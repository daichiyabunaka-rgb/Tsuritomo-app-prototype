import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../models.dart';
import 'community_detail_screen.dart';

/// コミュニティ作成シート（誰でも作成可）。
/// ビジネスユーザーは自分の店舗のファンコミュニティとして作れる。
Future<void> showCommunityCreateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CommunityCreateSheet(),
  );
}

class _CommunityCreateSheet extends StatefulWidget {
  const _CommunityCreateSheet();

  @override
  State<_CommunityCreateSheet> createState() => _CommunityCreateSheetState();
}

class _CommunityCreateSheetState extends State<_CommunityCreateSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _isFanOfMyStore = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final me = appState.me!;
    final isBusiness = me.isBusiness;
    _isFanOfMyStore = isBusiness;
    _name = TextEditingController(
        text: isBusiness && me is BusinessUser
            ? '${me.nickname}のファン会'
            : '');
    _description = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _isBusiness => appState.me!.isBusiness;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final community = await appState.createCommunity(
        name: name,
        description: _description.text.trim(),
        linkedStore: _isBusiness && _isFanOfMyStore
            ? appState.me!.nickname
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CommunityDetailScreen(communityId: community.id),
        ),
      );
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
            Text('コミュニティを作る',
                style: theme.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'クラブ・グループ・店舗のファンコミュニティなど、'
              '好きなテーマで作成できます。作成者は自動で参加します。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'コミュニティ名',
                hintText: '例: 堤防釣り部 / わだつみ常連会',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: '説明',
                hintText: '何をするコミュニティか、どんな人に来てほしいか',
                border: OutlineInputBorder(),
              ),
            ),
            if (_isBusiness) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('自分の店舗のファンコミュニティにする'),
                subtitle: const Text('店舗シートからもリンクされます'),
                value: _isFanOfMyStore,
                onChanged: (v) => setState(() => _isFanOfMyStore = v),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _create,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('作成する'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
