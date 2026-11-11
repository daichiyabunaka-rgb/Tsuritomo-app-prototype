import 'dart:math' as math;

import '../models.dart';

/// モックユーザーは「anchor（中心点）からの相対距離」で配置する。
/// anchor には実 GPS で取得した現在地が入り、どこにいても近くの釣りとも候補が並ぶ。
class _MockSpec {
  final String id;
  final String nickname;
  final String decade;
  final String gender;
  final String iconCategoryId;
  final List<String> interestIds;
  final String bio;
  final double northKm; // anchor からの北方向距離
  final double eastKm; // anchor からの東方向距離

  const _MockSpec(this.id, this.nickname, this.decade, this.gender,
      this.iconCategoryId, this.interestIds, this.bio, this.northKm,
      this.eastKm);
}

const List<_MockSpec> _specs = [
  _MockSpec(
    'u-sabiki-tetsu',
    'サビキのテツ',
    '30代',
    'male',
    'sabiki',
    ['sabiki', 'night', 'cook'],
    '週末は近所の堤防でサビキ。アジとイワシの回遊を追う毎日。仕掛けのコツも教えます。',
    0.6,
    0.2,
  ),
  _MockSpec(
    'u-eging-mari',
    'エギャーのマリ',
    '20代',
    'female',
    'lure',
    ['lure', 'photo', 'travel'],
    '春はアオリイカのエギング。釣果写真を撮るのが最近の楽しみ。遠征も大歓迎。',
    -0.3,
    -0.1,
  ),
  _MockSpec(
    'u-jig-gen',
    'ジギングのゲン',
    '40代',
    'male',
    'boat',
    ['boat', 'tackle'],
    '週1で乗り合い船に乗って青物を追っています。同乗者募集中。貸し竿の相談もどうぞ。',
    0.15,
    -0.4,
  ),
  _MockSpec(
    'u-fukase-yuki',
    'フカセのユキ',
    '30代',
    'undisclosed',
    'sabiki',
    ['sabiki', 'cleanup', 'cook'],
    'グレのフカセ釣りが好き。釣り場にはいつもきれいに帰ります（ゴミは必ず持ち帰り）。',
    -0.7,
    0.5,
  ),
  _MockSpec(
    'u-nage-taro',
    '投げ釣りのタロ',
    '30代',
    'undisclosed',
    'surf',
    ['surf', 'tackle', 'night'],
    'カレイとキスの投げ釣り。遠投の練習中。夜の投げ釣りもやります。',
    -0.75,
    0.9,
  ),
  _MockSpec(
    'u-wakasagi-nana',
    'ワカサギのなな',
    '20代',
    'undisclosed',
    'pond',
    ['pond', 'cook', 'photo'],
    '冬はワカサギ、夏は管釣りのニジマス。氷上の甘党（お団子は必須）です。',
    1.2,
    -0.9,
  ),
  _MockSpec(
    'u-bass-kai',
    'バッサーの櫂',
    '40代',
    'male',
    'lure',
    ['lure', 'cleanup'],
    '野池と河川をルアーで回っています。キャッチ＆リリース派。ランガン仲間を探してます。',
    -1.1,
    1.0,
  ),
  _MockSpec(
    'u-photo-yui',
    '釣りカメラの柚衣',
    '20代',
    'female',
    'photo',
    ['photo', 'travel', 'cleanup'],
    '釣り人の写真を撮るのが好き。海と空の写真がたくさんあります。撮影OKです。',
    0.45,
    -1.3,
  ),
];

class _BusinessSpec {
  final String id;
  final String nickname;
  final String iconCategoryId;
  final String storeType;
  final String bio;
  final double northKm;
  final double eastKm;

  const _BusinessSpec(this.id, this.nickname, this.iconCategoryId,
      this.storeType, this.bio, this.northKm, this.eastKm);
}

const List<_BusinessSpec> _businessSpecs = [
  _BusinessSpec(
    'b-tackle-umeki',
    '釣具のうめき',
    'tackle',
    '釣具店',
    'リールのメンテナンスと仕掛けの相談ならお任せ。初心者セットのご用意もあります。',
    0.8,
    0.9,
  ),
  _BusinessSpec(
    'b-toami-wadatsumi',
    '渡船 わだつみ',
    'boat',
    '乗り合い船・渡船',
    '周辺の地磯へ毎日出港。朝4時受付。ライフジャケットの無料貸し出しあり。',
    -0.5,
    1.1,
  ),
  _BusinessSpec(
    'b-pond-mizuho',
    '釣り堀 みずほ',
    'pond',
    '釣り堀・管理釣り場',
    'ニジマスとイワナの釣り堀。エサ・レンタル竿あり。家族連れも大歓迎です。',
    1.5,
    -0.6,
  ),
  _BusinessSpec(
    'b-cafe-minato',
    '海辺のカフェ みなと',
    'cook',
    'フィッシングカフェ・飲食',
    '釣りのあとに立ち寄れる海辺のカフェ。釣った魚の持ち込み調理も承ります。',
    -1.4,
    -0.8,
  ),
];

const double _kmPerDegLat = 111.32;

AppUser _specToUser(_MockSpec s, double anchorLat, double anchorLng) {
  final cos =
      math.cos(anchorLat * math.pi / 180.0).abs().clamp(0.01, 1.0);
  return AppUser(
    id: s.id,
    nickname: s.nickname,
    decade: s.decade,
    gender: s.gender,
    iconCategoryId: s.iconCategoryId,
    interestIds: s.interestIds,
    bio: s.bio,
    lat: anchorLat + s.northKm / _kmPerDegLat,
    lng: anchorLng + s.eastKm / (_kmPerDegLat * cos),
  );
}

BusinessUser _specToBusiness(
    _BusinessSpec s, double anchorLat, double anchorLng) {
  final cos =
      math.cos(anchorLat * math.pi / 180.0).abs().clamp(0.01, 1.0);
  return BusinessUser(
    id: s.id,
    nickname: s.nickname,
    decade: '経営者',
    gender: 'undisclosed',
    iconCategoryId: s.iconCategoryId,
    interestIds: const [],
    bio: s.bio,
    lat: anchorLat + s.northKm / _kmPerDegLat,
    lng: anchorLng + s.eastKm / (_kmPerDegLat * cos),
    storeType: s.storeType,
  );
}

/// 現在地を中心にモックユーザー（一般 + ビジネス）を配置する。
List<AppUser> buildMockUsers(double anchorLat, double anchorLng) {
  return [
    for (final s in _specs) _specToUser(s, anchorLat, anchorLng),
    for (final s in _businessSpecs) _specToBusiness(s, anchorLat, anchorLng),
  ];
}

/// シード募集（起動時刻からの残り時間で作るので、いつ開いても「今から」感が出る）。
/// host は generalUsers（モック一般ユーザー）から id で引く。
List<Recruitment> seedRecruitments(DateTime now, List<AppUser> generalUsers) {
  Recruitment make({
    required String hostId,
    required String genreId,
    required String title,
    required String body,
    required String meetup,
    required int capacity,
    required int minutesLeft,
  }) {
    return Recruitment(
      id: 'r-$hostId',
      hostId: hostId,
      genreId: genreId,
      title: title,
      body: body,
      meetup: meetup,
      capacity: capacity,
      createdAt: now.subtract(const Duration(minutes: 15)),
      expiresAt: now.add(Duration(minutes: minutesLeft)),
      memberIds: [hostId],
    );
  }

  return [
    make(
      hostId: 'u-sabiki-tetsu',
      genreId: 'shore',
      title: '今から19時、堤防でサビキしませんか',
      body: 'アジの回遊があります。余った仕掛けもあるので手ぶらでどうぞ。初心者歓迎。',
      meetup: '青海堤防 入口',
      capacity: 3,
      minutesLeft: 105,
    ),
    make(
      hostId: 'u-jig-gen',
      genreId: 'boat',
      title: '土曜の乗り合い船、あと1名どうですか',
      body: 'ジギングで青物を狙います。貸し竿・仕掛けの用意もあります。女性の方も歓迎。',
      meetup: '第一港 渡船受付',
      capacity: 3,
      minutesLeft: 70,
    ),
    make(
      hostId: 'u-eging-mari',
      genreId: 'shore',
      title: '今夜、堤防からエギングしませんか',
      body: 'アオリイカのシーズンです。エギのカラー選びの情報交換もしたい。のんびり派。',
      meetup: '青海堤防 第二折り',
      capacity: 4,
      minutesLeft: 160,
    ),
    make(
      hostId: 'u-nage-taro',
      genreId: 'surf',
      title: '夕マズメ、サーフで投げ釣りを一緒に',
      body: 'キスとカレイの投げ釣り。遠投のコツを教え合えると嬉しいです。',
      meetup: '中央海水浴場 北駐車場',
      capacity: 2,
      minutesLeft: 95,
    ),
    make(
      hostId: 'u-wakasagi-nana',
      genreId: 'boat',
      title: '日曜の午後、釣り堀でのんびりニジマス',
      body: '管理釣り場でまったり釣りたい。初心者や家族連れも大歓迎です。',
      meetup: '釣り堀 みずほ 玄関',
      capacity: 4,
      minutesLeft: 130,
    ),
    make(
      hostId: 'u-bass-kai',
      genreId: 'shore',
      title: '野池でバス釣り、情報交換もしませんか',
      body: 'ルアーの釣り場開拓をしたいです。キャッチ＆リリースで楽しみましょう。',
      meetup: '上の池 駐車帯',
      capacity: 3,
      minutesLeft: 45,
    ),
  ];
}

/// モックの返信候補（デモの自動応答に使う。本開発では Supabase Realtime に置換）
const List<String> mockReplies = [
  'よろしくお願いします！',
  '今から準備して向かいます。',
  '先に着いてポイントを取っておきますね。',
  'この釣り場ずっと気になっていました。',
];

/// モックの応募メッセージ
const List<String> mockApplyMessages = [
  '参加したいです！釣り仲間を探していました。',
  '何度か行ったことのある釣り場です。お供させてください。',
  '初心者ですが大丈夫でしょうか。',
];
