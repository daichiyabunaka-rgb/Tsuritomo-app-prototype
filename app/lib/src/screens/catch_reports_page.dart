import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../util/format.dart';
import 'catch_report_create_sheet.dart';
import 'chat_screen.dart';
import 'user_detail_screen.dart';
import 'widgets.dart';

/// 「釣果速報」タブ: 海・川・湖での釣果を近隣で共有する（FR-7-1〜7-4）。
/// 釣れた魚・状況を投稿して近くの釣り人とつながる。掲載終了は登録者が管理。
/// 遊漁ルールの遵守・釣り禁止区域の確認を常に案内する設計。
class CatchReportsPage extends StatefulWidget {
  const CatchReportsPage({super.key});

  @override
  State<CatchReportsPage> createState() => _CatchReportsPageState();
}

class _CatchReportsPageState extends State<CatchReportsPage> {
  String _filter = 'all'; // 'all' | 'sea' | 'fresh'

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCatchReportCreateSheet(context),
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('釣果を登録する'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final all = appState.catchReports;
            final reports = _filter == 'all'
                ? all
                : all
                      .where(
                        (r) =>
                            _filter == 'sea' ? r.isSea : r.isFresh,
                      )
                      .toList();
            return RefreshIndicator(
              onRefresh: () => appState.refreshFromRemote(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '釣果速報',
                    style: theme.textTheme.titleLarge!.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('すべて')),
                      ButtonSegment(
                          value: 'sea', label: Text('海')),
                      ButtonSegment(
                          value: 'fresh', label: Text('川・湖')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '近くで登録された釣果を近い順に表示します。'
                    '釣れた魚・釣り場の状況を投稿して、'
                    '近くの釣り仲間とつながりましょう。',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '※遊漁券・釣り禁止区域は現地の看板や自治体の'
                    '漁業調整規則をご確認ください。'
                    'サイズ制限・リリース規制も守って釣行をお願いします。',
                    style: theme.textTheme.labelSmall!.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (reports.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          '近くに釣果登録はまだありません。\n'
                          '「釣果を登録する」から最初の投稿をお願いします。',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  for (final r in reports) _reportCard(context, r),
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _reportCard(BuildContext context, CatchReport r) {
    final theme = Theme.of(context);
    final reporter = appState.userById(r.reporterId);
    final isMine = r.reporterId == appState.me!.id;
    final now = DateTime.now();
    final seaColor = Colors.teal.shade700;
    final freshColor = Colors.lightBlue.shade700;
    final color = r.isSea ? seaColor : freshColor;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: r.isSea
                        ? Colors.teal.shade50
                        : Colors.lightBlue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: r.isSea
                          ? Colors.teal.shade200
                          : Colors.lightBlue.shade200,
                    ),
                  ),
                  child: Text(
                    r.isSea ? '海' : '川・湖',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.fishDescription,
                    style: theme.textTheme.titleSmall!.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.place, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    r.areaName,
                    style: TextStyle(color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 2),
                Text(
                  '${elapsedLabel(r.createdAt, now)}の登録 / '
                  '${appState.catchReportDistanceLabel(r)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_hasPhoto(r))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onTap: () => _showPhoto(context, r),
                    child: _photoImage(r, 320),
                  ),
                ),
              ),
            if (r.detail.isNotEmpty)
              Text(r.detail, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UserDetailScreen(userId: reporter.id),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      userAvatar(reporter.id, size: 32),
                      const SizedBox(width: 8),
                      Text(
                        reporter.nickname,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isMine)
                  TextButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('掲載終了にする'),
                    onPressed: () => _confirmClose(context, r),
                  )
                else
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('この人にDM', style: TextStyle(fontSize: 13)),
                    onPressed: () async {
                      final room = await appState.getOrCreateDm(reporter.id);
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatScreen(roomId: room.id),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _hasPhoto(CatchReport r) {
    final p = r.photoPath ?? '';
    if (p.isEmpty) return false;
    if (p.startsWith('http')) return true;
    return File(p).existsSync();
  }

  Widget _photoImage(CatchReport r, double height) {
    final p = r.photoPath!;
    final Widget image;
    if (p.startsWith('http')) {
      image = Image.network(p,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink());
    } else {
      image = Image.file(File(p),
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink());
    }
    return image;
  }

  /// 写真を全画面で見る
  void _showPhoto(BuildContext context, CatchReport r) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.of(dialogContext).pop(),
          child: _photoImage(r, 480),
        ),
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context, CatchReport r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('掲載終了にしますか？'),
        content: const Text(
          '釣行が終わった、情報が古くなった等、共有を終える場合に設定します。'
          '掲載終了の登録は一覧から表示されなくなります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('掲載終了にする'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await appState.closeCatchReport(r.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('掲載終了にしました。一覧から削除されます'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
