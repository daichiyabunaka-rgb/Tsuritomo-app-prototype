import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_state.dart';
import '../services/icon_service.dart';

/// 釣果速報の登録シート（FR-7-1）。
/// kind: 'sea'（海での釣果）/ 'fresh'（川・湖での釣果）
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
  String _kind = 'sea';
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
            content: Text('登録に失敗しました。通信状況を確認してください'),
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
        content: Text('登録しました。近くのユーザーに表示されます'),
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
            Text('釣果を登録する',
                style: theme.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'sea',
                  icon: Icon(Icons.waves),
                  label: Text('海'),
                ),
                ButtonSegment(
                  value: 'fresh',
                  icon: Icon(Icons.pool),
                  label: Text('川・湖'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              _kind == 'sea'
                  ? '海での釣果を共有します。近くの釣り人の参考になる情報として表示されます。\n'
                      '※遊漁券・釣り禁止区域は現地の看板や漁業調整規則をご確認ください。'
                      '写真は釣果・風景の写るものを（本人の顔画像は不可）。'
                  : '川・湖での釣果を共有します。\n'
                      '※外来魚のリリース禁止など、水域ごとのルールをご確認ください。'
                      '個人が特定できる情報は記入しないでください。',
              style: theme.textTheme.labelSmall!
                  .copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fishDescription,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: '魚種・釣り方・サイズ',
                hintText: '例: アジ（20〜25cm・サビキ）',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),

            // ------------------------------ 投稿写真（任意）
            Text('写真（任意。釣果が伝わる写真を）',
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
              decoration: const InputDecoration(
                labelText: '釣り場・ポイント',
                hintText: '例: 青海堤防 第二折り',
                border: OutlineInputBorder(),
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
                  child: Text('登録する'),
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
      _areaName.text.trim().isNotEmpty;

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
