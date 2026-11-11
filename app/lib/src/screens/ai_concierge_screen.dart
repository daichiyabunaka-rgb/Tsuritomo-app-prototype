import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/ai_concierge.dart';
import '../services/app_state.dart';

class _ChatEntry {
  final String body;
  final bool isAi;
  _ChatEntry(this.body, this.isAi);
}

/// AI接客チャット（ビジネスユーザー向け有料機能のデモ）。
/// プロトタイプではルールベースのモック応答。本開発では LLM API を使い、
/// ビジネスユーザーは店舗情報を登録するだけで接客・営業文作成を任せられる。
class AiConciergeScreen extends StatefulWidget {
  const AiConciergeScreen({super.key, required this.storeId});

  final String storeId;

  @override
  State<AiConciergeScreen> createState() => _AiConciergeScreenState();
}

class _AiConciergeScreenState extends State<AiConciergeScreen> {
  final _input = TextEditingController();
  final List<_ChatEntry> _entries = [];
  bool _aiTyping = false;

  @override
  void initState() {
    super.initState();
    final store = appState.userById(widget.storeId) as BusinessUser;
    _entries.add(_ChatEntry(aiConcierge.greeting(appState.me!, store), true));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _aiTyping) return;
    setState(() {
      _entries.add(_ChatEntry(text, false));
      _aiTyping = true;
    });
    _input.clear();
    // デモ: 入力中の演出つきでモック AI が返す（本開発は LLM API 呼び出し）
    Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final store = appState.userById(widget.storeId) as BusinessUser;
      setState(() {
        _entries.add(_ChatEntry(aiConcierge.reply(text, appState.me!, store), true));
        _aiTyping = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = appState.userById(widget.storeId) as BusinessUser;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.nickname,
                style:
                    theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.bold)),
            Text('AI接客（ベータ期間中は無料）',
                style: theme.textTheme.labelSmall),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _entries.length + (_aiTyping ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= _entries.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('…入力中'),
                      ),
                    );
                  }
                  final e = _entries[i];
                  return Align(
                    alignment: e.isAi
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: e.isAi
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        e.body,
                        style: TextStyle(
                          color: e.isAi
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final q in const ['おすすめは？', '席は空いてる？', '営業時間は？', '予約したい'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: Icon(Icons.bolt, size: 16,
                            color: theme.colorScheme.primary),
                        label: Text(q),
                        onPressed: () => _send(q),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'AI接客に質問する',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _aiTyping ? null : () => _send(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
