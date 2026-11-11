import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';

/// 募集作成（FR-2-1）: ジャンル / タイトル / 本文 / 定員 / 期限 / 待ち合わせ
/// [initialMeetup] に釣り場名などを渡すと待ち合わせの初期値になる。
Future<void> showRecruitmentCreateSheet(BuildContext context,
    {String? initialMeetup}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CreateSheet(initialMeetup: initialMeetup),
  );
}

class _CreateSheet extends StatefulWidget {
  const _CreateSheet({this.initialMeetup});

  final String? initialMeetup;

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _meetup;
  late String _genreId;
  int _capacity = 3;
  int _expiryHours = 2;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _body = TextEditingController();
    _meetup = TextEditingController(text: widget.initialMeetup ?? '');
    _genreId = 'shore';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _meetup.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _title.text.trim().isNotEmpty && _meetup.text.trim().isNotEmpty;

  Future<void> _post() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    try {
      await appState.createRecruitment(
        genreId: _genreId,
        title: _title.text.trim(),
        body: _body.text.trim(),
        meetup: _meetup.text.trim(),
        capacity: _capacity,
        expiryHours: _expiryHours,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('募集の作成に失敗しました。通信状況を確認してください'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('募集をかけました（$_expiryHours時間で自動消滅）'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('募集をかける',
                style: theme.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '期限が来ると自動で消えます。近くの人に表示されます。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('ジャンル', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                for (final g in genres)
                  ButtonSegment(value: g.id, label: Text(g.label), icon: Icon(g.icon)),
              ],
              selected: {_genreId},
              onSelectionChanged: (s) => setState(() => _genreId = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                hintText: '例: 今から堤防でサビキしませんか',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '内容',
                hintText: '釣り方・対象魚、初心者歓迎、タックルの有無など',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _meetup,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '待ち合わせ',
                hintText: '例: 神田駅 北口',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('定員（自分を含む）', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 2, label: Text('2人')),
                          ButtonSegment(value: 3, label: Text('3人')),
                          ButtonSegment(value: 4, label: Text('4人')),
                          ButtonSegment(value: 6, label: Text('6人')),
                        ],
                        selected: {_capacity},
                        onSelectionChanged: (s) => setState(() => _capacity = s.first),
                        showSelectedIcon: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('期限', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1時間')),
                ButtonSegment(value: 2, label: Text('2時間')),
                ButtonSegment(value: 3, label: Text('3時間')),
              ],
              selected: {_expiryHours},
              onSelectionChanged: (s) => setState(() => _expiryHours = s.first),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_isValid && !_submitting) ? _post : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('募集する'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
