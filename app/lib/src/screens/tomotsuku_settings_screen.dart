import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_config.dart';
import '../services/app_state.dart';
import '../services/supabase_data.dart';

/// ともつく！連携設定。
/// 同一アカウントで使っている「ともつく！」シリーズ各アプリの
/// プロフィール一覧を表示し、アプリごとに「ともつく！全体に表示するか」
/// （他アプリの「近くの人」に見えるか）を切り替える。
/// このアプリ（釣りとも！）のプロフィールが無い場合は作成を案内する。
class TomoTskuSettingsScreen extends StatefulWidget {
  const TomoTskuSettingsScreen({super.key});

  @override
  State<TomoTskuSettingsScreen> createState() => _TomoTskuSettingsScreenState();
}

class _TomoTskuSettingsScreenState extends State<TomoTskuSettingsScreen> {
  late Future<List<({String appId, bool crossAppVisible, String nickname})>>
      _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!AppConfig.useSupabase) {
      _future = Future.value(const []);
    } else {
      _future = _load();
    }
  }

  Future<List<({String appId, bool crossAppVisible, String nickname})>>
      _load() async {
    final me = appState.me!;
    return supabaseData.fetchTomoTskuProfiles(me.id);
  }

  Future<void> _toggle(String appId, bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await supabaseData.setCrossAppVisible(appId, value);
      setState(() => _future = _load());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('設定の保存に失敗しました。通信状況をご確認ください'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ともつく！連携')),
      body: SafeArea(
        child: !AppConfig.useSupabase
            ? _mockNote(theme)
            : FutureBuilder<
                List<({String appId, bool crossAppVisible, String nickname})>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _errorCard(theme);
                  }
                  final profiles = snapshot.data ?? const [];
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '同じアカウントで使っているともつく！アプリ',
                        style: theme.textTheme.titleSmall!
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'メールアドレスが同じアカウントは、すべてのともつく！'
                        'アプリでそのままログインできます。',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      for (final p in profiles) _profileTile(theme, p),
                      if (profiles.isEmpty)
                        Text(
                          'プロフィールがありません。このアプリで会員登録を'
                          '完了すると、ここに表示されます。',
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'どこまで他ユーザーに見せるか',
                        style: theme.textTheme.titleSmall!
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'スイッチをONにしたアプリのプロフィールは、他のともつく！'
                        'アプリの「近くの人」「探す」にも、アプリ名のバッジ付きで'
                        '表示されます（例: 釣りとも！のプロフィールが犬とも！'
                        'ユーザーにも見える）。OFFの間はそのアプリ内だけで表示'
                        'されます。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _profileTile(
      ThemeData theme, ({String appId, bool crossAppVisible, String nickname}) p) {
    final isThisApp = p.appId == AppConfig.appId;
    final appName = tomoTskuAppNames[p.appId] ?? p.appId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              isThisApp ? Icons.set_meal : Icons.apps,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$appName${isThisApp ? '（このアプリ）' : ''}',
                    style: theme.textTheme.titleSmall!
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    p.nickname.isEmpty
                        ? '$appNameのプロフィール'
                        : '${p.nickname} として利用中',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Switch(
              value: p.crossAppVisible,
              onChanged: _busy ? null : (v) => _toggle(p.appId, v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text('設定を取得できませんでした。通信状況をご確認ください。',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('再読み込み'),
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
    );
  }

  Widget _mockNote(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'ともつく！連携',
          style:
              theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '現在この端末は端末内データ（モック）で動作しているため、'
          '連携設定は利用できません。本番のSupabaseに接続したビルドでは、\n'
          '・同じアカウントで使っているアプリの一覧\n'
          '・アプリごとの「ともつく！全体に表示」設定\n'
          'がここで管理できます。',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
