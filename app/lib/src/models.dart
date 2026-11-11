import 'package:flutter/material.dart';

/// 募集ジャンル
class Genre {
  final String id;
  final String label;
  final IconData icon;
  const Genre(this.id, this.label, this.icon);
}

const List<Genre> genres = [
  Genre('shore', '堤防・陸っぱり', Icons.phishing),
  Genre('surf', '投げ・サーフ', Icons.waves),
  Genre('boat', '船・釣り堀', Icons.directions_boat),
];

Genre genreById(String id) => genres.firstWhere((g) => g.id == id);

/// 興味カテゴリ。
/// `interestCategories` は初期セット（デフォルト）。ユーザーは自由に
/// カテゴリを追加でき（AppState.categoryRegistry）、Supabase モードでは
/// 全ユーザーに共有される。
class InterestCategory {
  final String id;
  final String label;
  final IconData icon;
  const InterestCategory(this.id, this.label, this.icon);
}

const List<InterestCategory> interestCategories = [
  InterestCategory('sabiki', 'サビキ・堤防釣り', Icons.phishing),
  InterestCategory('surf', '投げ・サーフ釣り', Icons.waves),
  InterestCategory('lure', 'ルアー・エギング', Icons.set_meal),
  InterestCategory('fly', 'フライ・渓流釣り', Icons.air),
  InterestCategory('pond', '管理釣り場・淡水', Icons.pool),
  InterestCategory('boat', '船釣り', Icons.directions_boat),
  InterestCategory('night', '夜釣り', Icons.dark_mode),
  InterestCategory('cook', '釣った魚を食べる', Icons.restaurant),
  InterestCategory('tackle', '釣り具・自作仕掛け', Icons.handyman),
  InterestCategory('photo', '釣果・風景撮影', Icons.camera_alt),
  InterestCategory('travel', '遠征・釣行旅行', Icons.luggage),
  InterestCategory('cleanup', '釣り場の清掃・環境保護', Icons.volunteer_activism),
];

/// カスタムカテゴリのアイコン候補（名前でDB保存するため定数マップ）。
/// 本アプリは釣りに特化するため、アイコンも釣り・海系のみとする
/// （その他の趣味は別アプリで展開する方針）。
const Map<String, IconData> categoryIconChoices = {
  'hook': Icons.phishing,
  'fish': Icons.set_meal,
  'water': Icons.water,
  'waves': Icons.waves,
  'boat': Icons.directions_boat,
  'sailing': Icons.sailing,
  'kayak': Icons.kayaking,
  'beach': Icons.beach_access,
  'night': Icons.dark_mode,
  'camera': Icons.camera_alt,
  'food': Icons.restaurant,
  'tools': Icons.handyman,
  'travel': Icons.luggage,
  'heart': Icons.favorite,
  'bag': Icons.shopping_bag,
};

/// アイコン名から IconData を引く（未登録の名前はデフォルトを返す）
IconData categoryIconByName(String? name) =>
    categoryIconChoices[name] ?? Icons.phishing;

/// プロトタイプ用のモック現在地（本開発では端末の GPS + geohash に置き換える）
class MockLocation {
  final String id;
  final String name;
  final double lat;
  final double lng;
  const MockLocation(this.id, this.name, this.lat, this.lng);
}

const List<MockLocation> mockLocations = [
  MockLocation('tokyo', '東京駅', 35.6812, 139.7671),
  MockLocation('yurakucho', '有楽町', 35.6748, 139.7629),
  MockLocation('akiba', '秋葉原', 35.7023, 139.7745),
  MockLocation('shibuya', '渋谷', 35.6580, 139.7016),
  MockLocation('shinjuku', '新宿', 35.6896, 139.7006),
  MockLocation('shinagawa', '品川', 35.6285, 139.7394),
];

/// 近くの釣り場（「釣りスポット情報共有MAPくん」の共有データ）。
/// 実データは share-map.net のWeb版が使うデータ取得経路
/// （lib/src/util/fishing_spots.dart）から現在地周辺で取得する。
/// 釣り堀・海釣り公園など有料・管理系施設と釣具店ピンは除外する。
class FishingSpot {
  final String id; // MAPくんの coordinate_id
  final String name;
  final String spotType; // '堤防' | '桟橋' | '護岸' | 'デッキ' | ... ラベル
  final double lat;
  final double lng;
  final double distanceKm; // 現在地からの距離
  final bool isSea; // 海釣りスポット
  final bool isFresh; // 川・湖のスポット
  final bool feeFreeKnown; // 無料と投稿されている（no_fee=1）
  final bool is24Hours; // 24時間釣り可能と投稿されている
  final String? businessHours; // 営業時間のテキスト（24時間でない場合）
  final double reputationAvg; // 投稿者評価の平均（投票が無い場合は 0）
  final String? fishes; // 釣れる魚などの投稿テキスト
  final String? memo; // 場所についての投稿メモ

  const FishingSpot({
    required this.id,
    required this.name,
    required this.spotType,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    this.isSea = false,
    this.isFresh = false,
    this.feeFreeKnown = false,
    this.is24Hours = false,
    this.businessHours,
    this.reputationAvg = 0,
    this.fishes,
    this.memo,
  });

  /// 桟橋・デッキ系のアイコン表示用
  bool get isPierLike => spotType == '桟橋' || spotType == 'デッキ';
}

class AppUser {
  final String id;
  final String nickname;
  final String decade; // 例: '20代'。ビジネスユーザーは '経営者'
  final String gender; // 'male' | 'female' | 'undisclosed'
  final String iconCategoryId; // 趣味アイコン（顔画像は禁止）
  final String? iconImagePath; // 端末内に保存した投稿アイコン画像（あれば優先表示）
  final List<String> interestIds;
  final String bio;
  final double lat;
  final double lng;
  final String? websiteUrl; // 公開URL（例: 店のホームページ）
  final String? snsNote; // SNS（例: 'X: @tsuritomo_official / IG: tsuritomo'）
  final String? phone; // ビジネスユーザー（店舗）の電話番号。タップで発信

  const AppUser({
    required this.id,
    required this.nickname,
    required this.decade,
    required this.gender,
    required this.iconCategoryId,
    required this.interestIds,
    required this.bio,
    required this.lat,
    required this.lng,
    this.iconImagePath,
    this.websiteUrl,
    this.snsNote,
    this.phone,
  });

  String get genderLabel => const {'male': '男性', 'female': '女性'}.containsKey(gender)
      ? const {'male': '男性', 'female': '女性'}[gender]!
      : '非公開';

  bool get isBusiness => false;

  /// 位置だけ変えたコピーを返す
  AppUser withPosition(double newLat, double newLng) {
    return AppUser(
      id: id,
      nickname: nickname,
      decade: decade,
      gender: gender,
      iconCategoryId: iconCategoryId,
      interestIds: interestIds,
      bio: bio,
      lat: newLat,
      lng: newLng,
      iconImagePath: iconImagePath,
      websiteUrl: websiteUrl,
      snsNote: snsNote,
      phone: phone,
    );
  }
}

/// ビジネスユーザー（店舗。一般ユーザー登録と分離された登録フローで作られる）
class BusinessUser extends AppUser {
  final String storeType; // 例: '釣具店'

  const BusinessUser({
    required super.id,
    required super.nickname,
    required super.decade,
    required super.gender,
    required super.iconCategoryId,
    required super.interestIds,
    required super.bio,
    required super.lat,
    required super.lng,
    required this.storeType,
    super.iconImagePath,
    super.websiteUrl,
    super.snsNote,
    super.phone,
  });

  @override
  bool get isBusiness => true;

  @override
  AppUser withPosition(double newLat, double newLng) {
    return BusinessUser(
      id: id,
      nickname: nickname,
      decade: decade,
      gender: gender,
      iconCategoryId: iconCategoryId,
      interestIds: interestIds,
      bio: bio,
      lat: newLat,
      lng: newLng,
      storeType: storeType,
      iconImagePath: iconImagePath,
      websiteUrl: websiteUrl,
      snsNote: snsNote,
      phone: phone,
    );
  }
}

enum RecStatus { active, fulfilled, expired, cancelled }

class Recruitment {
  final String id;
  final String hostId;
  final String genreId;
  final String title;
  final String body;
  final String meetup;
  final int capacity;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> memberIds; // host を含む

  const Recruitment({
    required this.id,
    required this.hostId,
    required this.genreId,
    required this.title,
    required this.body,
    required this.meetup,
    required this.capacity,
    required this.createdAt,
    required this.expiresAt,
    required this.memberIds,
  });

  bool get isFull => memberIds.length >= capacity;

  bool isActiveAt(DateTime now) =>
      now.isBefore(expiresAt) && !isFull && memberIds.isNotEmpty;

  int get remainingSlots => capacity - memberIds.length;

  RecStatus statusAt(DateTime now) {
    if (isFull) return RecStatus.fulfilled;
    if (!now.isBefore(expiresAt)) return RecStatus.expired;
    return RecStatus.active;
  }
}

enum JoinStatus { pending, accepted, declined }

class JoinApplication {
  final String id;
  final String recruitmentId;
  final String applicantId;
  final String message;
  JoinStatus status;
  final DateTime createdAt;

  JoinApplication({
    required this.id,
    required this.recruitmentId,
    required this.applicantId,
    required this.message,
    required this.status,
    required this.createdAt,
  });
}

class ChatRoom {
  final String id;
  final String recruitmentId; // DM・コミュニティの場合は空文字
  final List<String> memberIds;
  final DateTime createdAt;
  final String type; // 'group' | 'dm' | 'community'
  final String? communityId; // コミュニティチャットの場合

  ChatRoom({
    required this.id,
    required this.recruitmentId,
    required this.memberIds,
    required this.createdAt,
    this.type = 'group',
    this.communityId,
  });

  bool get isDm => type == 'dm';

  bool get isCommunity => type == 'community';
}

/// コミュニティ（クラブ・イベント企画・店舗のファンコミュニティ）。
/// 誰でも作成でき、参加するとコミュニティチャットが開ける（FR-6-1〜6-3）。
class Community {
  final String id;
  final String ownerId;
  final String name;
  final String description;
  final String? linkedStore; // 店舗ファンコミュニティの場合の店舗名
  final DateTime createdAt;
  final Set<String> memberIds;

  Community({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.description,
    required this.linkedStore,
    required this.createdAt,
    required this.memberIds,
  });

  Community copyWith({
    Set<String>? memberIds,
    String? name,
    String? description,
  }) {
    return Community(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      description: description ?? this.description,
      linkedStore: linkedStore,
      createdAt: createdAt,
      memberIds: memberIds ?? this.memberIds,
    );
  }
}

/// コミュニティ内で企画されるイベント・クラブ
class CommunityEvent {
  final String id;
  final String communityId;
  final String hostId;
  final String title;
  final String body;
  final String eventTime; // ベータでは自由記述（例: '3/14 19:00〜'）
  final String locationName;
  final int capacity;
  final DateTime createdAt;
  final Set<String> participantIds;

  CommunityEvent({
    required this.id,
    required this.communityId,
    required this.hostId,
    required this.title,
    required this.body,
    required this.eventTime,
    required this.locationName,
    required this.capacity,
    required this.createdAt,
    required this.participantIds,
  });

  bool get isFull => participantIds.length >= capacity;

  CommunityEvent copyWith({Set<String>? participantIds}) {
    return CommunityEvent(
      id: id,
      communityId: communityId,
      hostId: hostId,
      title: title,
      body: body,
      eventTime: eventTime,
      locationName: locationName,
      capacity: capacity,
      createdAt: createdAt,
      participantIds: participantIds ?? this.participantIds,
    );
  }
}

class ChatMessage {
  final String id;
  final String roomId;
  final String senderId; // system の場合 'system'
  final String body;
  final DateTime sentAt;
  final bool isSystem;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.isSystem = false,
  });
}
