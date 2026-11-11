import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../util/share_text.dart';

class _InviteOption {
  final String title;
  final String description;
  final String text;
  const _InviteOption(this.title, this.description, this.text);
}

/// 招待シート。
/// - 全ユーザー: お客さま/友達を招待（「一緒に使いませんか？」）
/// - ビジネスユーザー: 同業者のお店を紹介・招待（ビジネス同士のつながり）
/// いずれも SNS 共有（OSの共有シート）とテキストコピーに対応。
Future<void> showInviteSheet(BuildContext context) {
  final me = appState.me!;
  final options = <_InviteOption>[
    _InviteOption(
      me.isBusiness ? 'お客さまを招待する' : '友達を招待する',
      'SNSで「一緒に使いませんか？」を送る',
      inviteText(me.nickname),
    ),
    if (me.isBusiness)
      _InviteOption(
        '同業者のお店を紹介する',
        '近くの釣具店・釣り業界仲間に「釣りとも！」を勧める',
        businessInviteText(
            me.nickname, (me as BusinessUser).storeType),
      ),
  ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '招待・紹介',
            style: Theme.of(sheetContext)
                .textTheme
                .titleLarge!
                .copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'LINE / X / Instagram など、お使いの SNS やメッセージアプリから'
            '招待状を送れます。',
            style: Theme.of(sheetContext).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final option in options) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(option.description,
                        style: Theme.of(sheetContext).textTheme.bodySmall),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        option.text,
                        style: const TextStyle(height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.ios_share),
                            label: const Text('共有'),
                            onPressed: () async {
                              Navigator.of(sheetContext).pop();
                              try {
                                await SharePlus.instance.share(
                                  ShareParams(
                                    title: '釣りとも！',
                                    text: option.text,
                                  ),
                                );
                              } catch (_) {
                                // 共有シートを開けない端末では無視
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy),
                            label: const Text('コピー'),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: option.text));
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('招待文をコピーしました'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'ベータ期間中は、ビジネスユーザー・一般ユーザーともに'
            'すべての機能が無料でご利用いただけます。'
            '本リリース後、招待コード（?ref=）による招待者との自動接続を追加予定です。',
            style: Theme.of(sheetContext).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
