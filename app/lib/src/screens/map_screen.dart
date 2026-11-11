import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;

import '../models.dart';
import '../services/app_config.dart';
import '../services/app_state.dart';
import 'store_sheet.dart';

/// 近くの店を地図で見る画面。
/// Google Maps SDK の API キー（--dart-define=GOOGLE_MAPS_API_KEY=...）が
/// 指定されている場合は Google マップ、未指定なら OpenStreetMap（APIキー不要）
/// で表示する。Googleマップアプリへの遷移は store_sheet の「Googleマップ」ボタン。
class MapScreen extends StatelessWidget {
  const MapScreen({super.key, this.highlightStoreId});

  final String? highlightStoreId;

  @override
  Widget build(BuildContext context) {
    final me = appState.me!;
    final stores = appState.businessUsers;
    final useGoogle = AppConfig.googleMapsApiKey.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('近くの店マップ')),
      body: useGoogle
          ? _GoogleMapBody(
              me: me, stores: stores, highlightStoreId: highlightStoreId)
          : _OsmMapBody(
              me: me, stores: stores, highlightStoreId: highlightStoreId),
    );
  }
}

class _GoogleMapBody extends StatelessWidget {
  const _GoogleMapBody(
      {required this.me, required this.stores, this.highlightStoreId});

  final AppUser me;
  final List<BusinessUser> stores;
  final String? highlightStoreId;

  @override
  Widget build(BuildContext context) {
    gmaps.LatLng initial = gmaps.LatLng(me.lat, me.lng);
    for (final s in stores) {
      if (s.id == highlightStoreId) {
        initial = gmaps.LatLng(s.lat, s.lng);
      }
    }
    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: initial,
        zoom: 14,
      ),
      markers: {
        // 自分（現在地）: 青
        gmaps.Marker(
          markerId: gmaps.MarkerId('me'),
          position: gmaps.LatLng(me.lat, me.lng),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueBlue),
          infoWindow: const gmaps.InfoWindow(title: '現在地'),
        ),
        // 近くの店: オレンジ（タップで店舗シート）
        for (final s in stores)
          gmaps.Marker(
            markerId: gmaps.MarkerId(s.id),
            position: gmaps.LatLng(s.lat, s.lng),
            icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              s.id == highlightStoreId
                  ? gmaps.BitmapDescriptor.hueOrange
                  : gmaps.BitmapDescriptor.hueRed,
            ),
            infoWindow: gmaps.InfoWindow(
              title: s.nickname,
              snippet: s.storeType,
            ),
            onTap: () => showStoreSheet(context, s),
          ),
      },
    );
  }
}

class _OsmMapBody extends StatelessWidget {
  const _OsmMapBody(
      {required this.me, required this.stores, this.highlightStoreId});

  final AppUser me;
  final List<BusinessUser> stores;
  final String? highlightStoreId;

  @override
  Widget build(BuildContext context) {
    ll.LatLng? initial;
    for (final s in stores) {
      if (s.id == highlightStoreId) {
        initial = ll.LatLng(s.lat, s.lng);
      }
    }
    return FlutterMap(
      options: MapOptions(
        initialCenter: initial ?? ll.LatLng(me.lat, me.lng),
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.tsuritomo.tsuritomo',
        ),
        MarkerLayer(
          markers: [
            // 自分（現在地）: 青丸
            Marker(
              point: ll.LatLng(me.lat, me.lng),
              width: 24,
              height: 24,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
            // 近くの店: オレンジのピン（タップで店舗シート）
            for (final s in stores)
              Marker(
                point: ll.LatLng(s.lat, s.lng),
                width: 44,
                height: 44,
                child: Builder(
                  builder: (context) => InkWell(
                    onTap: () => showStoreSheet(context, s),
                    child: Icon(
                      Icons.location_on,
                      size: 44,
                      color: s.id == highlightStoreId
                          ? Colors.deepOrange
                          : Colors.orange,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
