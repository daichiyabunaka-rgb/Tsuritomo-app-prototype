import '../models.dart';

/// モックモードでのドメイン状態の端末内保存・復元用の変換関数群。
/// Supabase モードでは使わない（Postgres が永続化を担う）。
/// 不正なレコードは例外を投げず null を返す（壊れた1件で全体を落とさない）。

Map<String, dynamic> recruitmentToMap(Recruitment r) => {
      'id': r.id,
      'hostId': r.hostId,
      'genreId': r.genreId,
      'title': r.title,
      'body': r.body,
      'meetup': r.meetup,
      'capacity': r.capacity,
      'createdAt': r.createdAt.toIso8601String(),
      'expiresAt': r.expiresAt.toIso8601String(),
      'memberIds': r.memberIds,
    };

Recruitment? recruitmentFromMap(Map<String, dynamic> m) {
  try {
    return Recruitment(
      id: m['id'] as String,
      hostId: m['hostId'] as String,
      genreId: m['genreId'] as String,
      title: m['title'] as String,
      body: m['body'] as String,
      meetup: m['meetup'] as String,
      capacity: m['capacity'] as int,
      createdAt: DateTime.parse(m['createdAt'] as String),
      expiresAt: DateTime.parse(m['expiresAt'] as String),
      memberIds: (m['memberIds'] as List).cast<String>(),
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> joinApplicationToMap(JoinApplication a) => {
      'id': a.id,
      'recruitmentId': a.recruitmentId,
      'applicantId': a.applicantId,
      'message': a.message,
      'status': a.status.name,
      'createdAt': a.createdAt.toIso8601String(),
    };

JoinApplication? joinApplicationFromMap(Map<String, dynamic> m) {
  try {
    return JoinApplication(
      id: m['id'] as String,
      recruitmentId: m['recruitmentId'] as String,
      applicantId: m['applicantId'] as String,
      message: m['message'] as String,
      status: JoinStatus.values
          .firstWhere((s) => s.name == (m['status'] as String?)),
      createdAt: DateTime.parse(m['createdAt'] as String),
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> chatRoomToMap(ChatRoom r) => {
      'id': r.id,
      'recruitmentId': r.recruitmentId,
      'memberIds': r.memberIds,
      'createdAt': r.createdAt.toIso8601String(),
      'type': r.type,
      'communityId': r.communityId,
    };

ChatRoom? chatRoomFromMap(Map<String, dynamic> m) {
  try {
    return ChatRoom(
      id: m['id'] as String,
      recruitmentId: m['recruitmentId'] as String? ?? '',
      memberIds: (m['memberIds'] as List).cast<String>(),
      createdAt: DateTime.parse(m['createdAt'] as String),
      type: (m['type'] as String?) ?? 'group',
      communityId: m['communityId'] as String?,
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> chatMessageToMap(ChatMessage m) => {
      'id': m.id,
      'roomId': m.roomId,
      'senderId': m.senderId,
      'body': m.body,
      'sentAt': m.sentAt.toIso8601String(),
      'isSystem': m.isSystem,
    };

ChatMessage? chatMessageFromMap(Map<String, dynamic> m) {
  try {
    return ChatMessage(
      id: m['id'] as String,
      roomId: m['roomId'] as String,
      senderId: m['senderId'] as String,
      body: m['body'] as String,
      sentAt: DateTime.parse(m['sentAt'] as String),
      isSystem: (m['isSystem'] as bool?) ?? false,
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> communityToMap(Community c) => {
      'id': c.id,
      'ownerId': c.ownerId,
      'name': c.name,
      'description': c.description,
      'linkedStore': c.linkedStore,
      'createdAt': c.createdAt.toIso8601String(),
      'memberIds': c.memberIds.toList(),
    };

Community? communityFromMap(Map<String, dynamic> m) {
  try {
    return Community(
      id: m['id'] as String,
      ownerId: m['ownerId'] as String,
      name: m['name'] as String,
      description: m['description'] as String,
      linkedStore: m['linkedStore'] as String?,
      createdAt: DateTime.parse(m['createdAt'] as String),
      memberIds: (m['memberIds'] as List).cast<String>().toSet(),
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> communityEventToMap(CommunityEvent e) => {
      'id': e.id,
      'communityId': e.communityId,
      'hostId': e.hostId,
      'title': e.title,
      'body': e.body,
      'eventTime': e.eventTime,
      'locationName': e.locationName,
      'capacity': e.capacity,
      'createdAt': e.createdAt.toIso8601String(),
      'participantIds': e.participantIds.toList(),
    };

CommunityEvent? communityEventFromMap(Map<String, dynamic> m) {
  try {
    return CommunityEvent(
      id: m['id'] as String,
      communityId: m['communityId'] as String,
      hostId: m['hostId'] as String,
      title: m['title'] as String,
      body: m['body'] as String,
      eventTime: m['eventTime'] as String,
      locationName: m['locationName'] as String,
      capacity: m['capacity'] as int,
      createdAt: DateTime.parse(m['createdAt'] as String),
      participantIds: (m['participantIds'] as List).cast<String>().toSet(),
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> catchReportToMap(CatchReport r) => {
      'id': r.id,
      'reporterId': r.reporterId,
      'kind': r.kind,
      'fishDescription': r.fishDescription,
      'areaName': r.areaName,
      'detail': r.detail,
      'photoPath': r.photoPath,
      'lat': r.lat,
      'lng': r.lng,
      'createdAt': r.createdAt.toIso8601String(),
      'closed': r.closed,
    };

CatchReport? catchReportFromMap(Map<String, dynamic> m) {
  try {
    final report = CatchReport(
      id: m['id'] as String,
      reporterId: m['reporterId'] as String,
      kind: m['kind'] as String,
      fishDescription: m['fishDescription'] as String,
      areaName: m['areaName'] as String,
      detail: m['detail'] as String,
      photoPath: m['photoPath'] as String?,
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      createdAt: DateTime.parse(m['createdAt'] as String),
      closed: m['closed'] as bool? ?? false,
    );
    return report;
  } catch (_) {
    return null;
  }
}

/// 保存済みスナップショットを「自分のもの」だけに刈り込む。
/// 別アカウントで同じ端末からログインした場合に前アカウントの
/// データが混ざらないための防護。
Map<String, dynamic> pruneSnapshotToOwner(
    Map<String, dynamic> snapshot, String myId) {
  final now = DateTime.now();
  final recs = ((snapshot['recruitments'] as List?) ?? const [])
      .map((e) => e as Map<String, dynamic>)
      .map(recruitmentFromMap)
      .where((r) =>
          r != null &&
          r.hostId == myId &&
          r.expiresAt.isAfter(now))
      .cast<Recruitment>()
      .toList();
  final recIds = recs.map((r) => r.id).toSet();
  final apps = ((snapshot['applications'] as List?) ?? const [])
      .map((e) => e as Map<String, dynamic>)
      .map(joinApplicationFromMap)
      .where((a) =>
          a != null &&
          (recIds.contains(a.recruitmentId) || a.applicantId == myId))
      .cast<JoinApplication>()
      .toList();
  final rooms = ((snapshot['rooms'] as List?) ?? const [])
      .map((e) => e as Map<String, dynamic>)
      .map(chatRoomFromMap)
      .where((r) => r != null && r.memberIds.contains(myId))
      .cast<ChatRoom>()
      .toList();
  final roomIds = rooms.map((r) => r.id).toSet();
  final messages = ((snapshot['messages'] as List?) ?? const [])
      .map((e) => e as Map<String, dynamic>)
      .map(chatMessageFromMap)
      .where((m) => m != null && roomIds.contains(m.roomId))
      .cast<ChatMessage>()
      .toList();
  final communities = ((snapshot['communities'] as List?) ?? const [])
      .map((e) => e as Map<String, dynamic>)
      .map(communityFromMap)
      .where((c) =>
          c != null && (c.ownerId == myId || c.memberIds.contains(myId)))
      .cast<Community>()
      .toList();
  final communityIds = communities.map((c) => c.id).toSet();
  final events = ((snapshot['events'] as List?) ?? const [])
      .map((e) => e as Map<String, dynamic>)
      .map(communityEventFromMap)
      .where((e) => e != null && communityIds.contains(e.communityId))
      .cast<CommunityEvent>()
      .toList();
  final reports = ((snapshot['catchReports'] as List?) ?? const [])
      .map((e) => e as Map<String, dynamic>)
      .map(catchReportFromMap)
      .where((r) => r != null && r.reporterId == myId)
      .cast<CatchReport>()
      .toList();
  return {
    'recruitments': recs.map(recruitmentToMap).toList(),
    'applications': apps.map(joinApplicationToMap).toList(),
    'rooms': rooms.map(chatRoomToMap).toList(),
    'messages': messages.map(chatMessageToMap).toList(),
    'communities': communities.map(communityToMap).toList(),
    'events': events.map(communityEventToMap).toList(),
    'catchReports': reports.map(catchReportToMap).toList(),
  };
}
