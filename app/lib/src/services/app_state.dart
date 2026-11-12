import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock/mock_data.dart';
import '../models.dart';
import '../util/format.dart';
import '../util/mock_persist.dart' as persist;
import 'app_config.dart';
import 'supabase_data.dart';

/// アプリ全体の状態。
/// - モックモード: ドメイン状態はインメモリ（モックユーザーが自動で応募・返信する）
/// - Supabase モード（--dart-define でキー指定）: 募集・応募・チャット・DM は
///   実データ。モックの自動応答は無効化される。
class AppState extends ChangeNotifier {
  AppUser? me;
  bool gpsAvailable = false;
  double anchorLat = 35.6812; // デフォルトは東京駅（GPS が取れない場合のフォールバック）
  double anchorLng = 139.7671;

  final Map<String, AppUser> _users = {};
  final List<Recruitment> _recruitments = [];
  final List<JoinApplication> _applications = [];
  final List<ChatRoom> _rooms = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, int> unreadByRoom = {};
  final Map<String, List<CommunityEvent>> _eventsByCommunity = {};
  final List<Community> _communities = [];

  int _seq = 1;
  bool _closed = false;
  bool _seeded = false;
  bool _remoteBusy = false;
  final List<InterestCategory> _categories =
      List.of(interestCategories);

  bool get _remote => AppConfig.useSupabase;

  // ------------------------------------------------------------ categories

  static const _kCustomCategories = 'tsuritomo_custom_categories';

  /// 興味カテゴリ一覧（デフォルト + ユーザー追加分）
  List<InterestCategory> get categories => List.unmodifiable(_categories);

  /// IDからカテゴリを引く。未知の ID（他端末で作成など）は
  /// 名前をそのまま表示に使うフォールバックを返す（例外にしない）。
  InterestCategory categoryOf(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return InterestCategory(id, id, categoryIconByName(null));
  }

  /// ユーザーがカテゴリを追加する（Supabase モードでは全ユーザーに共有）。
  /// 同じ名前のカテゴリは作れない。メモリに先行追加してから永続化することで
  /// 並行して走る loadCategories との二重追加を防ぐ。
  Future<InterestCategory?> addCategory(
      {required String label, required String iconName}) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return null;
    final exists = _categories.any((c) => c.label == trimmed);
    if (exists) return null;
    final id = 'cat-${DateTime.now().microsecondsSinceEpoch}';
    final category = InterestCategory(
        id, trimmed, categoryIconByName(iconName));
    _categories.add(category);
    notifyListeners();
    if (_remote) {
      try {
        await supabaseData.createCategory(
            id: id, label: trimmed, icon: iconName);
      } catch (_) {
        // DB登録できない場合はロールバック（他端末で表示できないため）
        _categories.remove(category);
        notifyListeners();
        return null;
      }
    } else {
      // モック: 端末内に永続化
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getStringList(_kCustomCategories) ?? [];
        saved.add(jsonEncode({
          'id': id,
          'label': trimmed,
          'icon': iconName,
        }));
        await prefs.setStringList(_kCustomCategories, saved);
      } catch (_) {
        // 保存失敗でもメモリには残す（このセッション内では使える）
      }
    }
    return category;
  }

  /// ログイン時にカテゴリを復元/取得する
  Future<void> loadCategories() async {
    if (_remote) {
      await refreshCategoriesFromRemote();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kCustomCategories) ?? [];
      for (final json in saved) {
        try {
          final m = jsonDecode(json) as Map<String, dynamic>;
          final label = m['label'] as String;
          if (_categories.any((c) => c.label == label)) continue;
          _categories.add(InterestCategory(
            m['id'] as String,
            label,
            categoryIconByName(m['icon'] as String?),
          ));
        } catch (_) {
          // 壊れたレコードは読み飛ばす
        }
      }
    } catch (_) {
      // 無視
    }
  }

  Future<void> refreshCategoriesFromRemote() async {
    if (!_remote) return;
    try {
      final customs = await supabaseData.fetchCategories();
      // デフォルト + DBのカスタムカテゴリ（ラベル重複は排除）
      _categories
        ..clear()
        ..addAll(interestCategories);
      for (final c in customs) {
        if (!_categories.any((x) => x.label == c.label)) {
          _categories.add(c);
        }
      }
      notifyListeners();
    } catch (_) {
      // 無視
    }
  }

  AppState() {
    _rebuildMockUsers();
  }

  // ------------------------------------------------------------ blocks

  static const _kBlockedUsers = 'tsuritomo_blocked_users';
  final Set<String> _blockedUserIds = {};
  bool _blockedLoaded = false;

  /// ブロック中のユーザーID一覧
  List<String> get blockedUserIds => List.unmodifiable(_blockedUserIds);

  bool isBlocked(String userId) => _blockedUserIds.contains(userId);

  /// ログイン時にブロック一覧を復元/取得する。
  /// 並行して走る blockUser との競合を避けるため、クリアではなく追記のみ行う。
  Future<void> loadBlockedUsers() async {
    if (_blockedLoaded) return;
    _blockedLoaded = true;
    List<String> ids = const [];
    if (_remote) {
      try {
        ids = await supabaseData.fetchBlockedUserIds();
      } catch (_) {
        // 取得失敗時は空で続行（引き更新で再取得する）
      }
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        ids = prefs.getStringList(_kBlockedUsers) ?? [];
      } catch (_) {
        // 無視
      }
    }
    if (ids.isEmpty) return;
    _blockedUserIds.addAll(ids);
    notifyListeners();
  }

  /// ユーザーをブロックする。
  /// この人のプロフィール・募集・DM部屋が自分から見えなくなる。
  /// 相手には一切通知されない（ブロックされたことは相手側から分からない）。
  Future<void> blockUser(String userId) async {
    if (me == null || userId == me!.id) return;
    if (!_blockedUserIds.add(userId)) return;
    notifyListeners();
    if (_remote) {
      try {
        await supabaseData.blockUser(userId);
      } catch (_) {
        // 保存できない場合でもこのセッション内では有効
      }
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
            _kBlockedUsers, _blockedUserIds.toList());
      } catch (_) {
        // 保存失敗でもメモリには残る
      }
    }
  }

  /// ブロックを解除する（相手には通知されない）
  Future<void> unblockUser(String userId) async {
    if (!_blockedUserIds.remove(userId)) return;
    notifyListeners();
    if (_remote) {
      try {
        await supabaseData.unblockUser(userId);
      } catch (_) {
        // 無視
      }
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
            _kBlockedUsers, _blockedUserIds.toList());
      } catch (_) {
        // 無視
      }
    }
  }

  // ---------------------------------------------------------------- basics

  DateTime _now() => DateTime.now();

  AppUser userById(String id) => _users[id]!;

  /// 存在しない可能性があるユーザー（ブロック一覧の表示など）用
  AppUser? tryUserById(String id) => _users[id];

  Recruitment? recruitmentById(String id) {
    for (final r in _recruitments) {
      if (r.id == id) return r;
    }
    return null;
  }

  ChatRoom? roomById(String id) {
    for (final r in _rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<AppUser> get allUsers => _users.values.toList();

  /// 近くの一般ユーザー（自分以外、ビジネス除く、ブロック済みは非表示）
  List<AppUser> get generalUsers {
    if (me == null) return const [];
    return _users.values
        .where((u) =>
            u.id != me!.id && !u.isBusiness && !isBlocked(u.id))
        .toList();
  }

  /// 近くのビジネスユーザー（店舗。ブロック済みは非表示）
  List<BusinessUser> get businessUsers {
    return _users.values
        .whereType<BusinessUser>()
        .where((u) => !isBlocked(u.id))
        .toList();
  }

  /// リリース（ベータ配布）ビルドではモックデータを出さない。
  /// モックの一般ユーザー・店舗・シード募集・シードコミュニティ・
  /// シードの釣果速報は開発・テスト（デバッグ）ビルドのみ。
  bool get _useMockData => !kReleaseMode;

  void _rebuildMockUsers() {
    _users.clear();
    if (me != null) {
      _users[me!.id] = me!;
    }
    if (!_useMockData) return;
    final users = buildMockUsers(anchorLat, anchorLng);
    _users.addEntries(users.map((u) => MapEntry(u.id, u)));
    if (me != null) {
      _users[me!.id] = me!;
    }
  }

  /// 実 GPS で現在地を更新（モックユーザーが現在地の周囲に再配置される）。
  /// Supabase モードでは自分の位置 geohash を DB に反映して近傍を引き直す。
  void applyGps(double lat, double lng) {
    gpsAvailable = true;
    anchorLat = lat;
    anchorLng = lng;
    _rebuildMockUsers();
    _replaceMockCatchReportSeeds();
    if (me != null) {
      // ビジネスユーザーは店舗の位置（プロフィール位置）を GPS で
      // 更新しない（登録時に設定した位置に固定）
      if (!me!.isBusiness) {
        me = me!.withPosition(lat, lng);
        _users[me!.id] = me!;
      }
    }
    notifyListeners();
    if (_remote && me != null) {
      unawaited(refreshFromRemote());
    }
  }

  // ------------------------------------------------------------ account

  /// ログイン／会員登録後に呼ばれ、ドメイン状態を初期化する
  void attachUser(AppUser user, {bool reseed = false}) {
    me = user;
    _users[me!.id] = me!;
    unawaited(loadCategories());
    unawaited(loadBlockedUsers());
    if (_remote) {
      // Supabase モード: モックのシードは作らず実データを引きに行く
      unawaited(refreshFromRemote());
      unawaited(refreshCommunities());
      _seeded = true;
    } else if (reseed || !_seeded) {
      _seeded = true;
      // リリース（配布）ビルド: 端末内スナップショットの復元 → シード。
      // 開発・テストビルド: 復元は無いので同期でシードする
      if (_persistEnabled) {
        unawaited(_initMockDomain());
      } else {
        _seedMockDomain();
      }
    }
    notifyListeners();
  }

  /// モックモードのドメイン初期化（端末内スナップショットの復元つき）。
  /// 自分のデータ（募集・釣果・コミュニティ・部屋）を復元し、
  /// 開発ビルドではシードが無い場合だけモックデータを補う。
  Future<void> _initMockDomain() async {
    _persistBusy = true;
    await _loadDomainSnapshot();
    _persistBusy = false;
    _seedMockDomain();
    notifyListeners();
  }

  void _seedMockDomain() {
    if (!_useMockData) return;
    if (_recruitments.isEmpty) {
      _recruitments.addAll(seedRecruitments(_now(), _users.values
          .where((u) => u.id != me!.id && !u.isBusiness)
          .toList()));
    }
    _seedMockCommunities();
    _seedMockCatchReports();
  }

  /// ログアウト
  void detach() {
    // 保留中の保存を実行してから破棄する（直前の変更を取りこぼさない）
    _persistDebounce?.cancel();
    if (me != null && _persistEnabled && !_persistBusy) {
      unawaited(_saveDomainSnapshot());
    }
    me = null;
    // 再ログイン時にブロック一覧を読み直す（アカウントが変わる場合がある）
    _blockedLoaded = false;
    _blockedUserIds.clear();
    notifyListeners();
  }

  // ------------------------------------------------- mock persistence

  static const _kDomainSnapshot = 'tsuritomo_domain_state_v1';
  Timer? _persistDebounce;
  bool _persistBusy = false;

  /// リリース（配布）ビルドのモックモードでは、自分の募集・釣果速報・
  /// コミュニティ・部屋・メッセージを端末内に保存し、再起動後も残す。
  /// 開発・テストビルドではオフ（シード・テスト動作を壊さないため）。
  /// Supabase モードでは Postgres が永続化するため対象外。
  bool get _persistEnabled => kReleaseMode && !_remote;

  /// 状態変更に合わせて（1秒後に）スナップショットを保存する
  @override
  void notifyListeners() {
    super.notifyListeners();
    if (!_persistEnabled || me == null || _persistBusy) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 1), _saveDomainSnapshot);
  }

  Map<String, dynamic> _buildSnapshot() {
    final roomIds = _rooms
        .where((r) => r.memberIds.contains(me!.id))
        .map((r) => r.id)
        .toSet();
    final communityIds = _communities.map((c) => c.id).toSet();
    final events = <CommunityEvent>[];
    _eventsByCommunity.forEach((communityId, list) {
      if (communityIds.contains(communityId)) {
        events.addAll(list);
      }
    });
    return {
      'recruitments': _recruitments
          .where((r) => r.hostId == me!.id)
          .map(persist.recruitmentToMap)
          .toList(),
      'applications': _applications
          .where((a) =>
              a.applicantId == me!.id ||
              _recruitments.any((r) => r.id == a.recruitmentId && r.hostId == me!.id))
          .map(persist.joinApplicationToMap)
          .toList(),
      'rooms': _rooms
          .where((r) => r.memberIds.contains(me!.id))
          .map(persist.chatRoomToMap)
          .toList(),
      'messages': _messages.entries
          .expand((e) => e.value)
          .where((m) => roomIds.contains(m.roomId))
          .map(persist.chatMessageToMap)
          .toList(),
      'communities': _communities.map(persist.communityToMap).toList(),
      'events': events.map(persist.communityEventToMap).toList(),
      // シード(id付き cr-seed-)は保存しない（再ログイン時に再生成される）
      'catchReports': _catchReports
          .where((p) => p.reporterId == me!.id && !p.id.startsWith('cr-seed-'))
          .map(persist.catchReportToMap)
          .toList(),
    };
  }

  Future<void> _saveDomainSnapshot() async {
    final mine = me;
    if (mine == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDomainSnapshot, jsonEncode(_buildSnapshot()));
    } catch (_) {
      // 保存失敗は無視（メモリにはある）
    }
  }

  /// 端末内スナップショットを復元する（自分のデータのみ。他アカウントの
  /// 残骸は所有者チェックではじく）。
  Future<bool> _loadDomainSnapshot() async {
    if (!_persistEnabled) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDomainSnapshot);
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final pruned = persist.pruneSnapshotToOwner(decoded, me!.id);
      final recs = ((pruned['recruitments'] as List?) ?? const [])
          .map((e) => persist.recruitmentFromMap(e as Map<String, dynamic>))
          .whereType<Recruitment>();
      _recruitments
        ..clear()
        ..addAll(recs);
      _applications
        ..clear()
        ..addAll(((pruned['applications'] as List?) ?? const [])
            .map((e) =>
                persist.joinApplicationFromMap(e as Map<String, dynamic>))
            .whereType<JoinApplication>());
      _rooms
        ..clear()
        ..addAll(((pruned['rooms'] as List?) ?? const [])
            .map((e) => persist.chatRoomFromMap(e as Map<String, dynamic>))
            .whereType<ChatRoom>());
      _messages.clear();
      for (final m in ((pruned['messages'] as List?) ?? const [])
          .map((e) => persist.chatMessageFromMap(e as Map<String, dynamic>))
          .whereType<ChatMessage>()) {
        _messages.putIfAbsent(m.roomId, () => []).add(m);
      }
      unreadByRoom.clear();
      _communities
        ..clear()
        ..addAll(((pruned['communities'] as List?) ?? const [])
            .map((e) => persist.communityFromMap(e as Map<String, dynamic>))
            .whereType<Community>());
      _eventsByCommunity.clear();
      for (final e in ((pruned['events'] as List?) ?? const [])
          .map((e) => persist.communityEventFromMap(e as Map<String, dynamic>))
          .whereType<CommunityEvent>()) {
        _eventsByCommunity.putIfAbsent(e.communityId, () => []).add(e);
      }
      _catchReports
        ..clear()
        ..addAll(((pruned['catchReports'] as List?) ?? const [])
            .map((e) => persist.catchReportFromMap(e as Map<String, dynamic>))
            .whereType<CatchReport>());
      return true;
    } catch (_) {
      // 壊れたスナップショットは無視して普通に初期化
      return false;
    }
  }

  /// Supabase モード: 近くの人・募集・応募・部屋を実データから引き直す
  Future<void> refreshFromRemote() async {
    if (me == null || !AppConfig.useSupabase || _remoteBusy) return;
    _remoteBusy = true;
    try {
      await supabaseData.updateMyLocation(me!.lat, me!.lng);
      final (users, recsHosts) = await (
        supabaseData.fetchNearbyUsers(me!),
        supabaseData.fetchActiveRecruitments(me!)
      ).wait;
      // ユーザーマップを再構築（自分 + 実データ。モックは使わない）
      _users
        ..clear()
        ..addEntries(users.map((u) => MapEntry(u.id, u)));
      if (me != null) {
        _users[me!.id] = me!;
      }
      for (final h in recsHosts.$2) {
        _users[h.id] = h;
      }
      _recruitments
        ..clear()
        ..addAll(recsHosts.$1);
      // 自分の募集への応募
      final myRecs = _recruitments.where((r) => r.hostId == me!.id).toList();
      final (hostApps, appUsers) =
          await supabaseData.fetchHostApplications(myRecs);
      final myApps = await supabaseData.fetchMyApplications();
      _applications
        ..clear()
        ..addAll(hostApps)
        ..addAll(myApps);
      for (final u in appUsers) {
        _users[u.id] = u;
        // 応募者が募集に既に参加している場合（承認済み）に対応
      }
      // 承認済みの member_ids を募集に反映
      for (final app in _applications) {
        if (app.status == JoinStatus.accepted) {
          final rec = _recruitments.any((r) => r.id == app.recruitmentId)
              ? _recruitments.firstWhere((r) => r.id == app.recruitmentId)
              : null;
          if (rec != null && !rec.memberIds.contains(app.applicantId)) {
            final idx = _recruitments.indexOf(rec);
            _recruitments[idx] = Recruitment(
              id: rec.id,
              hostId: rec.hostId,
              genreId: rec.genreId,
              title: rec.title,
              body: rec.body,
              meetup: rec.meetup,
              capacity: rec.capacity,
              createdAt: rec.createdAt,
              expiresAt: rec.expiresAt,
              memberIds: [...rec.memberIds, app.applicantId],
            );
          }
        }
      }
      // 部屋
      final rooms = await supabaseData.fetchMyRooms();
      for (final room in rooms) {
        final exists = _rooms.any((r) => r.id == room.id);
        if (!exists) {
          _rooms.add(room);
          _messages.putIfAbsent(room.id, () => []);
        }
      }
      // 部屋のメンバー（ともつく！横断DMの相手を含む）のうち、
      // 取得できていないいるユーザーのプロフィールを補完する
      for (final room in rooms) {
        for (final memberId in room.memberIds) {
          if (memberId == me!.id || _users.containsKey(memberId)) continue;
          try {
            final member = await supabaseData.fetchAnyProfileById(memberId);
            if (member != null) _users[memberId] = member;
          } catch (_) {
            // 補完失敗は無視（次の更新で再試行）
          }
        }
      }
      // 釣果速報
      final reports = await supabaseData.fetchCatchReports(me!);
      _catchReports
        ..clear()
        ..addAll(reports);
      for (final rep in reports) {
        if (!_users.containsKey(rep.reporterId)) {
          try {
            final reporter = await supabaseData.fetchProfileById(rep.reporterId);
            if (reporter != null) _users[rep.reporterId] = reporter;
          } catch (_) {
            // 無視
          }
        }
      }
      unawaited(refreshCommunities());
      notifyListeners();
    } catch (_) {
      // ベータ: 通信エラーは画面を壊さず無視（次の更新で再試行）
    } finally {
      _remoteBusy = false;
    }
  }

  /// Supabase モード: 部屋のメッセージを引き直す（チャット画面と部屋一覧で使用）
  Future<void> reloadRoomMessages(String roomId) async {
    if (!AppConfig.useSupabase) return;
    try {
      final messages = await supabaseData.fetchMessages(roomId);
      _messages[roomId] = messages;
      notifyListeners();
    } catch (_) {
      // 無視
    }
  }

  /// リアルタイム着信（Supabase Realtime の INSERT から呼ばれる）。
  /// 重複チェックをして、自分以外の送信なら未読を増やす。
  void handleIncomingMessage(String roomId, ChatMessage message) {
    _messages.putIfAbsent(roomId, () => []);
    final exists = _messages[roomId]!.any((m) => m.id == message.id);
    if (exists) return;
    _messages[roomId]!.add(message);
    if (message.senderId != me?.id && !message.isSystem) {
      unreadByRoom[roomId] = (unreadByRoom[roomId] ?? 0) + 1;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ community

  List<Community> get communities => List.unmodifiable(_communities);

  Community? communityById(String id) {
    for (final c in _communities) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<CommunityEvent> eventsOf(String communityId) {
    return List.unmodifiable(_eventsByCommunity[communityId] ?? const []);
  }

  /// 参加中のコミュニティ
  List<Community> get myCommunities {
    if (me == null) return const [];
    return _communities
        .where((c) => c.memberIds.contains(me!.id))
        .toList();
  }

  /// 店舗シートから飛べる「ファンコミュニティ」を探す
  Community? fanCommunityOfStore(String storeName) {
    for (final c in _communities) {
      if (c.linkedStore == storeName) return c;
    }
    return null;
  }

  /// コミュニティまでの距離（メンバー・主催の中で最も近い人までの距離）
  double communityDistanceKm(Community c) {
    if (me == null) return double.infinity;
    var best = double.infinity;
    for (final id in c.memberIds) {
      final u = _users[id];
      if (u == null) continue;
      final km = haversineKm(me!.lat, me!.lng, u.lat, u.lng);
      if (km < best) best = km;
    }
    return best;
  }

  /// コミュニティまでの粗い距離バンド（位置不明なら空文字）
  String communityDistanceLabel(Community c) {
    final km = communityDistanceKm(c);
    return km.isFinite ? distanceLabel(km) : '';
  }

  /// 距離が近い順に並べたコミュニティ一覧
  List<Community> get nearbyCommunities {
    if (me == null) return const [];
    final list = List<Community>.of(communities)
      ..sort((a, b) =>
          communityDistanceKm(a).compareTo(communityDistanceKm(b)));
    return list;
  }

  void _seedMockCommunities() {
    // シードは開発用の固定IDで二重追加を防ぐ（自分のコミュニティが
    // あってもシードは補われる）
    const seedIds = {'c-shore', 'c-wadatsumi', 'c-photo'};
    if (_communities.any((c) => seedIds.contains(c.id))) return;
    final now = _now();
    _communities.addAll([
      Community(
        id: 'c-shore',
        ownerId: 'u-sabiki-tetsu',
        name: '堤防釣り部',
        description: '堤防釣りの情報交換と釣り場の清掃活動をする会。初心者歓迎。釣り場の話をしよう。',
        linkedStore: null,
        createdAt: now.subtract(const Duration(days: 12)),
        memberIds: {'u-sabiki-tetsu', 'u-nage-taro', 'u-bass-kai'},
      ),
      Community(
        id: 'c-wadatsumi',
        ownerId: 'b-toami-wadatsumi',
        name: 'わだつみ常連会',
        description: '渡船 わだつみ のファンコミュニティ。渡船グループの予約調整や釣果共有をします。',
        linkedStore: '渡船 わだつみ',
        createdAt: now.subtract(const Duration(days: 8)),
        memberIds: {'b-toami-wadatsumi', 'u-jig-gen', 'u-fukase-yuki'},
      ),
      Community(
        id: 'c-photo',
        ownerId: 'u-photo-yui',
        name: '釣果撮影クラブ',
        description: '釣果・風景の写真を交換する会。月1で撮影オフ会。',
        linkedStore: null,
        createdAt: now.subtract(const Duration(days: 3)),
        memberIds: {'u-photo-yui', 'u-eging-mari'},
      ),
    ]);
    _eventsByCommunity['c-shore'] = [
      CommunityEvent(
        id: 'e-shore-1',
        communityId: 'c-shore',
        hostId: 'u-sabiki-tetsu',
        title: '第4回 堤防清掃とサビキ釣り会',
        body: '朝イチで堤防の清掃をしてから、みんなでサビキ釣りをします。',
        eventTime: '今週土曜 6:00〜',
        locationName: '青海堤防 入口 集合',
        capacity: 6,
        createdAt: now.subtract(const Duration(days: 2)),
        participantIds: {'u-sabiki-tetsu', 'u-nage-taro'},
      ),
    ];
    _eventsByCommunity['c-wadatsumi'] = [
      CommunityEvent(
        id: 'e-wadatsumi-1',
        communityId: 'c-wadatsumi',
        hostId: 'b-toami-wadatsumi',
        title: '初心者ジギング講習会',
        body: '常連さん限定で初めての方へのジギングレクチャーをやります。',
        eventTime: '来週日曜 15:00〜',
        locationName: '渡船 わだつみ 受付',
        capacity: 10,
        createdAt: now.subtract(const Duration(days: 1)),
        participantIds: {'b-toami-wadatsumi'},
      ),
    ];
  }

  /// コミュニティ一覧の取得（ログイン時と引き更新で呼ぶ）
  Future<void> refreshCommunities() async {
    if (me == null) return;
    if (_remote) {
      try {
        final list = await supabaseData.fetchCommunities();
        // オーナー情報を補完
        for (final c in list) {
          if (!_users.containsKey(c.ownerId)) {
            try {
              final owner = await supabaseData.fetchProfileById(c.ownerId);
              if (owner != null) _users[c.ownerId] = owner;
            } catch (_) {
              // 無視
            }
          }
        }
        _communities
          ..clear()
          ..addAll(list);
        // 参加中コミュニティのイベントを取得
        for (final c in myCommunities) {
          final events = await supabaseData.fetchEvents(c.id);
          _eventsByCommunity[c.id] = events;
        }
        notifyListeners();
      } catch (_) {
        // 無視
      }
      return;
    }
    _seedMockCommunities();
    notifyListeners();
  }

  /// コミュニティ作成（誰でも可。ビジネスは自分の店舗のファンコミュニティ化も）
  Future<Community> createCommunity({
    required String name,
    required String description,
    String? linkedStore,
  }) async {
    if (_remote) {
      final c = await supabaseData.createCommunity(
        name: name,
        description: description,
        linkedStore: linkedStore,
      );
      // 自分を参加させておく（チャットも始まる）
      await supabaseData.joinCommunity(c.id);
      _communities.insert(0, c.copyWith(memberIds: {me!.id}));
      _ensureCommunityRoom(c.id);
      notifyListeners();
      return c;
    }
    final c = Community(
      id: 'c-${_seq++}',
      ownerId: me!.id,
      name: name,
      description: description,
      linkedStore: linkedStore,
      createdAt: _now(),
      memberIds: {me!.id},
    );
    _communities.insert(0, c);
    _ensureCommunityRoom(c.id);
    notifyListeners();
    return c;
  }

  void _ensureCommunityRoom(String communityId) {
    final exists = _rooms.any((r) => r.communityId == communityId);
    if (exists) return;
    final room = ChatRoom(
      id: 'croom-$communityId',
      recruitmentId: '',
      memberIds: [me!.id],
      createdAt: _now(),
      type: 'community',
      communityId: communityId,
    );
    _rooms.insert(0, room);
    _messages.putIfAbsent(room.id, () => []);
  }

  /// コミュニティ参加（チャット部屋にjoinする）
  Future<void> joinCommunity(String communityId) async {
    final idx = _communities.indexWhere((c) => c.id == communityId);
    if (idx < 0) return;
    final c = _communities[idx];
    if (c.memberIds.contains(me!.id)) return;
    _communities[idx] = c.copyWith(memberIds: {...c.memberIds, me!.id});
    // チャット部屋: 無ければ作り、メンバーに加える
    var room = _rooms.cast<ChatRoom?>().firstWhere(
          (r) => r!.communityId == communityId,
          orElse: () => null,
        );
    if (room == null) {
      room = ChatRoom(
        id: 'croom-$communityId',
        recruitmentId: '',
        memberIds: [me!.id],
        createdAt: _now(),
        type: 'community',
        communityId: communityId,
      );
      _rooms.insert(0, room);
    } else if (!room.memberIds.contains(me!.id)) {
      final rIdx = _rooms.indexOf(room);
      _rooms[rIdx] = ChatRoom(
        id: room.id,
        recruitmentId: room.recruitmentId,
        memberIds: [...room.memberIds, me!.id],
        createdAt: room.createdAt,
        type: room.type,
        communityId: room.communityId,
      );
    }
    _messages.putIfAbsent(room.id, () => []);
    // イベントも取得（Supabase）/ モックならシード済み
    if (!_eventsByCommunity.containsKey(communityId)) {
      if (_remote) {
        final events = await supabaseData.fetchEvents(communityId);
        _eventsByCommunity[communityId] = events;
      } else {
        _eventsByCommunity.putIfAbsent(communityId, () => []);
      }
    }
    if (_remote) {
      await supabaseData.joinCommunity(communityId);
    }
    notifyListeners();
  }

  /// コミュニティ脱退（チャットからも抜ける）
  Future<void> leaveCommunity(String communityId) async {
    final idx = _communities.indexWhere((c) => c.id == communityId);
    if (idx < 0) return;
    final c = _communities[idx];
    if (!c.memberIds.contains(me!.id)) return;
    final newMembers = {...c.memberIds}..remove(me!.id);
    _communities[idx] = c.copyWith(memberIds: newMembers);
    final roomIdx = _rooms.indexWhere((r) => r.communityId == communityId);
    if (roomIdx >= 0) {
      final room = _rooms[roomIdx];
      final newRoomMembers = [...room.memberIds]..remove(me!.id);
      if (newRoomMembers.isEmpty) {
        _rooms.removeAt(roomIdx);
        _messages.remove(room.id);
      } else {
        _rooms[roomIdx] = ChatRoom(
          id: room.id,
          recruitmentId: room.recruitmentId,
          memberIds: newRoomMembers,
          createdAt: room.createdAt,
          type: room.type,
          communityId: room.communityId,
        );
      }
    }
    if (_remote) {
      await supabaseData.leaveCommunity(communityId);
    }
    notifyListeners();
  }

  String communityRoomId(String communityId) {
    return 'croom-$communityId';
  }

  /// コミュニティ用のメッセージ投稿（既存の sendMessage を流用）
  Future<void> sendCommunityMessage(String communityId, String body) async {
    final roomId = communityRoomId(communityId);
    final realId = _rooms
        .cast<ChatRoom?>()
        .firstWhere((r) => r!.communityId == communityId,
            orElse: () => null)
        ?.id;
    final target = realId ?? roomId;
    // 既存の sendMessage を使う（Supabase 書き込みも含む）
    sendMessage(target, body);
    if (!_remote) {
      // モック: 他の参加者が反応する（デモ）
      final c = communityById(communityId);
      if (c != null) {
        final others =
            c.memberIds.where((id) => id != me!.id).toList();
        if (others.isNotEmpty) {
          _fakeDelay(const Duration(seconds: 3), () {
            _postMessage(target,
                senderId: others.first,
                body: mockReplies[_seq % mockReplies.length]);
            unreadByRoom[target] = (unreadByRoom[target] ?? 0) + 1;
            notifyListeners();
          });
        }
      }
    }
  }

  /// イベント・クラブの企画（参加者なら誰でも）
  Future<CommunityEvent> createEvent({
    required String communityId,
    required String title,
    required String body,
    required String eventTime,
    required String locationName,
    required int capacity,
  }) async {
    if (_remote) {
      final e = await supabaseData.createEvent(
        communityId: communityId,
        title: title,
        body: body,
        eventTime: eventTime,
        locationName: locationName,
        capacity: capacity,
      );
      _eventsByCommunity.putIfAbsent(communityId, () => []);
      _eventsByCommunity[communityId]!.add(e);
      notifyListeners();
      return e;
    }
    final e = CommunityEvent(
      id: 'e-${_seq++}',
      communityId: communityId,
      hostId: me!.id,
      title: title,
      body: body,
      eventTime: eventTime,
      locationName: locationName,
      capacity: capacity,
      createdAt: _now(),
      participantIds: {me!.id},
    );
    _eventsByCommunity.putIfAbsent(communityId, () => []);
    _eventsByCommunity[communityId]!.insert(0, e);
    notifyListeners();
    return e;
  }

  Future<void> joinEvent(String eventId) async {
    bool touched = false;
    for (final entry in _eventsByCommunity.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        if (e.id == eventId && !e.participantIds.contains(me!.id)) {
          if (e.isFull) return;
          list[i] = e.copyWith(
              participantIds: {...e.participantIds, me!.id});
          touched = true;
          break;
        }
      }
    }
    if (touched && _remote) {
      await supabaseData.joinEvent(eventId);
    }
    if (touched) notifyListeners();
  }

  Future<void> leaveEvent(String eventId) async {
    bool touched = false;
    for (final entry in _eventsByCommunity.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        if (e.id == eventId && e.participantIds.contains(me!.id)) {
          final p = {...e.participantIds}..remove(me!.id);
          list[i] = e.copyWith(participantIds: p);
          touched = true;
          break;
        }
      }
    }
    if (touched && _remote) {
      await supabaseData.leaveEvent(eventId);
    }
    if (touched) notifyListeners();
  }
  void updateProfile({
    required String nickname,
    required String decade,
    required String gender,
    required String iconCategoryId,
    required List<String> interestIds,
    required String bio,
    String? iconImagePath,
    String? websiteUrl,
    String? snsNote,
    String? phone,
    String? storeType,
  }) {
    final old = me!;
    if (old is BusinessUser) {
      me = BusinessUser(
        id: old.id,
        nickname: nickname,
        decade: decade,
        gender: gender,
        iconCategoryId: iconCategoryId,
        interestIds: interestIds,
        bio: bio,
        lat: old.lat,
        lng: old.lng,
        storeType: storeType ?? old.storeType,
        iconImagePath: _pickIcon(old.iconImagePath, iconImagePath),
        websiteUrl: websiteUrl ?? old.websiteUrl,
        snsNote: snsNote ?? old.snsNote,
        phone: phone ?? old.phone,
      );
    } else {
      me = AppUser(
        id: old.id,
        nickname: nickname,
        decade: decade,
        gender: gender,
        iconCategoryId: iconCategoryId,
        interestIds: interestIds,
        bio: bio,
        lat: old.lat,
        lng: old.lng,
        iconImagePath: _pickIcon(old.iconImagePath, iconImagePath),
        websiteUrl: websiteUrl ?? old.websiteUrl,
        snsNote: snsNote ?? old.snsNote,
        phone: phone ?? old.phone,
      );
    }
    _users[me!.id] = me!;
    notifyListeners();
  }

  String? _pickIcon(String? current, String? incoming) {
    if (incoming == null) return current; // 変更なし
    return incoming; // '' は解除、パスは新画像
  }

  // ------------------------------------------------------------ recruit

  /// 近くのアクティブな募集（距離近い順。ブロック済みユーザーの募集は非表示）。
  /// 未ログインなら空。
  List<Recruitment> activeRecruitments({String? genreId}) {
    if (me == null) return const [];
    final now = _now();
    final list = _recruitments
        .where((r) => r.isActiveAt(now) && !isBlocked(r.hostId))
        .toList()
      ..sort((a, b) {
        final da = haversineKm(
            me!.lat, me!.lng, _users[a.hostId]!.lat, _users[a.hostId]!.lng);
        final db = haversineKm(
            me!.lat, me!.lng, _users[b.hostId]!.lat, _users[b.hostId]!.lng);
        return da.compareTo(db);
      });
    if (genreId == null) return list;
    return list.where((r) => r.genreId == genreId).toList();
  }

  /// 募集までの粗い距離バンド
  String recruitmentDistanceLabel(Recruitment r) {
    if (r.hostId == me!.id) return 'あなたの募集';
    final km = haversineKm(
        me!.lat, me!.lng, _users[r.hostId]!.lat, _users[r.hostId]!.lng);
    return distanceLabel(km);
  }

  /// ユーザー（一般・ビジネス）までの粗い距離バンド
  String userDistanceLabel(AppUser u) {
    final mine = me;
    if (mine == null) return '';
    return distanceLabel(haversineKm(mine.lat, mine.lng, u.lat, u.lng));
  }

  Future<Recruitment> createRecruitment({
    required String genreId,
    required String title,
    required String body,
    required String meetup,
    required int capacity,
    required int expiryHours,
  }) async {
    if (_remote) {
      final rec = await supabaseData.createRecruitment(
        genreId: genreId,
        title: title,
        body: body,
        meetup: meetup,
        capacity: capacity,
        expiryHours: expiryHours,
      );
      _recruitments.insert(0, rec);
      notifyListeners();
      return rec;
    }
    final now = _now();
    final rec = Recruitment(
      id: 'r-${_seq++}',
      hostId: me!.id,
      genreId: genreId,
      title: title,
      body: body,
      meetup: meetup,
      capacity: capacity,
      createdAt: now,
      expiresAt: now.add(Duration(hours: expiryHours)),
      memberIds: [me!.id],
    );
    _recruitments.insert(0, rec);
    notifyListeners();
    _scheduleMockApplicants(rec);
    return rec;
  }

  /// デモ用: 自分の募集にモックユーザーが数秒後に応募してくる
  void _scheduleMockApplicants(Recruitment rec) {
    final candidates = _users.values
        .where((u) =>
            u.id != me!.id && !u.isBusiness && u.interestIds.isNotEmpty)
        .toList();
    if (candidates.isEmpty) return;
    _fakeDelay(const Duration(seconds: 4), () {
      final alive = recruitmentById(rec.id);
      if (alive == null ||
          !alive.isActiveAt(_now()) ||
          _applications.any((a) =>
              a.recruitmentId == rec.id &&
              a.applicantId == candidates.first.id)) {
        return;
      }
      _addApplication(
        recruitmentId: rec.id,
        applicantId: candidates.first.id,
        message: mockApplyMessages.first,
      );
    });
    if (candidates.length > 1) {
      _fakeDelay(const Duration(seconds: 12), () {
        final alive = recruitmentById(rec.id);
        if (alive == null || !alive.isActiveAt(_now())) return;
        final already = _applications.any((a) =>
            a.recruitmentId == rec.id && a.applicantId == candidates[1].id);
        if (already) return;
        _addApplication(
          recruitmentId: rec.id,
          applicantId: candidates[1].id,
          message: mockApplyMessages[1 % mockApplyMessages.length],
        );
      });
    }
  }

  void _addApplication({
    required String recruitmentId,
    required String applicantId,
    required String message,
  }) {
    if (_closed) return;
    _applications.add(JoinApplication(
      id: 'a-${_seq++}',
      recruitmentId: recruitmentId,
      applicantId: applicantId,
      message: message,
      status: JoinStatus.pending,
      createdAt: _now(),
    ));
    notifyListeners();
  }

  List<JoinApplication> applicationsFor(String recruitmentId) {
    return _applications
        .where((a) => a.recruitmentId == recruitmentId)
        .toList();
  }

  JoinApplication? myPendingApplication(String recruitmentId) {
    for (final a in _applications) {
      if (a.recruitmentId == recruitmentId &&
          a.applicantId == me!.id &&
          a.status == JoinStatus.pending) {
        return a;
      }
    }
    return null;
  }

  void applyTo(String recruitmentId, {required String message}) {
    final rec = recruitmentById(recruitmentId);
    if (rec == null || rec.hostId == me!.id) return;
    if (myPendingApplication(recruitmentId) != null) return;
    _addApplication(
      recruitmentId: recruitmentId,
      applicantId: me!.id,
      message: message,
    );
    if (_remote) {
      unawaited(supabaseData.insertApplication(recruitmentId, message));
      return; // 本物のホストがアプリで承認する（自動承認なし）
    }
    // デモ用: 数秒後にホストが承認する
    _fakeDelay(const Duration(seconds: 3), () {
      final app = myPendingApplication(recruitmentId);
      if (app == null) return;
      _acceptInternal(app);
    });
  }

  void acceptApplication(String applicationId) {
    JoinApplication? target;
    for (final a in _applications) {
      if (a.id == applicationId) target = a;
    }
    if (target == null || target.status != JoinStatus.pending) return;
    _acceptInternal(target);
  }

  void declineApplication(String applicationId) {
    for (final a in _applications) {
      if (a.id == applicationId) a.status = JoinStatus.declined;
    }
    if (_remote) {
      unawaited(
          supabaseData.setApplicationStatus(applicationId, JoinStatus.declined));
    }
    notifyListeners();
  }

  void _acceptInternal(JoinApplication app) {
    if (_closed) return;
    final rec = recruitmentById(app.recruitmentId);
    if (rec == null || rec.isFull || !rec.isActiveAt(_now())) return;
    if (app.status != JoinStatus.pending) return;

    app.status = JoinStatus.accepted;
    final updated = Recruitment(
      id: rec.id,
      hostId: rec.hostId,
      genreId: rec.genreId,
      title: rec.title,
      body: rec.body,
      meetup: rec.meetup,
      capacity: rec.capacity,
      createdAt: rec.createdAt,
      expiresAt: rec.expiresAt,
      memberIds: [...rec.memberIds, app.applicantId],
    );
    final idx = _recruitments.indexWhere((r) => r.id == rec.id);
    _recruitments[idx] = updated;

    final room = _ensureRoomFor(updated);
    _postMessage(room.id,
        senderId: 'system',
        body: '${_users[app.applicantId]?.nickname ?? '新しい参加者'}'
            ' さんが参加しました。',
        isSystem: true);
    unreadByRoom[room.id] = (unreadByRoom[room.id] ?? 0) + 1;
    notifyListeners();

    if (_remote) {
      // 実書き込み: ステータス・メンバー・部屋・システムメッセージ
      unawaited(() async {
        try {
          await supabaseData.setApplicationStatus(
              app.id, JoinStatus.accepted);
          await supabaseData.setRecruitmentMembers(
              updated.id, updated.memberIds);
          final dbRoom = await supabaseData.ensureGroupRoom(
              updated.id, updated.hostId);
          await supabaseData.addRoomMember(dbRoom.id, app.applicantId);
          await supabaseData.postMessage(dbRoom.id,
              '${_users[app.applicantId]?.nickname ?? '新しい参加者'}'
              ' さんが参加しました。',
              isSystem: true);
        } catch (_) {
          // 無視（次回の同期で回復）
        }
      }());
      return;
    }

    // デモ用: 参加者がひとこと挨拶する（モックのみ）
    if (app.applicantId != me!.id) {
      _fakeDelay(const Duration(seconds: 2), () {
        _postMessage(room.id,
            senderId: app.applicantId,
            body: mockReplies[2 % mockReplies.length]);
        unreadByRoom[room.id] = (unreadByRoom[room.id] ?? 0) + 1;
        notifyListeners();
      });
    }
  }

  ChatRoom _ensureRoomFor(Recruitment rec) {
    for (final room in _rooms) {
      if (room.recruitmentId == rec.id) return room;
    }
    final room = ChatRoom(
      id: 'room-${_seq++}',
      recruitmentId: rec.id,
      memberIds: List.of(rec.memberIds),
      createdAt: _now(),
      type: 'group',
    );
    _rooms.insert(0, room);
    _messages[room.id] = [];
    return room;
  }

  // ------------------------------------------------- catch reports

  final List<CatchReport> _catchReports = [];

  /// 掲載終了とブロック済みユーザーの投稿を除いた釣果速報の一覧
  /// （距離近い順）
  List<CatchReport> get catchReports {
    if (me == null) return const [];
    return _catchReports
        .where((r) => !r.closed && !isBlocked(r.reporterId))
        .toList()
      ..sort((a, b) => _catchReportKm(a).compareTo(_catchReportKm(b)));
  }

  double _catchReportKm(CatchReport r) {
    if (me == null) return double.infinity;
    return haversineKm(me!.lat, me!.lng, r.lat, r.lng);
  }

  /// 登録までの粗い距離バンド
  String catchReportDistanceLabel(CatchReport r) {
    final km = _catchReportKm(r);
    return km.isFinite ? distanceLabel(km) : '';
  }

  /// 釣果速報（海 / 川・湖）を登録する
  Future<CatchReport> registerCatchReport({
    required String kind,
    required String fishDescription,
    required String areaName,
    required String detail,
    String? photoPath,
  }) async {
    if (_remote) {
      // アップロード失敗で端末内パス（http で始まらない）が返ってきた場合、
      // 他の端末から見えないため photoPath として保存しない
      final effectivePhoto = (photoPath != null &&
              photoPath.isNotEmpty &&
              photoPath.startsWith('http'))
          ? photoPath
          : null;
      final created = await supabaseData.createCatchReport(
        kind: kind,
        fishDescription: fishDescription,
        areaName: areaName,
        detail: detail,
        photoPath: effectivePhoto,
        lat: me!.lat,
        lng: me!.lng,
      );
      _catchReports.insert(0, created);
      notifyListeners();
      return created;
    }
    final report = CatchReport(
      id: 'cr-${_seq++}',
      reporterId: me!.id,
      kind: kind,
      fishDescription: fishDescription,
      areaName: areaName,
      detail: detail,
      photoPath: photoPath,
      lat: me!.lat,
      lng: me!.lng,
      createdAt: _now(),
    );
    _catchReports.insert(0, report);
    notifyListeners();
    return report;
  }

  /// 登録を掲載終了にする（釣行が終わった、情報が古くなった等）
  Future<void> closeCatchReport(String id) async {
    for (final r in _catchReports) {
      if (r.id == id) {
        r.closed = true;
        break;
      }
    }
    notifyListeners();
    if (_remote) {
      try {
        await supabaseData.closeCatchReport(id);
      } catch (_) {
        // 無視（再取得で同期される）
      }
    }
  }

  /// モック: シードの釣果速報を現在地周囲に配置する
  void _seedMockCatchReports() {
    if (_catchReports.any((r) => r.id.startsWith('cr-seed-'))) return;
    _catchReports.addAll(buildSeedCatchReports(_now(), anchorLat, anchorLng));
  }

  /// 実 GPS で現在地が変わったら、シードの投稿も作り直す（開発ビルドのみ）
  void _replaceMockCatchReportSeeds() {
    if (_remote || !_useMockData) return;
    _catchReports.removeWhere((r) => r.id.startsWith('cr-seed-'));
    _catchReports.addAll(buildSeedCatchReports(_now(), anchorLat, anchorLng));
  }

  // ------------------------------------------------------------ rooms / DM

  List<ChatRoom> get myRooms {
    return _rooms.where((r) {
      if (me == null || !r.memberIds.contains(me!.id)) return false;
      // 相手をブロックしているDM部屋は一覧から消す
      if (r.isDm) {
        for (final id in r.memberIds) {
          if (id != me!.id && isBlocked(id)) return false;
        }
      }
      return true;
    }).toList();
  }

  List<ChatMessage> messagesOf(String roomId) => _messages[roomId] ?? const [];

  String lastMessageOf(String roomId) {
    final list = _messages[roomId];
    if (list == null || list.isEmpty) return '';
    return list.last.body;
  }

  void markRoomRead(String roomId) {
    unreadByRoom[roomId] = 0;
    if (_remote) {
      unawaited(supabaseData.markRoomRead(roomId));
    }
    notifyListeners();
  }

  /// 特定ユーザーとの DM ルームを取得（なければ作る）。
  /// [crossApp] が true の場合、他のともつく！アプリのユーザーとの
  /// 横断DM（app_id='cross' の部屋）を作る。
  Future<ChatRoom> getOrCreateDm(String otherUserId,
      {bool crossApp = false}) async {
    for (final room in _rooms) {
      if (room.isDm &&
          room.memberIds.contains(me!.id) &&
          room.memberIds.contains(otherUserId)) {
        return room;
      }
    }
    if (_remote) {
      final roomId = await supabaseData.getOrCreateDm(otherUserId,
          crossApp: crossApp);
      final room = ChatRoom(
        id: roomId,
        recruitmentId: '',
        memberIds: [me!.id, otherUserId],
        createdAt: _now(),
        type: 'dm',
      );
      _rooms.insert(0, room);
      _messages.putIfAbsent(room.id, () => []);
      notifyListeners();
      return room;
    }
    final room = ChatRoom(
      id: 'dm-${_seq++}',
      recruitmentId: '',
      memberIds: [me!.id, otherUserId],
      createdAt: _now(),
      type: 'dm',
    );
    _rooms.insert(0, room);
    _messages[room.id] = [];
    _postMessage(room.id,
        senderId: 'system',
        body:
            '${_users[otherUserId]!.nickname} さんとのDMを始めました。',
        isSystem: true);
    notifyListeners();
    return room;
  }

  void sendMessage(String roomId, String body) {
    _postMessage(roomId, senderId: me!.id, body: body);
    notifyListeners();
    if (_remote) {
      unawaited(supabaseData.postMessage(roomId, body));
      return;
    }
    // デモ用: 他の参加者が返信する
    final room = roomById(roomId);
    if (room == null) return;
    final others = room.memberIds.where((id) => id != me!.id).toList();
    if (others.isEmpty || others.every((id) => id == 'system')) return;
    _fakeDelay(const Duration(seconds: 3), () {
      _postMessage(roomId,
          senderId: others.first,
          body: mockReplies[_seq % mockReplies.length]);
      notifyListeners();
    });
  }

  void _postMessage(String roomId,
      {required String senderId, required String body, bool isSystem = false}) {
    if (_closed) return;
    _messages.putIfAbsent(roomId, () => []);
    _messages[roomId]!.add(ChatMessage(
      id: 'm-${_seq++}',
      roomId: roomId,
      senderId: senderId,
      body: body,
      sentAt: _now(),
      isSystem: isSystem,
    ));
  }

  // ------------------------------------------------------------ stats

  int get createdCount => _recruitments.where((r) => r.hostId == me!.id).length;

  int get joinedRoomsCount => myRooms.length;

  void _fakeDelay(Duration d, void Function() fn) {
    Future.delayed(d, () {
      if (!_closed) fn();
    });
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}

/// グローバルインスタンス（本開発では DI / Riverpod Provider に置き換える）
final AppState appState = AppState();
