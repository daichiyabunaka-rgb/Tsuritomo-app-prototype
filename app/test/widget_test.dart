import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tsuritomo/main.dart';
import 'package:tsuritomo/src/models.dart';
import 'package:tsuritomo/src/screens/chat_screen.dart';
import 'package:tsuritomo/src/services/ai_concierge.dart';
import 'package:tsuritomo/src/services/app_state.dart';
import 'package:tsuritomo/src/services/auth_service.dart';
import 'package:tsuritomo/src/util/fishing_spots.dart';
import 'package:tsuritomo/src/util/format.dart';
import 'package:tsuritomo/src/util/mock_persist.dart' as persist;
import 'package:tsuritomo/src/util/share_text.dart';

AppUser _testUser(AppState state, {String id = 'me', String nickname = 'テスト太郎'}) {
  return AppUser(
    id: id,
    nickname: nickname,
    decade: '30代',
    gender: 'male',
    iconCategoryId: 'sabiki',
    interestIds: const ['sabiki'],
    bio: 'テスト',
    lat: state.anchorLat,
    lng: state.anchorLng,
  );
}

void main() {
  group('format utils', () {
    test('距離は粗いバンド表示になる（FR-2-2）', () {
      expect(distanceLabel(0.3), '〜1km');
      expect(distanceLabel(2.4), '1〜3km');
      expect(distanceLabel(4.9), '3〜5km');
      expect(distanceLabel(7.2), '5〜10km');
      expect(distanceLabel(23.0), '10km〜');
    });

    test('残り時間ラベル', () {
      final now = DateTime(2026, 2, 1, 12, 0);
      expect(remainingLabel(now.add(const Duration(minutes: 42)), now),
          '残り42分');
      expect(remainingLabel(now.add(const Duration(hours: 2)), now),
          '残り2時間');
      expect(
          remainingLabel(now.add(const Duration(hours: 1, minutes: 20)), now),
          '残り1時間20分');
      expect(remainingLabel(now.subtract(const Duration(minutes: 1)), now),
          '終了');
    });

    test('経過時間ラベル', () {
      final now = DateTime(2026, 2, 1, 12, 0);
      expect(elapsedLabel(now.subtract(const Duration(seconds: 30)), now),
          'たった今');
      expect(
          elapsedLabel(now.subtract(const Duration(minutes: 42)), now),
          '42分前');
      expect(
          elapsedLabel(now.subtract(const Duration(hours: 5)), now),
          '5時間前');
      expect(elapsedLabel(now.subtract(const Duration(days: 2)), now),
          '2日前');
    });
  });

  group('share_text（SNS共有文）', () {
    test('招待文にニックネームとURLが入る', () {
      final t = inviteText('サビキのテツ');
      expect(t, contains('サビキのテツ'));
      expect(t, contains(kAppUrl));
      expect(t, contains('完全無料'));
    });

    test('募集の共有文にタイトルと集合場所が入る', () {
      final t = recruitmentShareText('今から堤防でサビキ', '青海堤防 入口');
      expect(t, contains('今から堤防でサビキ'));
      expect(t, contains('青海堤防 入口'));
      expect(t, contains(kAppUrl));
    });

    test('同業者向けの紹介文に店舗名と業態と無料表記が入る', () {
      final t = businessInviteText('釣具のうめき', '釣具店');
      expect(t, contains('釣具のうめき'));
      expect(t, contains('釣具店'));
      expect(t, contains('無料'));
      expect(t, contains(kAppUrl));
    });
  });

  group('近くの釣り場（釣りとも！特別機能）', () {
    // 東京駅（35.6812, 139.7671）を現在地としたOverpassレスポンスの例
    const overpassJson = '''
{
  "version": 0.6, "generator": "Overpass API",
  "elements": [
    {"type": "node", "id": 101, "lat": 35.70, "lon": 139.78,
     "tags": {"leisure": "fishing", "name": "A海釣り公園", "fee": "no"}},
    {"type": "node", "id": 102, "lat": 35.68, "lon": 139.76,
     "tags": {"leisure": "fishing", "name": "B有料釣り施設", "fee": "yes"}},
    {"type": "way", "id": 103,
     "center": {"lat": 35.67, "lon": 139.76},
     "tags": {"natural": "water", "fishing": "permit", "name": "C湖"}},
    {"type": "way", "id": 104,
     "center": {"lat": 35.60, "lon": 139.76},
     "tags": {"leisure": "fishing", "name": "D遠い釣り場"}},
    {"type": "node", "id": 105, "lat": 35.68, "lon": 139.772,
     "tags": {"fishing": "yes"}},
    {"type": "node", "id": 106, "lat": 35.68, "lon": 139.77,
     "tags": {"man_made": "pier", "fishing": "no", "name": "F釣りNG桟橋"}},
    {"type": "node", "id": 107, "lat": 35.67, "lon": 139.765,
     "tags": {"man_made": "pier", "name": "G桟橋"}}
  ]
}''';

    test('実在データのパース: 釣り禁止（fishing=no）の場所は除外される', () {
      final spots = parseOverpassResponse(overpassJson, 35.6812, 139.7671);
      final names = spots.map((s) => s.name).toList();
      expect(names, isNot(contains('F釣りNG桟橋'))); // fishing=no は除外
      expect(names, contains('A海釣り公園'));
      expect(names, contains('B有料釣り施設'));
      expect(names, contains('C湖'));
      expect(names, contains('名称未登録の釣り場')); // fishing=yes の名称未登録地点も載せる
    });

    test('結果は現在地からの距離の昇順に並ぶ', () {
      final spots = parseOverpassResponse(overpassJson, 35.6812, 139.7671);
      expect(spots.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < spots.length; i++) {
        expect(spots[i - 1].distanceKm,
            lessThanOrEqualTo(spots[i].distanceKm));
      }
    });

    test('タグから属性が読み取れる（釣り可・桟橋）', () {
      final spots = parseOverpassResponse(overpassJson, 35.6812, 139.7671);
      final permit = spots.firstWhere((s) => s.name == 'C湖');
      expect(permit.fishingRule, 'permit');
      expect(permit.type, 'water');
      final pier = spots.firstWhere((s) => s.name == 'G桟橋');
      expect(pier.type, 'pier');
      expect(pier.isPier, isTrue);
      final known = spots.firstWhere((s) => s.name == 'A海釣り公園');
      expect(known.fishingRule, 'unknown');
      expect(known.feeFreeKnown, isTrue);
    });

    test('Googleマップ用URLは釣り場の座標で組み立てられる', () {
      final spots = parseOverpassResponse(overpassJson, 35.6812, 139.7671);
      final spot = spots.first;
      final url = googleMapsUrlForSpot(spot);
      expect(url, startsWith('https://www.google.com/maps/search/'));
      expect(url, contains('${spot.lat},${spot.lng}'));
    });

    test('Overpassクエリは釣りスポットのみを含む', () {
      final q = buildOverpassQuery(35.6812, 139.7671, radiusKm: 5);
      // relation を含む bbox クエリは重すぎて各サーバーが502/504を返すため除外
      expect(q, isNot(contains('relation')));
      expect(q, contains('"leisure"="fishing"'));
      expect(q, contains('"fishing"~"^(yes|permit)\$"'));
      expect(q, contains('"man_made"="pier"'));
    });

    test('釣り場データのキャッシュ変換（Map⇔FishingSpot）は往復できる', () {
      final spots = parseOverpassResponse(overpassJson, 35.6812, 139.7671);
      for (final s in spots) {
        final restored = fishingSpotFromMap(fishingSpotToMap(s));
        expect(restored.osmId, s.osmId);
        expect(restored.name, s.name);
        expect(restored.type, s.type);
        expect(restored.lat, s.lat);
        expect(restored.lng, s.lng);
        expect(restored.fishingRule, s.fishingRule);
        expect(restored.openingHours, s.openingHours);
      }
    });
  });

  group('端末内スナップショット（モック永続化）', () {
    test('募集・釣果・コミュニティは保存用Mapとの往復ができる', () {
      final now = DateTime(2026, 3, 1, 12, 0);
      final rec = Recruitment(
        id: 'r-1',
        hostId: 'me',
        genreId: 'shore',
        title: 'テストの募集',
        body: '本文',
        meetup: 'テスト堤防',
        capacity: 3,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        memberIds: const ['me'],
      );
      final restored = persist.recruitmentFromMap(
          persist.recruitmentToMap(rec));
      expect(restored!.id, rec.id);
      expect(restored.title, rec.title);
      expect(restored.memberIds, rec.memberIds);

      final report = CatchReport(
        id: 'cr-1',
        reporterId: 'me',
        kind: 'sea',
        fishDescription: 'テスト魚（30cm・サビキ）',
        areaName: 'テスト堤防',
        detail: '状況メモ',
        lat: 35.0,
        lng: 139.0,
        createdAt: now,
        photoPath: '/data/user/0/catch_photos/catch_photo_1.jpg',
      );
      final restoredReport = persist.catchReportFromMap(
          persist.catchReportToMap(report));
      expect(restoredReport!.kind, 'sea');
      expect(restoredReport.photoPath, report.photoPath);
      expect(restoredReport.createdAt, report.createdAt);

      final com = Community(
        id: 'c-1',
        ownerId: 'me',
        name: 'テスト部',
        description: '説明',
        linkedStore: null,
        createdAt: now,
        memberIds: const {'me'},
      );
      final restoredCom = persist.communityFromMap(
          persist.communityToMap(com));
      expect(restoredCom!.name, com.name);
      expect(restoredCom.memberIds, com.memberIds);
    });

    test('prune: 他アカウントと期限切れの募集は復元されない', () {
      final now = DateTime.now();
      final rec = Recruitment(
        id: 'r-mine',
        hostId: 'me',
        genreId: 'shore',
        title: '自分の募集',
        body: '',
        meetup: '堤防',
        capacity: 2,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 2)),
        memberIds: const ['me'],
      );
      final expired = Recruitment(
        id: 'r-expired',
        hostId: 'me',
        genreId: 'shore',
        title: '期限切れ',
        body: '',
        meetup: '堤防',
        capacity: 2,
        createdAt: now.subtract(const Duration(hours: 5)),
        expiresAt: now.subtract(const Duration(hours: 1)),
        memberIds: const ['me'],
      );
      final othersReport = CatchReport(
        id: 'cr-other',
        reporterId: 'someone-else',
        kind: 'sea',
        fishDescription: '他人の投稿',
        areaName: 'どこか',
        detail: '',
        lat: 35.0,
        lng: 139.0,
        createdAt: now,
      );
      final myReport = CatchReport(
        id: 'cr-mine',
        reporterId: 'me',
        kind: 'sea',
        fishDescription: '自分の投稿',
        areaName: 'どこか',
        detail: '',
        lat: 35.0,
        lng: 139.0,
        createdAt: now,
      );
      final snapshot = {
        'recruitments': [rec, expired].map(persist.recruitmentToMap).toList(),
        'catchReports': [othersReport, myReport]
            .map(persist.catchReportToMap)
            .toList(),
      };
      final pruned = persist.pruneSnapshotToOwner(snapshot, 'me');
      final recIds =
          (pruned['recruitments'] as List).map((e) => e['id'] as String).toList();
      expect(recIds, ['r-mine']); // 期限切れは捨てる
      final reportIds = (pruned['catchReports'] as List)
          .map((e) => e['id'] as String)
          .toList();
      expect(reportIds, ['cr-mine']); // 他人の投稿は捨てる
    });
  });

  group('AuthService（モック認証）', () {
    test('会員登録するとログイン状態になり、ログアウト・再ログインができる',
        () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      await auth.init();

      // 会員登録 → 同時にログインされる
      await auth.register(
        email: 'Test@Example.com',
        password: 'secret123',
        nickname: '太郎',
        decade: '30代',
        gender: 'male',
        iconCategoryId: 'sabiki',
        interestIds: const ['sabiki'],
        bio: 'テスト',
      );
      expect(auth.sessionEmail, 'test@example.com'); // 小文字化して保存
      expect(auth.sessionNickname(), '太郎');

      // ログアウト → セッション消えるがアカウントは残る
      await auth.logout();
      expect(auth.hasSession, isFalse);
      await auth.login('test@example.com', 'secret123');
      expect(auth.hasSession, isTrue);

      // 誤パスワードは拒否される
      await expectLater(
        auth.login('test@example.com', 'wrong-pw'),
        throwsA(isA<AuthException>()),
      );

      // 同 email の再登録は拒否される
      await expectLater(
        auth.register(
          email: 'test@example.com',
          password: 'x',
          nickname: '二郎',
          decade: '20代',
          gender: 'male',
          iconCategoryId: 'sabiki',
          interestIds: const ['sabiki'],
          bio: '',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('セッションからユーザーを復元できる', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      await auth.init();
      await auth.register(
        email: 'a@b.com',
        password: 'secret123',
        nickname: '花子',
        decade: '20代',
        gender: 'female',
        iconCategoryId: 'photo',
        interestIds: const ['photo'],
        bio: 'テスト',
      );
      final user = await auth.buildSessionUser(lat: 35.0, lng: 139.0);
      expect(user, isNotNull);
      expect(user!.nickname, '花子');
      expect(user.lat, 35.0);
    });
  });

  group('AiConcierge（AI接客デモ）', () {
    final me = AppUser(
      id: 'me',
      nickname: '太郎',
      decade: '30代',
      gender: 'male',
      iconCategoryId: 'sabiki',
      interestIds: const ['sabiki'],
      bio: 'テスト',
      lat: 35.0,
      lng: 139.0,
    );
    final store = BusinessUser(
      id: 'b-tackle-umeki',
      nickname: '釣具のうめき',
      decade: '経営者',
      gender: 'undisclosed',
      iconCategoryId: 'tackle',
      interestIds: const [],
      bio: 'デモ店舗',
      lat: 35.0,
      lng: 139.0,
      storeType: '釣具店',
    );

    test('挨拶は店舗の口調とユーザーの興味を踏まえて案内する', () {
      final g = aiConcierge.greeting(me, store);
      expect(g, contains('いらっしゃい')); // 釣具店の口調
      expect(g, contains('太郎'));
      expect(g, contains('サビキ'));
      expect(g, contains('ロッド＋リール'));
    });

    test('口調は店舗タイプごとに変わる', () {
      final pond = BusinessUser(
        id: 'b-pond-mizuho',
        nickname: '釣り堀 みずほ',
        decade: '経営者',
        gender: 'undisclosed',
        iconCategoryId: 'pond',
        interestIds: const [],
        bio: 'デモ店舗',
        lat: 35.0,
        lng: 139.0,
        storeType: '釣り堀・管理釣り場',
      );
      expect(aiConcierge.greeting(me, pond), contains('ようこそ'));
    });

    test('キーワードに応じた応答をする（おすすめ/初心者/予約/unknown）', () {
      final ai = aiConcierge;
      expect(ai.reply('おすすめは？', me, store), contains('ロッド＋リール'));
      expect(ai.reply('初心者でも大丈夫？', me, store), contains('歓迎'));
      expect(ai.reply('予約したいです', me, store), contains('平日'));
      // どのキーワードにも当てはまらない場合は案内を返す
      expect(ai.reply('こんにちは', me, store), contains('おすすめ'));
    });
  });

  group('AppState（ドメイン状態）', () {
    test('ログインすると近くの募集・一般・ビジネスユーザーが見える', () {
      final state = AppState();
      expect(state.me, isNull);
      expect(state.activeRecruitments(), isEmpty);

      state.attachUser(_testUser(state), reseed: true);
      expect(state.me, isNotNull);
      expect(state.activeRecruitments(), isNotEmpty);
      expect(state.generalUsers, isNotEmpty);
      expect(state.businessUsers, isNotEmpty);
      // ビジネスユーザーは募集一覧の host には出てこない
      expect(
        state.activeRecruitments().every(
            (r) => state.userById(r.hostId).isBusiness == false),
        isTrue,
      );
    });

    test('GPS適用でモックが現在地周囲に再配置される', () {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      state.applyGps(43.0, 141.0);
      expect(state.gpsAvailable, isTrue);
      // 一般ユーザーは現在地（anchor）から粗いバンド内に並ぶ
      for (final u in state.generalUsers) {
        final km = haversineKm(state.anchorLat, state.anchorLng, u.lat, u.lng);
        expect(km, lessThan(6.0));
      }
    });

    test('募集を作ると期限付きで一覧に載る', () async {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final rec = await state.createRecruitment(
        genreId: 'shore',
        title: 'テストの募集',
        body: '本文',
        meetup: 'テスト堤防',
        capacity: 2,
        expiryHours: 2,
      );
      expect(rec.isActiveAt(DateTime.now()), isTrue);
      expect(state.activeRecruitments().map((r) => r.id), contains(rec.id));
      expect(state.recruitmentDistanceLabel(rec), 'あなたの募集');
    });

    test('他人の募集への応募は数秒後に承認され部屋ができる（デモ挙動）', () async {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final target = state
          .activeRecruitments()
          .firstWhere((r) => r.hostId != state.me!.id);
      state.applyTo(target.id, message: 'よろしくお願いします');
      expect(state.myPendingApplication(target.id), isNotNull);
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(state.myRooms, isNotEmpty);
      expect(state.messagesOf(state.myRooms.first.id), isNotEmpty);
    });

    test('存在しない応募の承認 / 却下は無視される', () {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      state.acceptApplication('nonexistent');
      state.declineApplication('nonexistent');
      expect(state.myRooms, isEmpty);
    });

    test('投稿アイコン画像は GPS・プロフィール更新でも保持される', () {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      state.updateProfile(
        nickname: 'テスト太郎',
        decade: '30代',
        gender: 'male',
        iconCategoryId: 'sabiki',
        interestIds: const ['sabiki'],
        bio: 'テスト',
        iconImagePath: '/data/user/0/app/icons/icon_1.jpg',
      );
      expect(state.me!.iconImagePath, isNotEmpty);
      state.applyGps(43.0, 141.0);
      expect(state.me!.iconImagePath, isNotEmpty);
    });

    test('DM: 同一相手との部屋は再利用され、違う相手は別の部屋になる', () async {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final other = state.generalUsers.first;
      final dm1 = await state.getOrCreateDm(other.id);
      final dm2 = await state.getOrCreateDm(other.id);
      expect(dm1.id, dm2.id);
      final other2 = state.generalUsers[1];
      final dm3 = await state.getOrCreateDm(other2.id);
      expect(dm3.id, isNot(dm1.id));
      expect(state.myRooms.where((r) => r.isDm), hasLength(2));
      expect(state.lastMessageOf(dm1.id), isNotEmpty); // system メッセージ
    });

    test('リアルタイム着信は重複せず、他人のメッセージは未読が増える',
        () async {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final other = state.generalUsers.first;
      final room = await state.getOrCreateDm(other.id);
      final before = state.unreadByRoom[room.id] ?? 0;
      final msg = ChatMessage(
        id: 'incoming-1',
        roomId: room.id,
        senderId: other.id,
        body: 'こんにちは',
        sentAt: DateTime.now(),
      );
      state.handleIncomingMessage(room.id, msg);
      state.handleIncomingMessage(room.id, msg); // 重複着信
      expect(
          state.messagesOf(room.id)
              .where((m) => m.id == 'incoming-1'),
          hasLength(1));
      expect(state.unreadByRoom[room.id], before + 1);
    });

    test('コミュニティ: モックでは参加中シードがあり、参加すると部屋ができる',
        () async {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      expect(state.communities, isNotEmpty);
      final target =
          state.communities.firstWhere((c) => !c.memberIds.contains('me'));
      final before = state.myRooms.length;
      await state.joinCommunity(target.id);
      expect(state.myCommunities.map((c) => c.id), contains(target.id));
      expect(state.myRooms.length, before + 1);
      final room = state.myRooms
          .firstWhere((r) => r.communityId == target.id);
      expect(room.isCommunity, isTrue);
      // コミュニティチャットに投稿できる
      await state.sendCommunityMessage(target.id, 'こんにちは');
      expect(state.lastMessageOf(room.id), contains('こんにちは'));
    });

    test('コミュニティ作成とイベント企画（誰でも作成できる）', () async {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final created = await state.createCommunity(
        name: 'テスト同好会',
        description: 'テスト用',
        linkedStore: null,
      );
      expect(created.memberIds, contains('me'));
      // 作成者は自動で参加し、チャット部屋ができている
      expect(state.myRooms.where((r) => r.communityId == created.id),
          isNotEmpty);
      final event = await state.createEvent(
        communityId: created.id,
        title: 'テスト釣行会',
        body: '',
        eventTime: '来週土曜',
        locationName: '堤防集合',
        capacity: 3,
      );
      final stored = state.eventsOf(created.id);
      expect(stored, hasLength(1));
      expect(stored.first.id, event.id);
      expect(stored.first.participantIds, contains('me')); // 主催は自動参加
    });

    test('イベントへの参加・取消ができる', () async {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      // シード済みコミュニティ（自分未参加の c-shore）のイベントへ参加する
      final community =
          state.communities.firstWhere((c) => c.id == 'c-shore');
      final target = state.eventsOf(community.id).first;
      await state.joinEvent(target.id);
      expect(state.eventsOf(community.id).first.participantIds,
          contains('me'));
      await state.leaveEvent(target.id);
      expect(state.eventsOf(community.id).first.participantIds,
          isNot(contains('me')));
    });

    test('興味カテゴリをユーザーが自由に追加できる（重複名は拒否）', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      // attachUser 内で loadCategories が走る
      final before = state.categories.length;
      final created =
          await state.addCategory(label: 'ワカサギ氷上釣り', iconName: 'fish');
      expect(created, isNotNull);
      expect(state.categories.length, before + 1);
      expect(state.categories.any((c) => c.label == 'ワカサギ氷上釣り'), isTrue);
      // 未知のIDはフォールバック表示（例外にならない）
      final unknown = state.categoryOf('made-on-other-device');
      expect(unknown.label, 'made-on-other-device');
      // 同名カテゴリは拒否される
      final dup =
          await state.addCategory(label: 'ワカサギ氷上釣り', iconName: 'fishing');
      expect(dup, isNull);
      expect(state.categories.length, before + 1);
    });

    test('ブロックすると相手のプロフィール・募集・DM部屋が非表示になる（解除で戻る）',
        () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final hostId = state
          .activeRecruitments()
          .firstWhere((r) => r.hostId != state.me!.id)
          .hostId;
      // ブロック前: 一覧に見え、DM部屋も見える
      expect(state.generalUsers.any((u) => u.id == hostId), isTrue);
      expect(
          state.activeRecruitments().any((r) => r.hostId == hostId), isTrue);
      final dm = await state.getOrCreateDm(hostId);
      expect(state.myRooms.any((r) => r.id == dm.id), isTrue);

      await state.blockUser(hostId);
      expect(state.isBlocked(hostId), isTrue);
      expect(state.generalUsers.any((u) => u.id == hostId), isFalse);
      expect(
          state.activeRecruitments().any((r) => r.hostId == hostId), isFalse);
      expect(state.myRooms.any((r) => r.id == dm.id), isFalse);

      await state.unblockUser(hostId);
      expect(state.isBlocked(hostId), isFalse);
      expect(state.generalUsers.any((u) => u.id == hostId), isTrue);
      expect(
          state.activeRecruitments().any((r) => r.hostId == hostId), isTrue);
      expect(state.myRooms.any((r) => r.id == dm.id), isTrue);
    });

    test('ブロック一覧は端末に保存され、アプリ再起動でも復元される', () async {
      SharedPreferences.setMockInitialValues({});
      final state1 = AppState();
      state1.attachUser(_testUser(state1), reseed: true);
      final target = state1.generalUsers.first;
      await state1.blockUser(target.id);

      // 新しいインスタンス（= アプリ再起動）でも復元される
      final state2 = AppState();
      await state2.loadBlockedUsers();
      expect(state2.isBlocked(target.id), isTrue);
      expect(state2.blockedUserIds, contains(target.id));
    });

    test('コミュニティは近い順に並ぶ（メンバー内の最寄り距離でソート）', () {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final sorted = state.nearbyCommunities;
      expect(sorted, isNotEmpty);
      for (var i = 1; i < sorted.length; i++) {
        expect(state.communityDistanceKm(sorted[i - 1]),
            lessThanOrEqualTo(state.communityDistanceKm(sorted[i])));
      }
      // 全コミュニティが距離を持っている（シードのメンバーは現在地周囲に配置済み）
      for (final c in sorted) {
        expect(state.communityDistanceKm(c).isFinite, isTrue);
        expect(state.communityDistanceLabel(c), isNotEmpty);
      }
    });

    test('釣果速報: シードは近い順に並び、海・川湖両方を含む', () {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final reports = state.catchReports;
      expect(reports, isNotEmpty);
      expect(reports.any((r) => r.isSea), isTrue);
      expect(reports.any((r) => r.isFresh), isTrue);
      final me = state.me!;
      double km(CatchReport r) => haversineKm(me.lat, me.lng, r.lat, r.lng);
      for (var i = 1; i < reports.length; i++) {
        expect(km(reports[i - 1]), lessThanOrEqualTo(km(reports[i])));
      }
      for (final r in reports) {
        // 相対配置されているので全シードが現在地の近くにある
        expect(km(r), lessThan(6.0));
        expect(state.catchReportDistanceLabel(r), isNotEmpty);
      }
    });

    test('釣果速報: 登録して一覧に出し、掲載終了で消える', () async {
      final state = AppState();
      state.attachUser(_testUser(state), reseed: true);
      final created = await state.registerCatchReport(
        kind: 'sea',
        fishDescription: 'テスト魚（30cm・サビキ）',
        areaName: 'テスト堤防',
        detail: '回遊あり',
        photoPath: '/data/catch_photos/catch_photo_1.jpg',
      );
      expect(created.isSea, isTrue);
      expect(created.photoPath, '/data/catch_photos/catch_photo_1.jpg');
      expect(state.catchReports.any((r) => r.id == created.id), isTrue);
      await state.closeCatchReport(created.id);
      expect(state.catchReports.any((r) => r.id == created.id), isFalse);
    });
  });

  group('models', () {
    test('Recruitment の期限切れ / 満員状態（FR-2-1）', () {
      final now = DateTime(2026, 2, 1, 12, 0);
      final rec = Recruitment(
        id: 'r-x',
        hostId: 'h',
        genreId: 'shore',
        title: 't',
        body: 'b',
        meetup: 'm',
        capacity: 2,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 2)),
        memberIds: const ['h'],
      );
      expect(rec.isActiveAt(now), isTrue);
      expect(rec.statusAt(now), RecStatus.active);
      expect(rec.statusAt(now.add(const Duration(hours: 3))),
          RecStatus.expired);

      final full = Recruitment(
        id: rec.id,
        hostId: rec.hostId,
        genreId: rec.genreId,
        title: rec.title,
        body: rec.body,
        meetup: rec.meetup,
        capacity: rec.capacity,
        createdAt: rec.createdAt,
        expiresAt: rec.expiresAt,
        memberIds: const ['h', 'x'],
      );
      expect(full.isActiveAt(now), isFalse);
      expect(full.statusAt(now), RecStatus.fulfilled);
      expect(full.remainingSlots, 0);
    });
  });

  testWidgets('未ログインではログイン画面が出る', (tester) async {
    await tester.pumpWidget(const TsuritomoApp());
    expect(find.text('釣りとも！'), findsOneWidget);
    expect(find.text('ログイン'), findsWidgets);
    expect(find.text('はじめての方は会員登録へ'), findsOneWidget);
    expect(find.text('会員登録'), findsNothing);

    // 会員登録へ遷移できる
    await tester.tap(find.text('はじめての方は会員登録へ'));
    await tester.pumpAndSettle();
    expect(find.text('会員登録'), findsWidgets);
    // 同意前は先へ進めない（FR-1-4, 1.2）
    final next = find
        .ancestor(of: find.text('プロフィール入力へ'),
            matching: find.byType(FilledButton))
        .first;
    expect(tester.widget<FilledButton>(next).enabled, isFalse);
  });

  testWidgets('DMは承認不要で即座に部屋が開く（回帰テスト）', (tester) async {
    // DM部屋は募集と紐付かない（recruitmentId が空）のため、
    // チャット画面は募集を必須として扱ってはならない
    appState.attachUser(_testUser(appState), reseed: true);
    final other = appState.generalUsers.first;
    final room = await appState.getOrCreateDm(other.id);
    expect(room.isDm, isTrue);
    expect(room.recruitmentId, isEmpty);

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(roomId: room.id)),
    );
    await tester.pump();
    expect(find.text('部屋が見つかりません'), findsNothing);
    expect(find.text('DM（1:1）'), findsOneWidget);
    expect(find.text(other.nickname), findsOneWidget);

    // チャット画面のタイマーを破棄するため別の画面に差し替える
    await tester.pumpWidget(const SizedBox());
  });
}
