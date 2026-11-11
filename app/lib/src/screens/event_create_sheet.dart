import 'package:flutter/material.dart';

import '../services/app_state.dart';

/// イベント・クラブの企画シート（参加者なら誰でも作成できる）
Future<void> showEventCreateSheet(BuildContext context, String communityId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EventCreateSheet(communityId: communityId),
  );
}

class _EventCreateSheet extends StatefulWidget {
  const _EventCreateSheet({required this.communityId});

  final String communityId;

  @override
  State<_EventCreateSheet> createState() => _EventCreateSheetState();
}

class _EventCreateSheetState extends State<_EventCreateSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _time = TextEditingController();
  final _location = TextEditingController();
  int _capacity = 6;
  bool _submitting = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _time.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await appState.createEvent(
        communityId: widget.communityId,
        title: title,
        body: _body.text.trim(),
        eventTime: _time.text.trim(),
        locationName: _location.text.trim(),
        capacity: _capacity,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('作成に失敗しました。通信状況を確認してください'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('イベント・クラブを企画する',
                style: theme.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'コミュニティ参加者に向けて企画できます。'
              '釣行会・清掃活動・定例会など、気軽にどうぞ。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                hintText: '例: 第2回 堤防清掃と釣り会',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _time,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '日時（自由記述）',
                hintText: '例: 3/14（土）19:00〜',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '場所',
                hintText: '例: 駅北口集合',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 3,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: '内容',
                hintText: '例: 早朝の堤防で1時間。初心者歓迎',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('定員', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 4, label: Text('4人')),
                ButtonSegment(value: 6, label: Text('6人')),
                ButtonSegment(value: 10, label: Text('10人')),
                ButtonSegment(value: 20, label: Text('20人')),
              ],
              selected: {_capacity},
              onSelectionChanged: (s) => setState(() => _capacity = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _create,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('企画する'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
