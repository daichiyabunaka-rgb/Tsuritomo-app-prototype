import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/icon_service.dart';
import '../services/location_service.dart';

const List<String> decades = ['18〜19歳', '20代', '30代', '40代', '50代以上'];

/// プロフィール登録・編集（FR-1-2, FR-1-3, FR-4-1）
/// - 会員登録モード: registrationEmail / registrationPassword を渡す（メール認証付きで登録）
/// - 編集モード: existing を渡す
/// 顔写真は不可。アイコンは「アイコンセット」または投稿画像。
/// ビジネスユーザー（registrationRole='business'）は店舗情報も入力する。
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.existing,
    this.registrationEmail,
    this.registrationPassword,
    this.registrationRole = 'general',
  });

  final AppUser? existing;
  final String? registrationEmail;
  final String? registrationPassword;
  final String registrationRole;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

const List<String> storeTypes = [
  '釣具店', '乗り合い船・渡船', '釣り堀・管理釣り場', 'ボート・カヤックレンタル',
  'フィッシングカフェ・飲食', 'ロッド・リール修理工房', 'アウトドア・キャンプ用品店', 'その他',
];

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nickname;
  late final TextEditingController _bio;
  late final TextEditingController _website;
  late final TextEditingController _sns;
  late final TextEditingController _phone;
  late String _decade;
  late String _gender;
  late String _iconCategory;
  late String? _storeType;
  late final Set<String> _interests;
  // アイコン画像（投稿）。null=未選択（既定の趣味アイコンを使う）, ''=解除
  String? _iconImagePath;
  bool _submitting = false;

  bool get _isBusiness =>
      widget.registrationRole == 'business' ||
      (widget.existing?.isBusiness ?? false);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final b = e is BusinessUser ? e : null;
    _nickname = TextEditingController(
        text: e?.nickname ?? '');
    _bio = TextEditingController(text: e?.bio ?? '');
    _website = TextEditingController(text: e?.websiteUrl ?? '');
    _sns = TextEditingController(text: e?.snsNote ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _decade = _isBusiness ? '経営者' : (e?.decade ?? '20代');
    _gender = e?.gender ?? 'undisclosed';
    _iconCategory = e?.iconCategoryId ?? 'sabiki';
    _storeType = b?.storeType ?? '釣具店';
    _interests = <String>{...?e?.interestIds};
    _iconImagePath = (e?.iconImagePath?.isNotEmpty ?? false)
        ? e!.iconImagePath
        : null;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    _website.dispose();
    _sns.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _nickname.text.trim().isNotEmpty &&
      (_isBusiness || _interests.isNotEmpty) &&
      _iconCategory.isNotEmpty;

  Future<void> _pickImage(ImageSource source) async {
    final path = await iconService.pickAndSave(source);
    if (path != null) {
      setState(() => _iconImagePath = path);
    }
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final nickname = _nickname.text.trim();
    final bio = _bio.text.trim();
    final website =
        _website.text.trim().isEmpty ? null : _website.text.trim();
    final sns = _sns.text.trim().isEmpty ? null : _sns.text.trim();
    final phone =
        _phone.text.trim().isEmpty ? null : _phone.text.trim();
    final imagePath =
        (_iconImagePath == null || _iconImagePath!.isEmpty) ? null : _iconImagePath;

    if (widget.existing == null) {
      // 会員登録（この時点でアカウント作成 + 自動ログイン + 位置情報取得）
      try {
        final gps = await locationService.currentPosition();
        if (gps != null) {
          appState.applyGps(gps.$1, gps.$2);
        }
        await authService.register(
          email: widget.registrationEmail!,
          password: widget.registrationPassword!,
          nickname: nickname,
          decade: _isBusiness ? '経営者' : _decade,
          gender: _gender,
          iconCategoryId: _iconCategory,
          interestIds: _interests.toList(),
          bio: bio,
          iconImagePath: imagePath,
          role: widget.registrationRole,
          websiteUrl: website,
          snsNote: sns,
          phone: _isBusiness ? phone : null,
          storeType: _isBusiness ? _storeType : null,
        );
        final user = await authService.buildSessionUser(
          lat: gps?.$1 ?? appState.anchorLat,
          lng: gps?.$2 ?? appState.anchorLng,
        );
        if (user != null) {
          appState.attachUser(user, reseed: true);
        }
      } on AuthException catch (e) {
        if (mounted) {
          setState(() {
            _submitting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    } else {
      await authService.updateCurrentProfile(
        iconImagePath: _iconImagePath, // null=変更なし, ''=解除, パス=新画像
        websiteUrl: website,
        snsNote: sns,
        phone: phone,
        storeType: _isBusiness ? _storeType : null,
      );
      appState.updateProfile(
        nickname: nickname,
        decade: _decade,
        gender: _gender,
        iconCategoryId: _iconCategory,
        interestIds: _interests.toList(),
        bio: bio,
        iconImagePath: _iconImagePath,
        websiteUrl: website,
        snsNote: sns,
        phone: phone,
        storeType: _isBusiness ? _storeType : null,
      );
    }
    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'プロフィール編集' : 'プロフィール登録'),
        actions: [
          TextButton(
            onPressed: (_isValid && !_submitting) ? _submit : null,
            child: Text(isEdit ? '保存' : '登録'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              _isBusiness
                  ? 'ニックネーム（店舗名など、公開名）'
                  : 'ニックネーム',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _nickname,
            decoration: InputDecoration(
              hintText: _isBusiness ? '例: 釣具のうめき' : '例: サビキのテツ',
              border: const OutlineInputBorder(),
              counterText: '',
            ),
            maxLength: 20,
          ),
          if (_isBusiness) ...[
            Text('業態', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in storeTypes)
                  ChoiceChip(
                    label: Text(t),
                    selected: _storeType == t,
                    onSelected: (_) => setState(() => _storeType = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('電話番号（お店への問い合わせ用。タップで発信できるよう表示されます）',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '例: 03-1234-5678',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!_isBusiness) ...[
            Text('年代', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final d in decades)
                  ChoiceChip(
                    label: Text(d),
                    selected: _decade == d,
                    onSelected: (_) => setState(() => _decade = d),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('性別', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'male', label: Text('男性')),
                ButtonSegment(value: 'female', label: Text('女性')),
                ButtonSegment(value: 'undisclosed', label: Text('非公開')),
              ],
              selected: {_gender},
              onSelectionChanged: (s) => setState(() => _gender = s.first),
            ),
          ],
          const SizedBox(height: 16),
          Text('アイコン', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '釣果・タックル・釣り場の風景など、釣りに関係する画像を投稿できます。'
            'ご本人の顔が写った画像は使用できません'
            '（本開発では AI 審査で自動拒否します）。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _iconPreview(theme),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('ギャラリーから'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('カメラで撮影'),
                    ),
                    if (_iconImagePath != null &&
                        _iconImagePath!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            setState(() => _iconImagePath = ''),
                        child: const Text('画像をやめて趣味アイコンに戻す'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('画像がない場合の趣味アイコン', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: appState,
            builder: (context, _) => SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in appState.categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () =>
                                setState(() => _iconCategory = c.id),
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    theme.colorScheme.primaryContainer,
                                border: _iconCategory == c.id
                                    ? Border.all(
                                        color:
                                            theme.colorScheme.primary,
                                        width: 3,
                                      )
                                    : null,
                              ),
                              child: Icon(
                                c.icon,
                                size: 32,
                                color: theme
                                    .colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.label,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('興味カテゴリ（複数選択・自由に追加できます）',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: appState,
            builder: (context, _) => Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in appState.categories)
                  FilterChip(
                    avatar: Icon(c.icon, size: 18),
                    label: Text(c.label),
                    selected: _interests.contains(c.id),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _interests.add(c.id);
                      } else {
                        _interests.remove(c.id);
                      }
                    }),
                  ),
                ActionChip(
                  avatar: Icon(Icons.add,
                      size: 18, color: theme.colorScheme.primary),
                  label: Text('追加',
                      style: TextStyle(
                          color: theme.colorScheme.primary)),
                  onPressed: () => _showAddCategorySheet(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('自己紹介（釣りともステータス）', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '得意な釣り方・よく行く釣り場・やってみたい釣りなど。'
            '中身で選んでもらうための情報です。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bio,
            maxLines: 4,
            maxLength: 140,
            decoration: InputDecoration(
              hintText: _isBusiness
                  ? '例: リールのメンテナンスと仕掛けの相談ならお任せ。初心者セットのご用意もあります。'
                  : '例: 週末は近所の堤防でサビキ。アジとイワシの回遊を追う毎日。'
                    '初心者にも仕掛けのコツを教えます。',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('公開URL（SNSやホームページ）', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'プロフィールに表示され、タップで開きます。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _website,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sns,
            decoration: const InputDecoration(
              labelText: 'SNS',
              hintText: '例: X: @tsuritomo / IG: tsuritomo',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// カテゴリ追加シート: 名前 + アイコンを選んで新カテゴリを作る。
  /// シート本体は StatefulWidget（コントローラと選択状態をシートの
  /// State が持つ。builder 内で作り直すとキーボード開閉の再構築で
  /// 入力中のフォーカスと文章が消えるため）。
  Future<void> _showAddCategorySheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddCategorySheet(
        onCreated: (id) => setState(() => _interests.add(id)),
      ),
    );
  }

  Widget _iconPreview(ThemeData theme) {
    final cat = appState.categoryOf(_iconCategory);
    Widget preview;
    final path = _iconImagePath ?? '';
    if (path.startsWith('http')) {
      preview = ClipOval(
        child: Image.network(
          path,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Icon(cat.icon, size: 40, color: theme.colorScheme.primary),
        ),
      );
    } else if (path.isNotEmpty) {
      final f = File(path);
      preview = f.existsSync()
          ? ClipOval(
              child: Image.file(f, width: 88, height: 88, fit: BoxFit.cover))
          : Icon(cat.icon, size: 40, color: theme.colorScheme.primary);
    } else {
      preview = Icon(cat.icon, size: 40, color: theme.colorScheme.primary);
    }
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primaryContainer,
      ),
      child: Center(child: preview),
    );
  }
}

/// カテゴリ追加シート本体。コントローラ・選択中アイコンはここで保持する。
class _AddCategorySheet extends StatefulWidget {
  const _AddCategorySheet({required this.onCreated});

  final ValueChanged<String> onCreated;

  @override
  State<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<_AddCategorySheet> {
  final TextEditingController _name = TextEditingController();
  String _selectedIcon = 'fishing';
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final created = await appState.addCategory(
      label: _name.text,
      iconName: _selectedIcon,
    );
    if (!mounted) return;
    if (created != null) {
      widget.onCreated(created.id);
      Navigator.of(context).pop();
      return;
    }
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('同じ名前のカテゴリが既にあります'),
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
            Text('カテゴリを追加',
                style: theme.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                '釣りに関するカテゴリを自由に追加できます'
                '（追加したカテゴリは全ユーザーで共有されます）',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: 'カテゴリ名',
                hintText: '例: ワカサギ部 / 仕掛け自作 / 管釣りオフ会',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Text('アイコン', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in categoryIconChoices.entries)
                  InkWell(
                    onTap: () =>
                        setState(() => _selectedIcon = entry.key),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _selectedIcon == entry.key
                            ? theme.colorScheme.primaryContainer
                            : Colors.grey.shade200,
                        border: _selectedIcon == entry.key
                            ? Border.all(
                                color: theme.colorScheme.primary,
                                width: 3)
                            : null,
                      ),
                      child: Icon(entry.value, size: 24),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('追加する'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
