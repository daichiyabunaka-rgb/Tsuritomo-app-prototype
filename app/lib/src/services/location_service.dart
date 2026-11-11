import 'package:geolocator/geolocator.dart';

/// 位置情報サービス。近くの人を探すために端末の GPS を一度だけ取得する。
/// 失敗・拒否された場合はフォールバック（東京駅 + 手動選択）に黙って落ちる。
class LocationService {
  /// 位置情報を取得して (lat, lng) を返す。取れない場合は null。
  Future<(double, double)?> currentPosition() async {
    try {
      var serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 12),
        ),
      );
      return (position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }
}

/// グローバルインスタンス（本開発では DI / Riverpod Provider に置き換える）
final LocationService locationService = LocationService();
