import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../util/geohash.dart';

/// Supabase モードでのデータアクセス層。
/// AppState はモック（インメモリ）とこのクラスを AppConfig.useSupabase で切り替える。
/// 位置は geohash のみを扱い、生の緯度経度は DB に保存しない
/// （仕様書 6 章 位置情報プライバシー）。
class SupabaseData {
  SupabaseClient get _c => Supabase.instance.client;

  String get _myId => _c.auth.currentUser!.id;

  ChatMessage _rowToMessage(String roomId, Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as String,
      roomId: roomId,
      senderId: row['sender_id'] as String,
      body: row['body'] as String,
      sentAt: DateTime.parse(row['sent_at'] as String).toLocal(),
      isSystem: (row['is_system'] as bool?) ?? false,
    );
  }

  /// 部屋のメッセージ着信をリアルタイム受信する（Supabase Realtime）。
  /// 戻り値のチャネルは呼び出し側で dispose 時に removeChannel すること。
  RealtimeChannel subscribeRoomMessages({
    required String roomId,
    required void Function(ChatMessage) onMessage,
  }) {
    return _c
        .channel('room-messages-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final row = Map<String, dynamic>.from(payload.newRecord);
              onMessage(_rowToMessage(roomId, row));
            } catch (_) {
              // 壊れたペイロードは無視
            }
          },
        )
        .subscribe();
  }

  // ---------------------------------------------------------- profiles

  Future<void> updateMyLocation(double lat, double lng) async {
    await _c.from('profiles').update({
      'location_geohash': geohashEncode(lat, lng, precision: 6),
      'online': true,
    }).eq('id', _myId);
  }

  /// 近くの一般ユーザー / 店舗（geohash プレフィックス、近百人）
  Future<List<AppUser>> fetchNearbyUsers(AppUser me) async {
    final rows = await _c
        .from('profiles')
        .select()
        .neq('id', _myId)
        .not('location_geohash', 'is', null)
        .limit(100);
    final users = <AppUser>[];
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      try {
        users.add(_rowToUser(row));
      } catch (_) {
        // 壊れた行は読み飛ばす
      }
    }
    // 近傍（geohash 先頭4桁一致 = 約20km四方）だけ残す
    final myPrefix = geohashEncode(me.lat, me.lng, precision: 4);
    return users
        .where((u) =>
            u.nickname.isNotEmpty &&
            (geohashEncode(u.lat, u.lng, precision: 4) == myPrefix))
        .toList();
  }

  AppUser _rowToUser(Map<String, dynamic> row) {
    final gh = row['location_geohash'] as String?;
    final (lat, lng) =
        gh == null ? (35.6812, 139.7671) : geohashDecode(gh);
    final isBusiness = row['role'] == 'business';
    if (isBusiness) {
      return BusinessUser(
        id: row['id'] as String,
        nickname: (row['nickname'] as String?) ?? '店舗',
        decade: (row['birth_decade'] as String?) ?? '経営者',
        gender: row['gender'] as String? ?? 'undisclosed',
        iconCategoryId: row['icon_category_id'] as String? ?? 'sabiki',
        interestIds:
            ((row['interest_ids'] as List?) ?? const []).cast<String>(),
        bio: (row['bio'] as String?) ?? '',
        lat: lat,
        lng: lng,
        storeType: (row['store_type'] as String?) ?? '店舗',
        websiteUrl: row['website_url'] as String?,
        snsNote: row['sns_note'] as String?,
        phone: row['phone'] as String?,
      );
    }
    return AppUser(
      id: row['id'] as String,
      nickname: (row['nickname'] as String?) ?? '名無し',
      decade: (row['birth_decade'] as String?) ?? '非公開',
      gender: row['gender'] as String? ?? 'undisclosed',
      iconCategoryId: row['icon_category_id'] as String? ?? 'sabiki',
      interestIds: ((row['interest_ids'] as List?) ?? const []).cast<String>(),
      bio: (row['bio'] as String?) ?? '',
      lat: lat,
      lng: lng,
      websiteUrl: row['website_url'] as String?,
      snsNote: row['sns_note'] as String?,
      phone: row['phone'] as String?,
    );
  }

  // ---------------------------------------------------------- recruitments

  Future<Recruitment> createRecruitment({
    required String genreId,
    required String title,
    required String body,
    required String meetup,
    required int capacity,
    required int expiryHours,
  }) async {
    final now = DateTime.now().toUtc();
    final rows = await _c.from('recruitments').insert({
      'host_id': _myId,
      'genre_id': genreId,
      'title': title,
      'body': body,
      'meetup': meetup,
      'capacity': capacity,
      'expires_at': now.add(Duration(hours: expiryHours)).toIso8601String(),
      'status': 'active',
    }).select();
    final row = (rows as List).first as Map<String, dynamic>;
    return Recruitment(
      id: row['id'] as String,
      hostId: _myId,
      genreId: genreId,
      title: title,
      body: body,
      meetup: meetup,
      capacity: capacity,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
      memberIds: [row['host_id'] as String],
    );
  }

  /// アクティブな募集（新着順、最大50件。ホストのプロフィールも一緒に返す）
  Future<(List<Recruitment>, List<AppUser>)> fetchActiveRecruitments(
      AppUser me) async {
    final rows = await _c
        .from('recruitments')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(50);
    final recs = <Recruitment>[];
    final hostIds = <String>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final expiresAt = DateTime.parse(row['expires_at'] as String).toLocal();
      if (expiresAt.isBefore(DateTime.now())) continue;
      final memberIds =
          ((row['member_ids'] as List?) ?? const []).cast<String>().toList();
      final hostId = row['host_id'] as String;
      hostIds.add(hostId);
      recs.add(Recruitment(
        id: row['id'] as String,
        hostId: hostId,
        genreId: row['genre_id'] as String,
        title: row['title'] as String,
        body: (row['body'] as String?) ?? '',
        meetup: (row['meetup'] as String?) ?? '',
        capacity: (row['capacity'] as int?) ?? 3,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        expiresAt: expiresAt,
        memberIds: memberIds.contains(hostId) ? memberIds : [hostId, ...memberIds],
      ));
    }
    if (hostIds.isEmpty) return (recs, <AppUser>[]);
    final profileRows =
        await _c.from('profiles').select().inFilter('id', hostIds.toList());
    final hosts = (profileRows as List)
        .map((r) => _rowToUser(r as Map<String, dynamic>))
        .toList();
    return (recs, hosts);
  }

  Future<void> setRecruitmentMembers(
      String recruitmentId, List<String> memberIds) async {
    await _c.from('recruitments').update({
      'member_ids': memberIds,
      'status': 'active', // 満員時はクライアントで fulfilled 判定する
    }).eq('id', recruitmentId);
  }

  // ---------------------------------------------------------- applications

  Future<void> insertApplication(String recruitmentId, String message) async {
    await _c.from('join_applications').upsert({
      'recruitment_id': recruitmentId,
      'applicant_id': _myId,
      'message': message,
      'status': 'pending',
    });
  }

  /// 主催者として受けた応募 + 応募者のプロフィール。
  /// （host の募集に限る。RLS により自分の募集への応募のみ見える）
  Future<(List<JoinApplication>, List<AppUser>)> fetchHostApplications(
      List<Recruitment> myRecruitments) async {
    if (myRecruitments.isEmpty) {
      return (<JoinApplication>[], <AppUser>[]);
    }
    final ids = myRecruitments.map((r) => r.id).toList();
    final rows = await _c
        .from('join_applications')
        .select()
        .inFilter('recruitment_id', ids)
        .order('created_at');
    final apps = <JoinApplication>[];
    final applicants = <String>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      apps.add(_rowToApplication(row));
      applicants.add(row['applicant_id'] as String);
    }
    if (applicants.isEmpty) return (apps, const <AppUser>[]);
    final profileRows =
        await _c.from('profiles').select().inFilter('id', applicants.toList());
    final users = (profileRows as List)
        .map((r) => _rowToUser(r as Map<String, dynamic>))
        .toList();
    return (apps, users);
  }

  /// 自分が応募した側のステータス
  Future<List<JoinApplication>> fetchMyApplications() async {
    final rows = await _c
        .from('join_applications')
        .select()
        .eq('applicant_id', _myId)
        .order('created_at');
    return (rows as List)
        .map((r) => _rowToApplication(r as Map<String, dynamic>))
        .toList();
  }

  JoinApplication _rowToApplication(Map<String, dynamic> row) {
    return JoinApplication(
      id: row['id'] as String,
      recruitmentId: row['recruitment_id'] as String,
      applicantId: row['applicant_id'] as String,
      message: (row['message'] as String?) ?? '',
      status: switch (row['status'] as String?) {
        'accepted' => JoinStatus.accepted,
        'declined' => JoinStatus.declined,
        _ => JoinStatus.pending,
      },
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  Future<void> setApplicationStatus(String applicationId, JoinStatus status) async {
    await _c.from('join_applications').update({
      'status': status == JoinStatus.accepted
          ? 'accepted'
          : status == JoinStatus.declined
              ? 'declined'
              : 'pending',
    }).eq('id', applicationId);
  }

  // ---------------------------------------------------------- rooms / DM

  Future<ChatRoom> ensureGroupRoom(String recruitmentId, String hostId) async {
    final existingRows =
        (await _c.from('chat_rooms').select().eq('recruitment_id', recruitmentId).limit(1))
            as List;
    if (existingRows.isNotEmpty) {
      final row = Map<String, dynamic>.from(existingRows.first as Map);
      final members = await _roomMembers(row['id'] as String);
      return ChatRoom(
        id: row['id'] as String,
        recruitmentId: recruitmentId,
        memberIds: members,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }
    final created = await _c.from('chat_rooms').insert({
      'recruitment_id': recruitmentId,
      'type': 'group',
    }).select();
    final row = (created as List).first as Map<String, dynamic>;
    final roomId = row['id'] as String;
    await _c.from('chat_room_members').upsert([
      {'room_id': roomId, 'user_id': hostId},
      {'room_id': roomId, 'user_id': _myId},
    ]);
    return ChatRoom(
      id: roomId,
      recruitmentId: recruitmentId,
      memberIds: [hostId, _myId],
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  Future<void> addRoomMember(String roomId, String userId) async {
    await _c.from('chat_room_members').upsert({
      'room_id': roomId,
      'user_id': userId,
    });
  }

  Future<List<String>> _roomMembers(String roomId) async {
    final rows =
        await _c.from('chat_room_members').select('user_id').eq('room_id', roomId);
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['user_id'] as String)
        .toList();
  }

  /// DM の部屋を取得（なければ作成）。戻り値は roomId
  Future<String> getOrCreateDm(String otherUserId) async {
    final res = await _c.rpc('get_or_create_dm', params: {
      'p_other_user': otherUserId,
    });
    return res as String;
  }

  Future<void> postMessage(String roomId, String body,
      {bool isSystem = false}) async {
    await _c.from('chat_messages').insert({
      'room_id': roomId,
      'sender_id': _myId,
      'body': body,
      'is_system': isSystem,
    });
  }

  Future<List<ChatMessage>> fetchMessages(String roomId) async {
    final rows = await _c
        .from('chat_messages')
        .select()
        .eq('room_id', roomId)
        .order('sent_at')
        .limit(200);
    return (rows as List).map((r) {
      final row = r as Map<String, dynamic>;
      return ChatMessage(
        id: row['id'] as String,
        roomId: roomId,
        senderId: row['sender_id'] as String,
        body: row['body'] as String,
        sentAt: DateTime.parse(row['sent_at'] as String).toLocal(),
        isSystem: (row['is_system'] as bool?) ?? false,
      );
    }).toList();
  }

  Future<void> markRoomRead(String roomId) async {
    await _c.from('chat_room_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('room_id', roomId)
        .eq('user_id', _myId);
  }

  /// 自分が参加している部屋（メンバー一覧も取得）
  Future<List<ChatRoom>> fetchMyRooms() async {
    final rows = await _c
        .from('chat_room_members')
        .select('room_id, chat_rooms!inner(id, recruitment_id, type, created_at)')
        .eq('user_id', _myId)
        .order('joined_at', ascending: false)
        .limit(20);
    final rooms = <ChatRoom>[];
    final roomIds = <String>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final room = r['chat_rooms'] as Map<String, dynamic>;
      final id = room['id'] as String;
      roomIds.add(id);
      rooms.add(ChatRoom(
        id: id,
        recruitmentId: (room['recruitment_id'] as String?) ?? '',
        memberIds: const [],
        createdAt: DateTime.parse(room['created_at'] as String).toLocal(),
        type: (room['type'] as String?) ?? 'group',
      ));
    }
    if (roomIds.isEmpty) return rooms;
    // 全メンバーを一括取得して rooms に反映
    final memberRows = await _c
        .from('chat_room_members')
        .select('room_id, user_id')
        .inFilter('room_id', roomIds);
    final membersByRoom = <String, List<String>>{};
    for (final r in (memberRows as List).cast<Map<String, dynamic>>()) {
      membersByRoom
          .putIfAbsent(r['room_id'] as String, () => [])
          .add(r['user_id'] as String);
    }
    return rooms
        .map((room) => ChatRoom(
              id: room.id,
              recruitmentId: room.recruitmentId,
              memberIds:
                  membersByRoom[room.id] ?? [_myId],
              createdAt: room.createdAt,
              type: room.type,
            ))
        .toList();
  }
}

/// グローバルインスタンス
final SupabaseData supabaseData = SupabaseData();

extension CommunityData on SupabaseData {
  // ------------------------------------------------------------ community

  /// ユーザー追加のカテゴリ一覧（全ユーザーに共有される）
  Future<List<InterestCategory>> fetchCategories() async {
    final rows = await _c
        .from('categories')
        .select()
        .order('created_at', ascending: false)
        .limit(200);
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return InterestCategory(
        m['id'] as String,
        m['label'] as String,
        categoryIconByName(m['icon'] as String?),
      );
    }).toList();
  }

  Future<void> createCategory({
    required String id,
    required String label,
    required String icon,
  }) async {
    await _c.from('categories').insert({
      'id': id,
      'label': label,
      'icon': icon,
      'created_by': _myId,
    });
  }

  /// 1人のプロフィールを取得（コミュニティオーナー等の補完に使う）
  Future<AppUser?> fetchProfileById(String id) async {
    final rows = await _c.from('profiles').select().eq('id', id).limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return _rowToUser(Map<String, dynamic>.from(list.first as Map));
  }

  /// コミュニティ一覧（参加メンバーの id も一緒に取得）
  Future<List<Community>> fetchCommunities() async {
    final rows = await _c
        .from('communities')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    final list = <Community>[];
    final ids = <String>[];
    for (final row in (rows as List)) {
      final m = Map<String, dynamic>.from(row as Map);
      ids.add(m['id'] as String);
      list.add(Community(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        name: m['name'] as String,
        description: (m['description'] as String?) ?? '',
        linkedStore: m['linked_store'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        memberIds: <String>{},
      ));
    }
    if (ids.isEmpty) return list;
    final memberRows = await _c
        .from('community_members')
        .select('community_id, user_id')
        .inFilter('community_id', ids);
    for (final r in (memberRows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      for (final c in list) {
        if (c.id == m['community_id']) {
          c.memberIds.add(m['user_id'] as String);
        }
      }
    }
    return list;
  }

  Future<Community> createCommunity({
    required String name,
    required String description,
    String? linkedStore,
  }) async {
    final rows = await _c.from('communities').insert({
      'owner_id': _myId,
      'name': name,
      'description': description,
      'linked_store': linkedStore,
    }).select();
    final m = Map<String, dynamic>.from((rows as List).first as Map);
    return Community(
      id: m['id'] as String,
      ownerId: _myId,
      name: name,
      description: description,
      linkedStore: linkedStore,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      memberIds: {_myId},
    );
  }

  Future<void> joinCommunity(String communityId) async {
    await _c.from('community_members')
        .upsert({'community_id': communityId, 'user_id': _myId});
    await _joinCommunityRoom(communityId);
  }

  /// コミュニティのチャット部屋（chat_rooms を流用）。参加時に作る
  Future<String> _joinCommunityRoom(String communityId) async {
    final existing = await _c
        .from('chat_rooms')
        .select()
        .eq('community_id', communityId)
        .limit(1);
    if ((existing as List).isNotEmpty) {
      final roomId =
          Map<String, dynamic>.from(existing.first as Map)['id'] as String;
      await _c.from('chat_room_members')
          .upsert({'room_id': roomId, 'user_id': _myId});
      return roomId;
    }
    final created = await _c.from('chat_rooms').insert({
      'community_id': communityId,
      'type': 'community',
    }).select();
    final roomId =
        Map<String, dynamic>.from((created as List).first as Map)['id']
            as String;
    await _c.from('chat_room_members')
        .upsert({'room_id': roomId, 'user_id': _myId});
    return roomId;
  }

  Future<void> leaveCommunity(String communityId) async {
    await _c.from('community_members')
        .delete()
        .eq('community_id', communityId)
        .eq('user_id', _myId);
    final rooms = await _c
        .from('chat_rooms')
        .select('id')
        .eq('community_id', communityId)
        .limit(1);
    if ((rooms as List).isNotEmpty) {
      final roomId = Map<String, dynamic>.from(rooms.first as Map)['id']
          as String;
      await _c.from('chat_room_members')
          .delete()
          .eq('room_id', roomId)
          .eq('user_id', _myId);
    }
  }

  // ------------------------------------------------------------ events

  Future<List<CommunityEvent>> fetchEvents(String communityId) async {
    final rows = await _c
        .from('events')
        .select()
        .eq('community_id', communityId)
        .order('created_at')
        .limit(50);
    final list = <CommunityEvent>[];
    final ids = <String>[];
    for (final row in (rows as List)) {
      final m = Map<String, dynamic>.from(row as Map);
      ids.add(m['id'] as String);
      list.add(CommunityEvent(
        id: m['id'] as String,
        communityId: communityId,
        hostId: m['host_id'] as String,
        title: m['title'] as String,
        body: (m['body'] as String?) ?? '',
        eventTime: (m['event_time'] as String?) ?? '',
        locationName: (m['location_name'] as String?) ?? '',
        capacity: (m['capacity'] as int?) ?? 20,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        participantIds: <String>{},
      ));
    }
    if (ids.isEmpty) return list;
    final parts = await _c
        .from('event_participants')
        .select('event_id, user_id')
        .inFilter('event_id', ids);
    for (final r in (parts as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      for (final e in list) {
        if (e.id == m['event_id']) {
          e.participantIds.add(m['user_id'] as String);
        }
      }
    }
    return list;
  }

  Future<CommunityEvent> createEvent({
    required String communityId,
    required String title,
    required String body,
    required String eventTime,
    required String locationName,
    required int capacity,
  }) async {
    final rows = await _c.from('events').insert({
      'community_id': communityId,
      'host_id': _myId,
      'title': title,
      'body': body,
      'event_time': eventTime,
      'location_name': locationName,
      'capacity': capacity,
    }).select();
    final m = Map<String, dynamic>.from((rows as List).first as Map);
    return CommunityEvent(
      id: m['id'] as String,
      communityId: communityId,
      hostId: _myId,
      title: title,
      body: body,
      eventTime: eventTime,
      locationName: locationName,
      capacity: capacity,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      participantIds: {_myId},
    );
  }

  Future<void> joinEvent(String eventId) async {
    await _c.from('event_participants')
        .upsert({'event_id': eventId, 'user_id': _myId});
  }

  Future<void> leaveEvent(String eventId) async {
    await _c.from('event_participants')
        .delete()
        .eq('event_id', eventId)
        .eq('user_id', _myId);
  }

  // ---------------------------------------------------------- blocks

  /// ブロック中のユーザーID一覧（RLS: 本人の行のみ参照可能）
  Future<List<String>> fetchBlockedUserIds() async {
    final rows =
        await _c.from('blocks').select('blocked_id').eq('blocker_id', _myId);
    return [
      for (final r in rows as List) r['blocked_id'] as String,
    ];
  }

  /// ブロックする。相手には通知しない（RLS: 相手は本テーブルを読めない）
  Future<void> blockUser(String userId) async {
    await _c.from('blocks').upsert({
      'blocker_id': _myId,
      'blocked_id': userId,
    });
  }

  /// ブロックを解除する
  Future<void> unblockUser(String userId) async {
    await _c.from('blocks').delete().match({
      'blocker_id': _myId,
      'blocked_id': userId,
    });
  }

  // ---------------------------------------------------- catch reports

  CatchReport _rowToCatchReport(Map<String, dynamic> row) {
    final gh = row['location_geohash'] as String?;
    final (lat, lng) =
        gh == null ? (0.0, 0.0) : geohashDecode(gh);
    return CatchReport(
      id: row['id'] as String,
      reporterId: row['reporter_id'] as String,
      kind: row['kind'] as String,
      fishDescription: row['fish_description'] as String,
      areaName: row['area_name'] as String,
      detail: (row['detail'] as String?) ?? '',
      photoPath: row['photo_path'] as String?,
      lat: lat,
      lng: lng,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      closed: (row['closed'] as bool?) ?? false,
    );
  }

  /// 近くの釣果速報の登録（geohash 先頭4桁一致 = 約20km四方）
  Future<List<CatchReport>> fetchCatchReports(AppUser me) async {
    final rows = await _c
        .from('catch_reports')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    final myPrefix = geohashEncode(me.lat, me.lng, precision: 4);
    final reports = <CatchReport>[];
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      try {
        final gh = row['location_geohash'] as String?;
        if (gh == null || !gh.startsWith(myPrefix)) continue;
        reports.add(_rowToCatchReport(row));
      } catch (_) {
        // 壊れた行は読み飛ばす
      }
    }
    return reports;
  }

  /// 釣果速報を登録する
  Future<CatchReport> createCatchReport({
    required String kind,
    required String fishDescription,
    required String areaName,
    required String detail,
    required double lat,
    required double lng,
    String? photoPath,
  }) async {
    final rows = await _c.from('catch_reports').insert({
      'reporter_id': _myId,
      'kind': kind,
      'fish_description': fishDescription,
      'area_name': areaName,
      'detail': detail,
      'photo_path': photoPath,
      'location_geohash': geohashEncode(lat, lng, precision: 6),
    }).select();
    return _rowToCatchReport((rows as List).first as Map<String, dynamic>);
  }

  /// 登録を掲載終了にする（本人のみ、RLSで担保）
  Future<void> closeCatchReport(String id) async {
    await _c.from('catch_reports').update({'closed': true}).eq('id', id);
  }
}
