import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import 'widgets.dart';
import 'chat_screen.dart';

/// 「部屋」タブ: 自分が参加している募集のグループチャットとDM一覧（FR-3-3）
class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Supabase モード: 20秒ごとに実データを引き直して着信を反映
    _ticker = Timer.periodic(
        const Duration(seconds: 20), (_) => appState.refreshFromRemote());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final rooms = appState.myRooms;
            if (rooms.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'まだ部屋がありません。\n'
                    '「近く」で募集に応募するか、自分で募集をかけて、\n'
                    '参加者が集まると部屋ができます。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rooms.length,
              itemBuilder: (context, i) {
                final room = rooms[i];
                late final String title;
                late final String leadingId;
                if (room.isDm) {
                  final otherId = room.memberIds
                      .firstWhere((id) => id != appState.me!.id);
                  leadingId = otherId;
                  title =
                      '${appState.userById(otherId).nickname}（DM）';
                } else if (room.isCommunity) {
                  final community =
                      appState.communityById(room.communityId ?? '');
                  leadingId = community?.ownerId ?? room.memberIds.first;
                  title = community?.name ?? 'コミュニティ';
                } else {
                  final rec = appState.recruitmentById(room.recruitmentId)!;
                  leadingId = rec.hostId;
                  title = rec.title;
                }
                final last = appState.lastMessageOf(room.id);
                final unread = appState.unreadByRoom[room.id] ?? 0;
                return ListTile(
                  leading: tappableAvatar(context, leadingId, size: 48),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    last.isEmpty ? '参加が決まるとメッセージが始まります' : last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: unread > 0
                      ? Badge(
                          label: Text('$unread'),
                        )
                      : Text(
                          '${room.memberIds.length}人',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatScreen(roomId: room.id),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
