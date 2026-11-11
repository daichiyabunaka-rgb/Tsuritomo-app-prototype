/// Geohash の encode / decode（位置の近傍検索に使う。DBには生の緯度経度を保存せず
/// geohash のみ渡す設計: 仕様書 6 章「位置情報プライバシー」）
library;

const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// [precision] 5 = 約4.9km四方、6 = 約1.2km四方
String geohashEncode(double lat, double lng, {int precision = 6}) {
  var latMin = -90.0;
  var latMax = 90.0;
  var lngMin = -180.0;
  var lngMax = 180.0;
  final buf = StringBuffer();
  var bit = 0;
  var ch = 0;
  var isEven = true;
  while (buf.length < precision) {
    if (isEven) {
      final mid = (lngMin + lngMax) / 2;
      if (lng >= mid) {
        ch = (ch << 1) + 1;
        lngMin = mid;
      } else {
        ch = ch << 1;
        lngMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        ch = (ch << 1) + 1;
        latMin = mid;
      } else {
        ch = ch << 1;
        latMax = mid;
      }
    }
    isEven = !isEven;
    if (bit < 4) {
      bit++;
    } else {
      buf.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return buf.toString();
}

/// geohash セルのおおよその中心座標（距離バンド表示の概算に使う）
(double, double) geohashDecode(String hash) {
  var latMin = -90.0;
  var latMax = 90.0;
  var lngMin = -180.0;
  var lngMax = 180.0;
  var isEven = true;
  for (final c in hash.codeUnits) {
    final idx = _base32.indexOf(String.fromCharCode(c));
    if (idx < 0) {
      throw ArgumentError('invalid geohash char: $c');
    }
    for (var bit = 4; bit >= 0; bit--) {
      final value = (idx >> bit) & 1;
      if (isEven) {
        final mid = (lngMin + lngMax) / 2;
        if (value == 1) {
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (value == 1) {
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
      isEven = !isEven;
    }
  }
  return ((latMin + latMax) / 2, (lngMin + lngMax) / 2);
}
