import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../util/fishing_spots.dart';
import '../util/format.dart';
import 'recruitment_create_sheet.dart';

/// 「近くの釣り場」タブ（釣りとも！の特別機能）。
/// 現在地の近くの釣りスポットを近い順に表示する
/// （OpenStreetMap の釣り場・桟橋・釣り可水域データ）。
/// 各釣り場はGoogleマップで開けるほか、その釣り場で直接募集をかけられる。
class SpotPage extends StatefulWidget {
  const SpotPage({super.key});

  @override
  State<SpotPage> createState() => _SpotPageState();
}

class _SpotPageState extends State<SpotPage> {
  String? _anchorKey;
  late Future<List<FishingSpot>> _future;
  int _shownCount = spotBatchSize; // 50件ずつ表示（スクロールで増やす）

  void _reloadIfNeeded() {
    final key =
        '${appState.anchorLat.toStringAsFixed(5)},${appState.anchorLng.toStringAsFixed(5)}';
    if (key == _anchorKey) return;
    _anchorKey = key;
    _future = fetchFishingSpotsNear(appState.anchorLat, appState.anchorLng);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        _reloadIfNeeded();
        return RefreshIndicator(
          onRefresh: () async {
            final f = fetchFishingSpotsNear(appState.anchorLat, appState.anchorLng,
                forceRefresh: true);
            setState(() {
              _anchorKey =
                  '${appState.anchorLat.toStringAsFixed(5)},${appState.anchorLng.toStringAsFixed(5)}';
              _future = f;
              _shownCount = spotBatchSize;
            });
            await f;
          },
          child: FutureBuilder<List<FishingSpot>>(
            key: ValueKey(_anchorKey),
            future: _future,
            builder: (context, snapshot) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 4),
                  Text(
                    '現在地の近くの釣り場を近い順に表示します。',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (snapshot.connectionState != ConnectionState.done &&
                      !snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            '周辺の釣り場を検索しています…\n'
                            '初回は30秒〜1分ほどかかることがあります',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  if (snapshot.hasError) _errorCard(theme),
                  if (snapshot.hasData) ...[
                    if (snapshot.data!.isEmpty) _emptyCard(theme),
                    for (final s in snapshot.data!.take(_shownCount))
                      _spotCard(context, s),
                    // 50件ずつ表示（「さらに表示」で追加）
                    if (snapshot.data!.length > _shownCount)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton(
                          onPressed: () => setState(
                              () => _shownCount += spotBatchSize),
                          child: Text(
                              'さらに表示（残り${snapshot.data!.length - _shownCount}件）'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _errorCard(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text('釣り場情報を取得できませんでした。通信状況をご確認ください。',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('再読み込み'),
            onPressed: () => setState(() => _anchorKey = null),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Icon(Icons.set_meal, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text('近くに釣り場が見つかりませんでした。',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _spotCard(BuildContext context, FishingSpot s) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  s.isPier ? Icons.directions_boat : Icons.phishing,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: theme.textTheme.titleMedium!
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.typeLabel} / ${distanceLabel(s.distanceKm)}',
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (s.openingHours != null) ...[
              const SizedBox(height: 6),
              Text('時間: ${s.openingHours!}',
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (s.fishingRule == 'yes') _chip(theme, '釣り可'),
                if (s.fishingRule == 'permit') _chip(theme, '要遊漁券'),
                if (s.feeFreeKnown) _chip(theme, '無料'),
                if (s.fishingRule == 'unknown')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '釣り可否は現地の看板・遊漁規則をご確認ください',
                      style: theme.textTheme.labelSmall!
                          .copyWith(color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label:
                        const Text('Googleマップで開く', style: TextStyle(fontSize: 13)),
                    onPressed: () => _openGoogleMaps(s),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.campaign, size: 18),
                    label: const Text('この釣り場で募集',
                        style: TextStyle(fontSize: 13)),
                    onPressed: () =>
                        showRecruitmentCreateSheet(context, initialMeetup: s.name),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }

  Future<void> _openGoogleMaps(FishingSpot spot) async {
    try {
      await launchUrl(Uri.parse(googleMapsUrlForSpot(spot)),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      // Googleマップアプリが無い環境では無視
    }
  }
}
