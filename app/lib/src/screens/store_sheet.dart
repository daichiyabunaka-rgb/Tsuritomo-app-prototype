import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/app_config.dart';
import '../services/app_state.dart';
import 'ai_concierge_screen.dart';
import 'chat_screen.dart';
import 'community_detail_screen.dart';
import 'map_screen.dart';
import 'widgets.dart';

/// 店舗（ビジネスユーザー）の詳細シート。「近く」とマップ画面の両方から使う。
/// 電話はタップで発信、SNS/URLも表示。お店（スタッフ）へのDMもここから開始できる。
Future<void> _callStore(String phone) async {
  try {
    await launchUrl(Uri.parse('tel:$phone'));
  } catch (_) {}
}

Future<void> _openUrl(String raw) async {
  final url =
      raw.startsWith('http://') || raw.startsWith('https://') ? raw : 'https://$raw';
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}
Future<void> showStoreSheet(BuildContext context, BusinessUser store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      builder: (sheetContext, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                tappableAvatar(context, store.id, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.nickname,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium!
                              .copyWith(fontWeight: FontWeight.bold)),
                      Text(
                          '${store.storeType} / ${appState.userDistanceLabel(store)}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(store.bio),
            if (store.phone?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _callStore(store.phone!),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone,
                          size: 18,
                          color: Theme.of(sheetContext).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        store.phone!,
                        style: TextStyle(
                          color:
                              Theme.of(sheetContext).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('タップで電話',
                          style: Theme.of(sheetContext).textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            ],
            if (store.snsNote?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.alternate_email,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Flexible(child: Text(store.snsNote!)),
                ],
              ),
            ],
            if (store.websiteUrl?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _openUrl(store.websiteUrl!),
                child: Row(
                  children: [
                    Icon(Icons.link,
                        size: 16,
                        color: Theme.of(sheetContext).colorScheme.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        store.websiteUrl!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              Theme.of(sheetContext).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('お店にDMする（スタッフ対応）'),
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  final room = await appState.getOrCreateDm(store.id);
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(roomId: room.id),
                    ),
                  );
                },
              ),
            ),
            Builder(builder: (_) {
              final fan = appState.fanCommunityOfStore(store.nickname);
              if (fan == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.groups_outlined),
                    label: Text('ファンコミュニティ「${fan.name}」を見る'),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CommunityDetailScreen(
                              communityId: fan.id),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('マップ'),
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MapScreen(highlightStoreId: store.id),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Googleマップ'),
                    onPressed: () =>
                        openInGoogleMaps(store),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.lock_outline),
                label: const Text('AI接客（ベータ期間中は準備中）'),
                onPressed: AppConfig.aiConciergeEnabled
                    ? () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AiConciergeScreen(storeId: store.id),
                          ),
                        );
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppConfig.aiConciergeEnabled
                  ? 'AI接客はビジネスユーザー向けの機能です。'
                      '本リリース後は LLM による来店前の質問対応・営業文の'
                      '作成支援をビジネスプランとして提供します。'
                  : 'AI接客は本リリース後に提供予定です。'
                      'ベータ期間中はお店へのDM・電話・地図連携を'
                      '無料でご利用いただけます。',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Google マップアプリ/ブラウザで店舗の場所を開く（APIキー不要の標準URL）。
/// 本開発では Google Maps SDK（Google Cloud の API キー）に置き換えて、
/// アプリ内で経路案内まで表示できるようにする予定。
Future<void> openInGoogleMaps(BusinessUser store) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${store.lat},${store.lng}');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // 端末に開けるアプリがない場合は何もしない（デモのため）
  }
}
