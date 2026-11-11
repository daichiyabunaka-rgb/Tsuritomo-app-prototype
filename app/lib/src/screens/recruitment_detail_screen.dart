import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../util/format.dart';
import '../util/share_text.dart';
import 'widgets.dart';

/// 募集詳細。
/// - 自分の募集: 応募の承認 / 却下（FR-3-2）
/// - 他人の募集: 応募（FR-3-1）
class RecruitmentDetailScreen extends StatefulWidget {
  const RecruitmentDetailScreen({super.key, required this.recruitmentId});

  final String recruitmentId;

  @override
  State<RecruitmentDetailScreen> createState() =>
      _RecruitmentDetailScreenState();
}

class _RecruitmentDetailScreenState extends State<RecruitmentDetailScreen> {
  Timer? _ticker;
  final TextEditingController _applyMessage = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
        const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _applyMessage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rec = appState.recruitmentById(widget.recruitmentId);
    if (rec == null) {
      return const Scaffold(body: Center(child: Text('この募集は終了しました')));
    }
    final now = DateTime.now();
    final theme = Theme.of(context);
    final isMine = rec.hostId == appState.me!.id;
    final host = appState.userById(rec.hostId);
    final myApp = appState.myPendingApplication(rec.id);
    final active = rec.isActiveAt(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('募集の詳細'),
        actions: [
          IconButton(
            tooltip: 'この募集を共有',
            icon: const Icon(Icons.share),
            onPressed: () async {
              try {
                await SharePlus.instance.share(
                  ShareParams(
                    title: '釣りとも！',
                    text: recruitmentShareText(rec.title, rec.meetup),
                  ),
                );
              } catch (_) {
                // 共有シートを開けない環境では無視する
              }
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final bodyRec = appState.recruitmentById(widget.recruitmentId)!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          tappableAvatar(context, host.id, size: 56, iconScale: 0.45),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  host.nickname,
                                  style: theme.textTheme.titleMedium!
                                      .copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${host.decade} / ${host.genderLabel}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isMine
                                    ? 'あなたの募集'
                                    : appState.recruitmentDistanceLabel(bodyRec),
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                remainingLabel(bodyRec.expiresAt, DateTime.now()),
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final id in host.interestIds)
                            interestLabel(appState.categoryOf(id)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(host.bio, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          genreChip(bodyRec.genreId),
                          const SizedBox(width: 8),
                          Icon(Icons.group, size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text(
                            '${bodyRec.memberIds.length}/${bodyRec.capacity}人',
                            style: TextStyle(color: Colors.grey.shade800),
                          ),
                          const Spacer(),
                          Icon(Icons.place, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              bodyRec.meetup,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        bodyRec.title,
                        style: theme.textTheme.titleLarge!
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(bodyRec.body),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: -8,
                        children: [
                          for (final m in bodyRec.memberIds)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: tappableAvatar(context, m, size: 36),
                            ),
                          if (bodyRec.remainingSlots > 0)
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.grey.shade200,
                              child: Text(
                                '+${bodyRec.remainingSlots}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade700),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isMine) ..._hostManagingAppSection(bodyRec),
            ],
          );
        },
      ),
      bottomSheet: (!isMine && active && myApp == null)
          ? SafeArea(
              child: Container(
                color: theme.scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                width: double.infinity,
                child: FilledButton(
                  onPressed: _showApplyDialog,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('参加したい'),
                  ),
                ),
              ),
            )
          : (!isMine && myApp != null)
              ? SafeArea(
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: null,
                      child: const Text('承認待ちです'),
                    ),
                  ),
                )
          : null,
    );
  }

  void _showApplyDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('参加の一声'),
        content: TextField(
          controller: _applyMessage,
          maxLength: 140,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '例: 近くにいるので今からでも行けます！',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              appState.applyTo(widget.recruitmentId,
                  message: _applyMessage.text.trim());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('応募しました。ホストの承認をお待ちください'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('応募する'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- manage

  List<Widget> _hostManagingAppSection(Recruitment rec) {
    final apps = appState.applicationsFor(rec.id);
    final theme = Theme.of(context);
    if (apps.isEmpty) {
      return [
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.hourglass_top, color: Colors.grey.shade500),
                const SizedBox(height: 8),
                Text('応募はまだありません',
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      const SizedBox(height: 16),
      Text('応募（${apps.length}件）',
          style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final app in apps)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _applicationTile(app, rec),
          ),
        ),
    ];
  }

  Widget _applicationTile(JoinApplication app, Recruitment rec) {
    final applicant = appState.userById(app.applicantId);
    final isPending = app.status == JoinStatus.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            tappableAvatar(context, applicant.id, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(applicant.nickname,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${applicant.decade} / ${applicant.genderLabel}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(_statusLabel(app.status)),
          ],
        ),
        if (app.message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(app.message,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
        if (isPending && !rec.isFull) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => appState.declineApplication(app.id),
                  child: const Text('見送る'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    appState.acceptApplication(app.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${applicant.nickname} さんを承認しました。'
                            'グループチャットができました'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('承認する'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _statusLabel(JoinStatus s) {
    switch (s) {
      case JoinStatus.pending:
        return '承認待ち';
      case JoinStatus.accepted:
        return '承認済み';
      case JoinStatus.declined:
        return '見送り';
    }
  }
}
