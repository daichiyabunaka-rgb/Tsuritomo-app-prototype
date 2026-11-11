import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import 'community_detail_screen.dart';
import 'widgets.dart';
import 'community_create_sheet.dart' as create;

/// 「コミュニティ」タブ: クラブ・イベント・店舗ファンコミュニティ。
/// 誰でも作成・参加でき、参加するとチャットが行える（FR-6-1〜6-3）。
class CommunitiesPage extends StatelessWidget {
  const CommunitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final mine = appState.myCommunities
              ..sort((a, b) => appState
                  .communityDistanceKm(a)
                  .compareTo(appState.communityDistanceKm(b)));
            final others =
                appState.communities.where((c) => !mine.contains(c)).toList()
                  ..sort((a, b) => appState
                      .communityDistanceKm(a)
                      .compareTo(appState.communityDistanceKm(b)));
            return RefreshIndicator(
              onRefresh: () => appState.refreshCommunities(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('参加中のコミュニティ（${mine.length}）',
                            style: theme.textTheme.titleSmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (mine.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'まだ参加していません。下の一覧から参加するか、'
                          '「作る」から自分のコミュニティを始められます。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  for (final c in mine)
                    _communityTile(context, c, isMember: true),
                  const SizedBox(height: 16),
                  Text('その他のコミュニティ（${others.length}）',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (others.isEmpty)
                    Text(
                      '自分が作ったものも、他の利用者が参加するとここに表示されます。',
                      style: theme.textTheme.bodySmall,
                    ),
                  for (final c in others)
                    _communityTile(context, c, isMember: false),
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => create.showCommunityCreateSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('作る'),
      ),
    );
  }

  Widget _communityTile(BuildContext context, Community c,
      {required bool isMember}) {
    final owner = appState.userById(c.ownerId);
    return Card(
      child: ListTile(
        leading: userAvatar(c.ownerId, size: 48),
        title: Text(
          c.linkedStore != null ? '${c.name}（${c.linkedStore}のファン）' : c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${c.memberIds.length}人参加 / 主催: ${owner.nickname}'
          ' / ${appState.communityDistanceLabel(c)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isMember
            ? const Icon(Icons.chat_bubble_outline)
            : Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  '参加',
                  style: TextStyle(
                      fontSize: 11, color: Colors.blue.shade800),
                ),
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                CommunityDetailScreen(communityId: c.id),
          ),
        ),
      ),
    );
  }
}
