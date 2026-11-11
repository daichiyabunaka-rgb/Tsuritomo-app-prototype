import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'format.dart';

/// 「近くの釣り場を探す」機能のデータ層。
/// 釣りスポット情報共有MAPくん（合同会社ファービヨンド https://share-map.net/fishing/ ）
/// のWeb版が使うのと同じデータ取得経路から現在地周辺の釣りスポットを取得する。
///
/// 仕組み:
/// 1. Web版ページ (GET /fishing/) を取得し、ページに埋め込まれた
///    get_objects 用の api_keyと my_connection_id を取り出す
///    （どちらもページを開くたびに変わる）
/// 2. POST /fishing/api/ に cmd=get_objects と矩形範囲を送ると、
///    地点リストが AES-256-CBC で暗号化された JSON で返ってくる
///    （鍵 = SHA256(ページ埋め込みの静的ID)、IV = レスポンスの ufydirelx）
/// 3. 復号した地点リストから**有料系施設（釣り堀・海釣り公園・室内釣り場・
///    コンクリート釣り場など）と釣具店ピンを除外**し、距離順に並べる
///
/// 注意: 本番リリース前に運営（ファービヨンド）への利用許諾を取ること。
/// MAPくんのデータは釣り人による投稿。付近が広いと「too_many_geo_objects」
/// になるため、矩形をタイル分割して取得する。
///
/// 同一地点（約100mグリッド）では30分の端末内キャッシュを優先して返す。

const String mapkunBase = 'https://share-map.net';
const String mapkunPage = 'https://share-map.net/fishing/';
const String mapkunApi = 'https://share-map.net/fishing/api/';

/// Web版ページに埋め込まれる静的な復号用ID（2026年2月時点）。
/// レスポンスのAES復号鍵 = SHA256(この文字列) の生バイト。
const String mapkunYourId =
    'f0a99dd2364c8b0040ef46ecfa213592d6a7d91439f642f214283f08fada84bd';

const int maxSpots = 100;
const double searchRadiusKm = 5.0;
/// 一覧の1画面あたりの表示件数（スクロールで「さらに表示」）
const int spotBatchSize = 50;
/// 1リクエストの矩形の一辺（度）。広すぎると too_many_geo_objects になる
const double tileDegrees = 0.08;
const Duration spotFetchTimeout = Duration(seconds: 60);
const Duration spotCacheTtl = Duration(minutes: 30);

const String _kBrowserUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// ------------------------------------------------------------- session

class _MapkunSession {
  final String apiKey;
  final String connectionId;
  const _MapkunSession(this.apiKey, this.connectionId);
}

_MapkunSession? _memSession;
DateTime _sessionAt = DateTime.fromMillisecondsSinceEpoch(0);

/// ページからapi_key / my_connection_idを取り出す（純関数）。テストで使う。
({String apiKey, String connectionId}) parseMapkunPage(String html) {
  // api_keyはページに2つ出てくる。1つ目は get_objects_by_names（検索用）、
  // 2つ目が get_objects（地図用）なので2つ目を使う。
  final keys = RegExp(r'api_key","([0-9a-z]{16})')
      .allMatches(html)
      .map((m) => m.group(1)!)
      .toList();
  final conn = RegExp(r'my_connection_id.{0,20}"([0-9a-f]{64})')
      .firstMatch(html)
      ?.group(1);
  if (keys.length < 2 || conn == null) {
    throw const SpotFetchException('釣り場ページの解析に失敗しました');
  }
  return (apiKey: keys[1], connectionId: conn);
}

Future<_MapkunSession> _obtainSession(http.Client c) async {
  final now = DateTime.now();
  if (_memSession != null && now.isBefore(_sessionAt.add(spotCacheTtl))) {
    return _memSession!;
  }
  final page = await c
      .get(Uri.parse(mapkunPage), headers: {'User-Agent': _kBrowserUa})
      .timeout(spotFetchTimeout);
  if (page.statusCode != 200) {
    throw SpotFetchException('MAPくんページの取得に失敗しました: ${page.statusCode}');
  }
  final parsed = parseMapkunPage(utf8.decode(page.bodyBytes));
  final session = _MapkunSession(parsed.apiKey, parsed.connectionId);
  _memSession = session;
  _sessionAt = now;
  return session;
}

void invalidateMapkunSession() {
  _memSession = null;
  _sessionAt = DateTime.fromMillisecondsSinceEpoch(0);
}

/// ------------------------------------------------------------ payload

/// MAPくんの暗号化レスポンスを復号する（純関数）。
/// 鍵 = SHA256(静的ID)の生バイト（32byte）、IV = ufydirelx の hex。
String decryptMapkunPayload(String cipherBase64, String ivHex) {
  final digest = crypto.sha256.convert(utf8.encode(mapkunYourId));
  final key = enc.Key(Uint8List.fromList(digest.bytes));
  final encrypter =
      enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'));
  return encrypter.decrypt(
    enc.Encrypted.fromBase64(cipherBase64),
    iv: enc.IV.fromBase16(ivHex),
  );
}

/// MAPくんのHTTPレスポンス（暗号化JSON）を FishingSpot の一覧に変換する。
/// 純関数として切り出してテストできるようにしている。
List<FishingSpot> decodeMapkunResponse(String body, double lat, double lng,
    {double radiusKm = searchRadiusKm}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const SpotFetchException('不正なレスポンス形式です');
  }
  if (decoded['status'] != 'success') {
    final code = decoded['error_code'] as String? ?? 'unknown';
    if (code == 'too_many_geo_objects') {
      throw const SpotFetchException('too_many_geo_objects');
    }
    throw const SpotFetchException('MAPくんから拒否されました');
  }
  final cipher = decoded['ufydirelw'] as String?;
  final ivHex = decoded['ufydirelx'] as String?;
  if (cipher == null || ivHex == null) {
    throw const SpotFetchException('MAPくんの応答に地点データがありません');
  }
  final plain = decryptMapkunPayload(cipher, ivHex);
  return parseMapkunSpots(plain, lat, lng, radiusKm: radiusKm);
}

/// 復号済みの地点リスト（JSON配列）を FishingSpot に変換する。
/// 釣り堀（pond）・海釣り公園（sea_preserve）・室内釣り場（indoor_fishing）・
/// コンクリート釣り場（concrete_preserve）など有料・管理系の施設と、
/// 釣具店（shop）のピンは除外する（無料で入れる釣り場だけを出す設計）。
List<FishingSpot> parseMapkunSpots(String plainJson, double lat, double lng,
    {double radiusKm = searchRadiusKm}) {
  final decoded = jsonDecode(plainJson);
  if (decoded is! List) {
    throw const SpotFetchException('地点リストの形式が不正です');
  }
  final byId = <String, FishingSpot>{};
  for (final e in decoded) {
    if (e is! Map<String, dynamic>) continue;
    final spot = _rowToFishingSpot(e, lat, lng);
    if (spot == null) continue;
    if (spot.distanceKm > radiusKm) continue;
    final existing = byId[spot.id];
    if (existing == null || spot.distanceKm < existing.distanceKm) {
      byId[spot.id] = spot;
    }
  }
  final spots = byId.values.toList()
    ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  return spots.take(maxSpots).toList(growable: false);
}

FishingSpot? _rowToFishingSpot(Map<String, dynamic> row, double lat, double lng) {
  final id = row['coordinate_id']?.toString();
  final latText = row['lat']?.toString();
  final lngText = row['lng']?.toString();
  if (id == null || latText == null || lngText == null) return null;
  final pLat = double.tryParse(latText);
  final pLng = double.tryParse(lngText);
  if (pLat == null || pLng == null) return null;

  bool flag(String key) => row[key]?.toString() == '1';

  // 有料・管理系施設と釣具店は出さない（無料で釣れる場所に限定する）
  if (flag('shop')) return null;
  if (flag('pond')) return null; // 釣り堀
  if (flag('indoor_fishing')) return null; // 室内釣り場
  if (flag('sea_preserve')) return null; // 海釣り公園
  if (flag('concrete_preserve')) return null; // コンクリート釣り場

  final name = (row['name'] as String?)?.trim();
  final isSea = row['sea_fishing']?.toString() == '1';
  final isFresh = row['river_fishing']?.toString() == '1';
  final feeFree = row['no_fee']?.toString() == '1';
  final is24h = row['is_24_hours']?.toString() == '1';

  final reputation =
      double.tryParse(row['reputation_avg']?.toString() ?? '') ?? 0;

  return FishingSpot(
    id: id,
    name: (name == null || name.isEmpty) ? '名称未登録の釣り場' : name,
    spotType: _spotTypeOf(row),
    lat: pLat,
    lng: pLng,
    distanceKm: haversineKm(lat, lng, pLat, pLng),
    isSea: isSea,
    isFresh: isFresh,
    feeFreeKnown: feeFree,
    is24Hours: is24h,
    businessHours: is24h ? null : _businessHours(row),
    reputationAvg: reputation,
    fishes: _clean(row['fishes'] as String?),
    memo: _clean(row['memo'] as String?),
  );
}

String _spotTypeOf(Map<String, dynamic> row) {
  const pairs = {
    'pier': '桟橋',
    'breakwater': '堤防',
    'revetment': '護岸',
    'deck': 'デッキ',
    'raft': 'イカダ',
    'mega_floot': 'メガフロート',
    'artificial_shor': '人工海浜',
  };
  for (final e in pairs.entries) {
    if (row[e.key]?.toString() == '1') return e.value;
  }
  return '釣り場';
}

String? _businessHours(Map<String, dynamic> row) {
  final start = (row['bh1_start'] as String?)?.substring(0, 5);
  final end = (row['bh1_end'] as String?)?.substring(0, 5);
  if (start == null || end == null) return null;
  final startText = start.endsWith(':00') ? start.substring(0, 2) : start;
  final endText = end.endsWith(':00') ? end.substring(0, 2) : end;
  return '$startText〜$endText';
}

String? _clean(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// -------------------------------------------------------------- fetch

/// 現在地周辺の釣り場を取得する（距離昇順）。
/// 同一地点（約100mグリッド）で30分以内の取得結果があればキャッシュを返す。
Future<List<FishingSpot>> fetchFishingSpotsNear(
  double lat,
  double lng, {
  http.Client? client,
  bool forceRefresh = false,
}) async {
  final key = _cacheKey(lat, lng);
  final now = DateTime.now();
  if (!forceRefresh) {
    if (_memSpots != null &&
        _memKey == key &&
        now.isBefore(_memAt.add(spotCacheTtl))) {
      return _memSpots!;
    }
    final disk = await _loadDiskCache(key, now);
    if (disk != null) {
      _memKey = key;
      _memAt = now;
      _memSpots = disk;
      return disk;
    }
  }
  final c = client ?? http.Client();
  try {
    final spots = await _fetchWithTiles(lat, lng, c);
    _memKey = key;
    _memAt = DateTime.now();
    _memSpots = spots;
    await _saveDiskCache(key, spots, _memAt);
    return spots;
  } finally {
    if (client == null) c.close();
  }
}

Future<List<FishingSpot>> _fetchWithTiles(double lat, double lng,
    http.Client c) async {
  final dLat = searchRadiusKm / 111.32;
  final cosLat = (lat * 3.1415926535897932 / 180.0).abs().clamp(0.01, 1.0);
  final dLng = searchRadiusKm / (111.32 * cosLat);
  final merged = <String, FishingSpot>{};
  for (final tile in _tilesFor(
      lat - dLat, lat + dLat, lng - dLng, lng + dLng)) {
    final spots =
        await _fetchTile(tile, c, userLat: lat, userLng: lng, retriedSession: false);
    for (final s in spots) {
      final existing = merged[s.id];
      if (existing == null) merged[s.id] = s;
    }
  }
  final list = merged.values
      .where((s) => s.distanceKm <= searchRadiusKm)
      .toList()
    ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  return list.take(maxSpots).toList(growable: false);
}

List<({double latFrom, double latTo, double lngFrom, double lngTo})>
    _tilesFor(double latFrom, double latTo, double lngFrom, double lngTo) {
  final tiles = <({double latFrom, double latTo, double lngFrom, double lngTo})>[];
  for (var la = latFrom; la < latTo; la += tileDegrees) {
    final laTo = la + tileDegrees >= latTo - 1e-9 ? latTo : la + tileDegrees;
    for (var lo = lngFrom; lo < lngTo; lo += tileDegrees) {
      final loTo = lo + tileDegrees >= lngTo - 1e-9 ? lngTo : lo + tileDegrees;
      tiles.add((latFrom: la, latTo: laTo, lngFrom: lo, lngTo: loTo));
    }
  }
  return tiles;
}

Future<List<FishingSpot>> _fetchTile(
    ({double latFrom, double latTo, double lngFrom, double lngTo}) tile,
    http.Client c, {
    required double userLat,
    required double userLng,
    required bool retriedSession,
  }) async {
  final session = await _obtainSession(c);
  final body = 'api_key=${session.apiKey}&cmd=get_objects'
      '&lat_from=${tile.latFrom}&lat_to=${tile.latTo}'
      '&lng_from=${tile.lngFrom}&lng_to=${tile.lngTo}';
  final res = await c
      .post(
        Uri.parse(mapkunApi),
        headers: {
          'User-Agent': _kBrowserUa,
          'Referer': mapkunPage,
          'Origin': mapkunBase,
          'X-Requested-With': 'XMLHttpRequest',
          'Cookie': 'my_connection_id=${session.connectionId}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      )
      .timeout(spotFetchTimeout);
  final text = utf8.decode(res.bodyBytes);
  if (res.statusCode != 200) {
    throw SpotFetchException('MAPくんAPIエラー: ${res.statusCode}');
  }
  try {
    return decodeMapkunResponse(text, userLat, userLng,
        radiusKm: 1e9); // 距離フィルタは merge 後に改めてかける
  } on SpotFetchException catch (e) {
    if (e.message == 'too_many_geo_objects' &&
        (tile.latTo - tile.latFrom) > 0.02) {
      // 地点が多すぎる矩形は4分割して取り直す
      final midLat = (tile.latFrom + tile.latTo) / 2;
      final midLng = (tile.lngFrom + tile.lngTo) / 2;
      final merged = <String, FishingSpot>{};
      for (final sub in [
        (latFrom: tile.latFrom, latTo: midLat, lngFrom: tile.lngFrom, lngTo: midLng),
        (latFrom: midLat, latTo: tile.latTo, lngFrom: tile.lngFrom, lngTo: midLng),
        (latFrom: tile.latFrom, latTo: midLat, lngFrom: midLng, lngTo: tile.lngTo),
        (latFrom: midLat, latTo: tile.latTo, lngFrom: midLng, lngTo: tile.lngTo),
      ]) {
        final spots = await _fetchTile(sub, c,
            userLat: userLat, userLng: userLng, retriedSession: retriedSession);
        for (final s in spots) {
          merged[s.id] ??= s;
        }
      }
      return merged.values.toList();
    }
    if (e.message == 'MAPくんから拒否されました' && !retriedSession) {
      // api_keyはページを開くたびに変わる。セッションを作り直して一度だけ再試行
      invalidateMapkunSession();
      return _fetchTile(tile, c,
          userLat: userLat, userLng: userLng, retriedSession: true);
    }
    rethrow;
  }
}

// ------------------------------------------------------------ cache

String _cacheKey(double lat, double lng) =>
    'spots@${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

List<FishingSpot>? _memSpots;
String? _memKey;
DateTime _memAt = DateTime.fromMillisecondsSinceEpoch(0);
const String _kDiskCache = 'tsuritomo_spot_cache';

Map<String, dynamic> fishingSpotToMap(FishingSpot s) => {
      'id': s.id,
      'name': s.name,
      'spotType': s.spotType,
      'lat': s.lat,
      'lng': s.lng,
      'km': s.distanceKm,
      'sea': s.isSea,
      'fresh': s.isFresh,
      'feeFree': s.feeFreeKnown,
      'is24h': s.is24Hours,
      'hours': s.businessHours,
      'reputation': s.reputationAvg,
      'fishes': s.fishes,
      'memo': s.memo,
    };

FishingSpot fishingSpotFromMap(Map<String, dynamic> m) => FishingSpot(
      id: m['id'] as String,
      name: m['name'] as String,
      spotType: m['spotType'] as String,
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      distanceKm: (m['km'] as num).toDouble(),
      isSea: (m['sea'] as bool?) ?? false,
      isFresh: (m['fresh'] as bool?) ?? false,
      feeFreeKnown: (m['feeFree'] as bool?) ?? false,
      is24Hours: (m['is24h'] as bool?) ?? false,
      businessHours: m['hours'] as String?,
      reputationAvg: (m['reputation'] as num?)?.toDouble() ?? 0,
      fishes: m['fishes'] as String?,
      memo: m['memo'] as String?,
    );

Future<List<FishingSpot>?> _loadDiskCache(String key, DateTime now) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDiskCache);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    if (m['key'] != key) return null;
    final at = DateTime.tryParse(m['at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    if (now.isAfter(at.add(spotCacheTtl))) return null;
    final list = (m['spots'] as List)
        .map((e) => fishingSpotFromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return list.isEmpty ? null : list;
  } catch (_) {
    return null;
  }
}

Future<void> _saveDiskCache(String key, List<FishingSpot> spots, DateTime at) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDiskCache, jsonEncode({
      'key': key,
      'at': at.toIso8601String(),
      'spots': spots.map(fishingSpotToMap).toList(),
    }));
  } catch (_) {
    // 保存失敗は無視（メモリキャッシュは有効）
  }
}

class SpotFetchException implements Exception {
  final String message;
  const SpotFetchException(this.message);
  @override
  String toString() => message;
}

/// 釣り場の「Googleマップで開く」URL（座標指定。迷わず正確な位置が開く）
String googleMapsUrlForSpot(FishingSpot spot) {
  return 'https://www.google.com/maps/search/?api=1&query=${spot.lat},${spot.lng}';
}
