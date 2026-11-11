import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'format.dart';

/// 「近くの釣り場を探す」機能のデータ層。
/// OpenStreetMap の Overpass API で現在地周辺の**釣りスポット**を取得する。
/// - 対象は次のいずれか:
///   - leisure=fishing（釣り場として登録された場所）
///   - fishing=yes / fishing=permit（釣り可・遊漁券が必要の水域や地点）
///   - man_made=pier（釣りによく使われる桟橋・堤防）
/// - 釣りが明確に禁止（fishing=no）・立入禁止（fishing=private）の場所は除外
///   する。fishing=permit の場合は「要遊漁券」と表示する
/// - waysのみ取得（relationsを含むbboxクエリは重すぎて各サーバーが
///   502/504を返すため。relationのみの大きな水域は表示されない）
/// - 取得には30〜60秒ほどかかることがあるため、同一場所なら
///   端末内キャッシュ（約100mグリッド・30分）を優先して返す
/// 取得結果は現在地からの距離の昇順に並べる。

/// Overpass サーバー（本家は混雑しやすいので、順にフォールバックする）
const List<String> overpassEndpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

const int maxSpots = 100;
const double searchRadiusKm = 5.0;
/// 一覧の1画面あたりの表示件数（スクロールで「さらに表示」）
const int spotBatchSize = 50;
/// 本家サーバーの混雑時は応答まで30〜60秒かかる
const Duration spotFetchTimeout = Duration(seconds: 60);
const Duration spotCacheTtl = Duration(minutes: 30);

/// Overpass は既定の User-Agent を持つ要求を拒否（406）するため、
/// 必ずアプリ名入り UA を送る
Map<String, String> get spotHttpHeaders => {
      'User-Agent':
          'Tsuritomo/1.0 (Android; fishing spot search; +https://github.com/daichiyabunaka-rgb/Tsuritomo-app-prototype)',
      'Accept': 'application/json',
    };

/// Overpass API に投げるクエリ（bbox は南,西,北,東の順）
String buildOverpassQuery(double lat, double lng, {double radiusKm = searchRadiusKm}) {
  final dLat = radiusKm / 111.32;
  final cosLat = (lat * 3.1415926535897932 / 180.0).abs().clamp(0.01, 1.0);
  final dLng = radiusKm / (111.32 * cosLat);
  final south = lat - dLat;
  final west = lng - dLng;
  final north = lat + dLat;
  final east = lng + dLng;
  final bbox = '$south,$west,$north,$east';
  return '[out:json][timeout:25];'
      '('
      'node["leisure"="fishing"]($bbox);'
      'way["leisure"="fishing"]($bbox);'
      'node["fishing"~"^(yes|permit)\$"]($bbox);'
      'way["fishing"~"^(yes|permit)\$"]($bbox);'
      'node["man_made"="pier"]["fishing"!~"^(no|private)\$"]($bbox);'
      'way["man_made"="pier"]["fishing"!~"^(no|private)\$"]($bbox);'
      ');'
      'out center tags;';
}

/// 現在地周辺の釣りスポットを取得する（距離昇順）。
/// 同一地点（約100mグリッド）で30分以内の取得結果があればキャッシュを返す。
/// Overpass のサーバーに順にフォールバックし、すべて失敗したら例外を投げる。
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
  final spots = await _fetchFromOverpass(lat, lng, client ?? http.Client(),
      clientProvided: client != null);
  _memKey = key;
  _memAt = DateTime.now();
  _memSpots = spots;
  await _saveDiskCache(key, spots, _memAt);
  return spots;
}

Future<List<FishingSpot>> _fetchFromOverpass(
    double lat, double lng, http.Client c,
    {required bool clientProvided}) async {
  try {
    Object? lastError;
    for (final endpoint in overpassEndpoints) {
      try {
        final res = await c
            .post(
              Uri.parse(endpoint),
              headers: spotHttpHeaders,
              body: {'data': buildOverpassQuery(lat, lng)},
            )
            .timeout(spotFetchTimeout);
        if (res.statusCode != 200) {
          throw SpotFetchException('Overpass API エラー: ${res.statusCode}');
        }
        return parseOverpassResponse(res.body, lat, lng);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const SpotFetchException('釣り場情報を取得できませんでした');
  } finally {
    if (!clientProvided) c.close();
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
      'id': s.osmId,
      'name': s.name,
      'type': s.type,
      'lat': s.lat,
      'lng': s.lng,
      'km': s.distanceKm,
      'fishing': s.fishingRule,
      'feeFree': s.feeFreeKnown,
      'hours': s.openingHours,
    };

FishingSpot fishingSpotFromMap(Map<String, dynamic> m) => FishingSpot(
      osmId: m['id'] as String,
      name: m['name'] as String,
      type: m['type'] as String,
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      distanceKm: (m['km'] as num).toDouble(),
      fishingRule: (m['fishing'] as String?) ?? 'unknown',
      feeFreeKnown: (m['feeFree'] as bool?) ?? false,
      openingHours: m['hours'] as String?,
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

/// Overpass の JSON を FishingSpot の一覧（距離昇順）に変換する。
/// 純関数として切り出してテストできるようにしている。
List<FishingSpot> parseOverpassResponse(String body, double lat, double lng) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic> || decoded['elements'] is! List) {
    throw const SpotFetchException('不正なレスポンス形式です');
  }
  final spots = <FishingSpot>[];
  for (final e in decoded['elements'] as List) {
    if (e is! Map<String, dynamic>) continue;
    final elementId = e['id'];
    if (elementId == null) continue;
    final osmType = (e['type'] as String?) ?? '';
    final tags = (e['tags'] as Map?)?.cast<String, String>() ?? const {};
    // 釣りが明確に禁止・立入禁止の場所は除外
    final fishing = tags['fishing'];
    if (fishing == 'no' || fishing == 'private') continue;
    // 対象は leisure=fishing / fishing=yes|permit / man_made=pier
    final isFishingPlace = tags['leisure'] == 'fishing';
    final isPermitted = fishing == 'yes' || fishing == 'permit';
    final isPier = tags['man_made'] == 'pier';
    if (!isFishingPlace && !isPermitted && !isPier) continue;
    // 位置: node は直接持つ。way / relation は out center で付く center を使う
    double? pLat = (e['lat'] as num?)?.toDouble();
    double? pLng = (e['lon'] as num?)?.toDouble();
    final center = e['center'];
    if (center is Map) {
      pLat = (center['lat'] as num?)?.toDouble() ?? pLat;
      pLng = (center['lon'] as num?)?.toDouble() ?? pLng;
    }
    if (pLat == null || pLng == null) continue;
    spots.add(FishingSpot(
      osmId: '$osmType/$elementId',
      name: tags['name'] ?? '名称未登録の釣り場',
      type: isFishingPlace
          ? 'spot'
          : isPier
              ? 'pier'
              : 'water',
      lat: pLat,
      lng: pLng,
      distanceKm: haversineKm(lat, lng, pLat, pLng),
      fishingRule: isPermitted ? fishing! : 'unknown',
      feeFreeKnown: tags['fee'] == 'no',
      openingHours: tags['opening_hours'],
    ));
  }
  spots.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  return spots.take(maxSpots).toList(growable: false);
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
