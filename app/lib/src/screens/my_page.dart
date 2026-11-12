import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'invite_sheet.dart';
import 'tomotsuku_settings_screen.dart';
import 'widgets.dart';
import 'profile_setup_screen.dart';

/// 「マイページ」タブ: プロフィール、統計、設定（FR-4-x, FR-5-4 の受信設定）
class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final me = appState.me!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        userAvatar(me.id, size: 84, iconScale: 0.45),
                        const SizedBox(height: 12),
                        Text(me.nickname,
                            style: theme.textTheme.titleLarge!
                                .copyWith(fontWeight: FontWeight.bold)),
                        Text('${me.decade} / ${me.genderLabel}',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final id in me.interestIds)
                              interestLabel(appState.categoryOf(id)),
                          ],
                        ),
                        if (me.isBusiness && me is BusinessUser) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        'ビジネスユーザー / ${me.storeType}',
                        style:
                            TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                  if (me.phone?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.phone,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          me.phone!,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (me.snsNote?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.alternate_email,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            me.snsNote!,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (me.websiteUrl?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final raw = me.websiteUrl!;
                        final url = raw.startsWith('http://') ||
                                raw.startsWith('https://')
                            ? raw
                            : 'https://$raw';
                        try {
                          await launchUrl(Uri.parse(url),
                              mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              me.websiteUrl!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (me.bio.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            me.bio,
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ProfileSetupScreen(existing: me),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('プロフィールを編集'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statCard(context, '${appState.createdCount}', '募集した数'),
                    const SizedBox(width: 8),
                    _statCard(context, '${appState.joinedRoomsCount}', '参加した部屋'),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.people_alt_outlined,
                        color: theme.colorScheme.primary),
                    title: Text(me.isBusiness ? '招待・紹介する' : '友達を招待する'),
                    subtitle: const Text('SNSで「一緒に使いませんか？」を送る'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showInviteSheet(context),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.hub_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('ともつく！連携'),
                    subtitle:
                        const Text('使っているアプリと公開範囲の設定'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TomoTskuSettingsScreen(),
                      ),
                    ),
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.mail_outline),
                        title: const Text('メールアドレス'),
                        subtitle:
                            Text(authService.sessionEmail ?? '（不明）'),
                        trailing: const Icon(Icons.verified_user_outlined),
                      ),
                      ListTile(
                        leading: const Icon(Icons.near_me),
                        title: const Text('位置情報'),
                        subtitle: Text(appState.gpsAvailable
                            ? 'GPS取得済み（距離は粗いバンド表示のみ）'
                            : '未取得（フォールバックの中心地で表示）'),
                        trailing: TextButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('更新'),
                          onPressed: () async {
                            final gps =
                                await locationService.currentPosition();
                            if (gps == null) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '位置情報を取得できませんでした。'
                                        '端末の位置情報設定をご確認ください'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                              return;
                            }
                            appState.applyGps(gps.$1, gps.$2);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('現在地を更新しました'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications),
                        title: const Text('お知らせ通知'),
                        subtitle: const Text('自分の募集への応募・承認を通知'),
                        value: true,
                        onChanged: null, // v1 では固定 ON（本開発で設定反映）
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _blockedUsersCard(context),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('ログアウト'),
                    onPressed: () async {
                      await authService.logout();
                      appState.detach();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('アカウントを削除'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                    onPressed: () => _confirmDeleteAccount(context),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'プロトタイプについて: データは端末内のモックです（再起動でリセット）。'
                    '本開発では Supabase（Postgres + geohash / Realtime / Auth）を'
                    'バックエンドに構築し、18歳以上限定・顔アイコン禁止・'
                    '恋愛目的禁止のポリシーは規約とモデレーションで担保します。',
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: Colors.grey.shade600),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// ブロックしたユーザーの一覧（解除はここから。相手には通知されない）
  Widget _blockedUsersCard(BuildContext context) {
    final theme = Theme.of(context);
    final blocked = appState.blockedUserIds;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('ブロックしたユーザー',
                style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'ブロックした人のプロフィール・募集・部屋は非表示になります。'
              'ブロックしたことは相手には通知されません。',
              style: theme.textTheme.bodySmall!
                  .copyWith(color: Colors.grey.shade600),
            ),
          ),
          if (blocked.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'ブロック中のユーザーはいません',
                style: theme.textTheme.bodySmall!
                    .copyWith(color: Colors.grey.shade500),
              ),
            )
          else
            for (final id in blocked)
              ListTile(
                dense: true,
                leading: Icon(Icons.block,
                    size: 20, color: Colors.grey.shade500),
                title: Text(
                  appState.tryUserById(id)?.nickname ?? '（退会済みのユーザー）',
                  style: theme.textTheme.bodyMedium,
                ),
                trailing: TextButton(
                  onPressed: () => appState.unblockUser(id),
                  child: const Text('解除'),
                ),
              ),
        ],
      ),
    );
  }

  /// アカウント削除（2段階確認つき）。Supabase モードは
  /// delete_my_account() で自分の行と auth ユーザーを完全に消す。
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('アカウントを削除しますか？'),
        content: const Text(
            'アカウント・プロフィール・募集・コミュニティ参加・メッセージが'
            'すべて削除され、元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await authService.deleteAccount();
      appState.detach();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('削除に失敗しました。通信状況をご確認ください'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _statCard(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall!
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
