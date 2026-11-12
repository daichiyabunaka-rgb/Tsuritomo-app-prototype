import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/app_config.dart';
import '../services/app_state.dart';
import '../services/supabase_data.dart';
import 'chat_screen.dart';
import 'widgets.dart';

/// ユーザー詳細（プロフィール閲覧 + DM の起点）。
/// 出会い系ではなく釣りとも候補として見る画面なので、募集や嗜好を主に表示する。
/// SNS・URLは本人がプロフィールで公開したものだけ表示する。
class UserDetailScreen extends StatelessWidget {
  const UserDetailScreen({super.key, required this.userId});

  final String userId;

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _call(String phone) async {
    try {
      await launchUrl(Uri.parse('tel:$phone'));
    } catch (_) {}
  }

  String _normalizedUrl(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    return 'https://$raw';
  }

  /// ブロックの確認。ブロックしたことは相手には一切伝わらない。
  Future<void> _confirmBlock(BuildContext context, AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${user.nickname}さんをブロックしますか？'),
        content: const Text(
            'この人のプロフィール・募集・部屋が表示されなくなります。'
            'ブロックしたことを相手に通知することはありません。'),
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
            child: const Text('ブロックする'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await appState.blockUser(user.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ブロックしました。この人のプロフィール・募集・部屋は非表示になります'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final user = appState.userById(userId);
    final isMe = appState.me!.id == user.id;

    // ブロック済みの相手: プロフィールの内容は非表示にする
    if (appState.isBlocked(user.id)) {
      return Scaffold(
        appBar: AppBar(title: const Text('プロフィール')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 48, color: Colors.grey.shade500),
                const SizedBox(height: 12),
                const Text('ブロックしたユーザーです'),
                const SizedBox(height: 8),
                Text(
                  'この人のプロフィール・募集・部屋は表示されません。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('ブロックを解除する'),
                  onPressed: () => appState.unblockUser(user.id),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final recruitments = appState
        .activeRecruitments()
        .where((r) => r.hostId == user.id)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  userAvatar(user.id, size: 88, iconScale: 0.45),
                  const SizedBox(height: 12),
                  Text(
                    user.nickname,
                    style: theme.textTheme.headlineSmall!
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (user.isOtherApp) ...[
                    const SizedBox(height: 4),
                    _appBadge(theme, user.appSourceLabel),
                  ],
                  Text(
                    user.isBusiness
                        ? '${(user as BusinessUser).storeType} / '
                            '${appState.userDistanceLabel(user)}'
                        : '${user.decade} / ${user.genderLabel} / '
                            '${appState.userDistanceLabel(user)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final id in user.interestIds)
                        interestLabel(appState.categoryOf(id)),
                    ],
                  ),
                  if (user.snsNote?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.alternate_email,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            user.snsNote!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (user.websiteUrl?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _open(_normalizedUrl(user.websiteUrl!)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              user.websiteUrl!,
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
                  if (user.isBusiness &&
                      (user.phone?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _call(user.phone!),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.phone,
                                size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              user.phone!,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (user.bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      user.bio,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (AppConfig.useSupabase) ...[
            const SizedBox(height: 8),
            _tomoTskuAppsSection(context, user),
          ],
          if (!isMe) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(user.isOtherApp
                    ? '${user.appSourceLabel}とうちにDMする'
                    : 'DMを始める'),
                onPressed: () async {
                  final room = await appState.getOrCreateDm(user.id,
                      crossApp: user.isOtherApp);
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(roomId: room.id),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                icon: Icon(Icons.block_outlined,
                    size: 18, color: Colors.red.shade700),
                label: Text('この人をブロック',
                    style: TextStyle(color: Colors.red.shade700)),
                onPressed: () => _confirmBlock(context, user),
              ),
            ),
          ],
          if (recruitments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('この人の募集', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final r in recruitments)
              Card(
                child: ListTile(
                  leading: genreChip(r.genreId),
                  title: Text(r.title, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: Text(appState.recruitmentDistanceLabel(r)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 他のともつく！アプリ由来であることを示すバッジ
  Widget _appBadge(ThemeData theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Text(
        '$labelから',
        style: TextStyle(fontSize: 12, color: Colors.teal.shade700),
      ),
    );
  }

  /// 「使っているともつく！」（全体公開に設定されたアプリのみ表示）
  Widget _tomoTskuAppsSection(BuildContext context, AppUser user) {
    final theme = Theme.of(context);
    return FutureBuilder<
        List<({String appId, bool crossAppVisible, String nickname})>>(
      future: supabaseData.fetchTomoTskuProfiles(user.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        // このアプリの行は除外し、全体公開の他アプリだけ表示する
        final apps = snapshot.data!
            .where((p) => p.appId != AppConfig.appId)
            .where((p) => p.crossAppVisible)
            .map((p) => tomoTskuAppNames[p.appId] ?? p.appId)
            .toList();
        if (apps.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hub_outlined,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'ともつく！: ${apps.join('・')} も利用中',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
