import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import 'chat_screen.dart';
import 'event_create_sheet.dart' as event_sheet;
import 'widgets.dart';

/// コミュニティ詳細: 参加/脱退、コミュニティチャット、イベント・クラブの企画と参加。
/// 利用規約上いずれも趣味の交流を目的とする（恋愛目的の利用は禁止）。
class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({super.key, required this.communityId});

  final String communityId;

  @override
  State<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
        const Duration(seconds: 15), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final c = appState.communityById(widget.communityId);
        if (c == null) {
          return const Scaffold(
              body: Center(child: Text('コミュニティが見つかりません')));
        }
        final me = appState.me!;
        final isMember = c.memberIds.contains(me.id);
        final events = appState.eventsOf(c.id);
        return Scaffold(
          appBar: AppBar(title: Text(c.name)),
          body: ListView(
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
                          tappableAvatar(context, c.ownerId, size: 52),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.linkedStore != null
                                      ? '${c.linkedStore}のファンコミュニティ'
                                      : 'コミュニティ',
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  '主催: ${appState.userById(c.ownerId).nickname}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Text('${c.memberIds.length}人'),
                        ],
                      ),
                      if (c.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(c.description,
                            style: theme.textTheme.bodySmall),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: -8,
                        children: [
                          for (final m in c.memberIds.take(12))
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: 4),
                              child: tappableAvatar(context, m, size: 32),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: isMember
                                ? OutlinedButton.icon(
                                    icon: const Icon(Icons.logout),
                                    label: const Text('脱退する'),
                                    onPressed: () async {
                                      await appState.leaveCommunity(c.id);
                                    },
                                  )
                                : FilledButton.icon(
                                    icon: const Icon(Icons.group_add),
                                    label: const Text('参加する'),
                                    onPressed: () async {
                                      await appState.joinCommunity(c.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content:
                                                Text('参加しました。チャットが使えます'),
                                            behavior: SnackBarBehavior
                                                .floating,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.forum_outlined),
                              label: const Text('チャット'),
                              onPressed: isMember
                                  ? () => _openChat(c)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('イベント・クラブ（${events.length}）',
                        style: theme.textTheme.titleSmall),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('企画する'),
                    onPressed: isMember
                        ? () => event_sheet.showEventCreateSheet(
                            context, c.id)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (events.isEmpty)
                Text(
                  'まだイベントがありません。参加者なら誰でも企画できます。',
                  style: theme.textTheme.bodySmall,
                ),
              for (final e in events)
                _eventCard(context, e, isMember),
            ],
          ),
        );
      },
    );
  }

  void _openChat(Community c) {
    final room = appState.myRooms.firstWhere(
      (r) => r.communityId == c.id,
      orElse: () => throw StateError('room missing'),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(roomId: room.id),
      ),
    );
  }

  Widget _eventCard(BuildContext context, CommunityEvent e,
      bool isMember) {
    final theme = Theme.of(context);
    final me = appState.me!;
    final joined = e.participantIds.contains(me.id);
    final isHost = e.hostId == me.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    e.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${e.participantIds.length}/${e.capacity}人',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '日時: ${e.eventTime}  /  場所: ${e.locationName}',
              style: theme.textTheme.bodySmall,
            ),
            if (e.body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(e.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            if (isHost)
              const SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: null,
                  child: Text('あなたが主催しています'),
                ),
              )
            else if (joined)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: isMember
                      ? () async => await appState.leaveEvent(e.id)
                      : null,
                  child: const Text('参加を取消'),
                ),
              )
            else if (e.isFull)
              const SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: null,
                  child: Text('満員'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isMember
                      ? () async {
                          await appState.joinEvent(e.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('参加しました'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      : null,
                  child: const Text('参加する'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
