import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_state.dart';
import '../services/icon_service.dart';

/// 近況報告の登録シート（FR-7-1）。
/// kind: 'catch'（釣果）/ 'post'（つぶやき）/ 'event'（イベント）/ 'art'（絵）
Future<void> showCatchReportCreateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateSheet(),
  );
}

class _CreateSheet extends StatefulWidget {
  const _CreateSheet();

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _fishDescription = TextEditingController();
  final _areaName = TextEditingController();
  final _detail = TextEditingController();
  String _kind = 'catch';
  String? _photoPath; // 選択した投稿写真（null=未選択, ''=解除）
  bool _submitting = false;

  @override
  void dispose() {
    _fishDescription.dispose();
    _areaName.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final path = await iconService.pickCatchReportPhoto(source);
    if (path != null) {
      setState(() => _photoPath = path);
    }
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    try {
      await appState.registerCatchReport(
        kind: _kind,
        fishDescription: _fishDescription.text.trim(),
        areaName: _areaName.text.trim(),
        detail: _detail.text.trim(),
        photoPath:
            (_photoPath == null || _photoPath!.isEmpty) ? null : _photoPath,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('報告に失敗しました。通信状況を確認してください'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('報告しました。近くのユーザーに表示されます'),
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
            Text('近況報告を投稿する',
                style: theme.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'catch',
                  icon: Icon(Icons.phishing),
                  label: Text('釣果'),
                ),
                ButtonSegment(
                  value: 'post',
                  icon: Icon(Icons.chat_bubble_outline),
                  label: Text('つぶやき'),
                ),
                ButtonSegment(
                  value: 'event',
                  icon: Icon(Icons.celebration),
                  label: Text('イベント'),
                ),
                ButtonSegment(
                  value: 'art',
                  icon: Icon(Icons.palette),
                  label: Text('絵'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              _kind == 'catch'
                  ? '釣った魚・釣り場の状況の報告です。\n'
                      '※遊漁券・釣り禁止区域は現地の看板や漁業調整規則をご確認ください。'
                      '写真は釣果・風景の写るものを（本人の顔画像は不可）。'
                  : _kind == 'post'
                      ? '近況・ひとことのつぶやきです。\n'
                          '※釣行の予定や装備の準備など、釣り仲間に伝えたい近況を報告しましょう。'
                      : _kind == 'event'
                          ? '釣りイベント・オフ会の報告です。\n'
                              '※主催者・参加者のルールと許諾を守ってください。'
                          : '描いた絵・イラストの投稿です。\n'
                              '※他人の作品の無断転載・トレースは禁止です。'
                              '成人向けの画像も投稿できません。',
              style: theme.textTheme.labelSmall!
                  .copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fishDescription,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: _kind == 'art' ? 'タイトル（描いた絵の内容など）' : '魚種・釣り方・サイズ',
                hintText: _kind == 'art'
                    ? '例: 魚の水彩画を描いてみました'
                    : '例: アジ（20〜25cm・サビキ）',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),

            // ------------------------------ 投稿写真（任意）
            Text('写真（任意。報告の画像を）',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                _photoPreview(theme),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 18),
                        label: const Text('ギャラリーから',
                            style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () => _pickPhoto(ImageSource.camera),
                        icon:
                            const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('カメラで撮影',
                            style: TextStyle(fontSize: 13)),
                      ),
                      if (_photoPath != null && _photoPath!.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _photoPath = ''),
                          child: const Text('写真をはずす',
                              style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _areaName,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: _kind == 'art' ? '地域・釣り場名（絵は任意）' : '釣り場・ポイント',
                hintText: '例: 青海堤防 第二折り',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detail,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '状況・タックル情報など',
                hintText: '例: 早朝に回遊あり。カラシマサビキが効きました。周辺にいる方ぜひ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_isValid && !_submitting) ? _submit : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('報告する'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isValid =>
      _fishDescription.text.trim().isNotEmpty &&
      (_kind == 'art' || _areaName.text.trim().isNotEmpty);

  Widget _photoPreview(ThemeData theme) {
    final path = (_photoPath ?? '');
    Widget preview;
    if (path.startsWith('http')) {
      preview = Image.network(path, width: 96, height: 96,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => _emptyPreview());
    } else if (path.isNotEmpty && File(path).existsSync()) {
      preview =
          Image.file(File(path), width: 96, height: 96, fit: BoxFit.cover);
    } else {
      preview = _emptyPreview();
    }
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: preview,
      ),
    );
  }

  Widget _emptyPreview() {
    return Container(
      color: Colors.grey.shade100,
      child: const Center(
        child: Icon(Icons.image_outlined, size: 32, color: Colors.grey),
      ),
    );
  }
}
