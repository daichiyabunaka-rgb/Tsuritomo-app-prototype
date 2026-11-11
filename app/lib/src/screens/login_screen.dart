import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'profile_setup_screen.dart';

/// ログイン画面（メール認証）。セッションがあれば起動時に自動ログインされる。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await authService.login(_email.text, _password.text);
      await _attachSessionUser();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = '通信エラーが発生しました');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachSessionUser() async {
    final gps = await locationService.currentPosition();
    final user = await authService.buildSessionUser(
      lat: gps?.$1 ?? appState.anchorLat,
      lng: gps?.$2 ?? appState.anchorLng,
    );
    if (user == null) return;
    if (gps != null) {
      appState.applyGps(gps.$1, gps.$2);
      appState.attachUser(user, reseed: true);
    } else {
      appState.attachUser(user, reseed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.set_meal,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('釣りとも！',
                    style: theme.textTheme.headlineLarge!
                        .copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('趣味でつながる。顔ではなく中身で。',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(
                    labelText: 'パスワード',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _login,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('ログイン'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RegisterScreen(),
                    ),
                  ),
                  child: const Text('はじめての方は会員登録へ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 会員登録（ステップ1: 登録種別 / メール / パスワード / 同意）
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _agreedAge = false;
  bool _agreedRule = false;
  String _role = 'general';
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _email.text.contains('@') &&
      _password.text.length >= 6 &&
      _agreedAge &&
      _agreedRule;

  void _next() {
    if (!_isValid) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileSetupScreen(
          registrationEmail: _email.text.trim(),
          registrationPassword: _password.text,
          registrationRole: _role,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('会員登録')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('登録種別', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'general',
                icon: Icon(Icons.person_outline),
                label: Text('一般ユーザー'),
              ),
              ButtonSegment(
                value: 'business',
                icon: Icon(Icons.storefront_outlined),
                label: Text('ビジネスユーザー'),
              ),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _role == 'business'
                ? '釣具店・乗り合い船など店舗情報を登録し、地図連携・DM・電話対応を利用します'
                  '（AI接客は本リリース後に提供予定）。ベータ期間中は無料です'
                : '近くの釣り仲間を探します。完全無料です',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'メールアドレス',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'パスワード（6文字以上）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _agreedAge,
            onChanged: (v) => setState(() => _agreedAge = v ?? false),
            title: const Text('18歳以上です（v1 は18歳以上限定です）'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _agreedRule,
            onChanged: (v) => setState(() => _agreedRule = v ?? false),
            title: const Text(
                '恋愛・異性交際を目的とした利用は禁止であることに同意します'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isValid ? _next : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('プロフィール入力へ'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
