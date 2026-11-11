import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../services/app_config.dart';
import '../services/app_state.dart';
import '../services/supabase_data.dart';
import 'widgets.dart';

/// グループチャット（FR-3-3, FR-3-5）。プロトタイプでは絵文字スタンプのみ。
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Timer? _ticker;
  dynamic _realtimeChannel; // Supabase モードでのリアルタイム受信
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    appState.markRoomRead(widget.roomId);
    // Supabase モード: 既存メッセージ取得 + リアルタイム受信
    unawaited(appState.reloadRoomMessages(widget.roomId));
    if (AppConfig.useSupabase) {
      _realtimeChannel = supabaseData.subscribeRoomMessages(
        roomId: widget.roomId,
        onMessage: (message) {
          appState.handleIncomingMessage(widget.roomId, message);
          // 開いている間は未読にしない
          appState.markRoomRead(widget.roomId);
        },
      );
    }
    _ticker = Timer.periodic(Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      // 5回に1回（5秒ごと）実データを引き直す（リアルタイム未接続時の保険）
      _tick++;
      if (_tick % 20 == 0) {
        unawaited(appState.reloadRoomMessages(widget.roomId));
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(
            _realtimeChannel as RealtimeChannel);
      } catch (_) {
        // アプリ終了時などは無視
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = appState.roomById(widget.roomId);
    if (room == null) {
      return const Scaffold(body: Center(child: Text('部屋が見つかりません')));
    }
    // 募集ベースのグループ部屋には募集が必須。DM・コミュニティ部屋は不要
    final rec = room.recruitmentId.isEmpty
        ? null
        : appState.recruitmentById(room.recruitmentId);
    if (room.type == 'group' && rec == null) {
      return const Scaffold(body: Center(child: Text('部屋が見つかりません')));
    }
    final theme = Theme.of(context);
    final String title;
    final String subtitle;
    if (room.isDm) {
      final other = appState.userById(
          room.memberIds.firstWhere((id) => id != appState.me!.id));
      title = other.nickname;
      subtitle = 'DM（1:1）';
    } else if (room.isCommunity) {
      final community = appState.communityById(room.communityId ?? '');
      title = community?.name ?? 'コミュニティ';
      subtitle = 'コミュニティ（${room.memberIds.length}人）';
    } else {
      title = rec!.title;
      subtitle = '${room.memberIds.length}人の部屋 / 待: ${rec.meetup}';
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall!
                    .copyWith(fontWeight: FontWeight.bold)),
            Text(subtitle, style: theme.textTheme.labelSmall),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in room.memberIds)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: tappableAvatar(context, m, size: 28),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final messages = appState.messagesOf(widget.roomId);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return _MessageTile(message: m);
                  },
                );
              },
            ),
          ),
          _ChatInput(roomId: widget.roomId),
        ],
      ),
    );
  }
}

class _ChatInput extends StatefulWidget {
  const _ChatInput({required this.roomId});

  final String roomId;

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    appState.sendMessage(widget.roomId, text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // ナビゲーションバー・ジェスチャーバーとの誤タッチを防ぐ
      minimum: const EdgeInsets.only(bottom: 4),
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'メッセージ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.body,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ),
        ),
      );
    }
    final isMine = message.senderId == appState.me!.id;
    final sender = appState.userById(message.senderId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            tappableAvatar(context, sender.id, size: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMine)
                  Text(sender.nickname,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMine
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message.body,
                    style: TextStyle(
                        color: isMine
                            ? Theme.of(context).colorScheme.onPrimary
                            : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          if (isMine) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
