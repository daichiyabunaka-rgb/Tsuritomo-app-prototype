import 'dart:math' as math;

/// 仕様書 FR-2-2: 距離は粗いバンド表示のみ（正確な位置は非公開）
String distanceLabel(double km) {
  if (km < 1) return '〜1km';
  if (km < 3) return '1〜3km';
  if (km < 5) return '3〜5km';
  if (km < 10) return '5〜10km';
  return '10km〜';
}

String remainingLabel(DateTime expiresAt, DateTime now) {
  final diff = expiresAt.difference(now);
  if (diff.isNegative) return '終了';
  final minutes = diff.inMinutes;
  if (minutes >= 60) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '残り$h時間' : '残り$h時間$m分';
  }
  return '残り$minutes分';
}

/// 投稿からの経過ラベル（例: '3時間前' / '2日前'）
String elapsedLabel(DateTime createdAt, DateTime now) {
  final diff = now.difference(createdAt);
  if (diff.inMinutes < 1) return 'たった今';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
  if (diff.inHours < 24) return '${diff.inHours}時間前';
  return '${diff.inDays}日前';
}

/// Haversine 距離（km）。本開発では端末側で geohash 化して送信するため、
/// この計算はモック用。表示は必ず distanceLabel でバンド化する。
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double deg2rad(double d) => d * math.pi / 180.0;
  final dLat = deg2rad(lat2 - lat1);
  final dLng = deg2rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2).toDouble() +
      math.pow(math.sin(dLng / 2), 2).toDouble() *
          math.cos(deg2rad(lat1)) *
          math.cos(deg2rad(lat2));
  return 2 * r * math.asin(math.sqrt(a));
}
