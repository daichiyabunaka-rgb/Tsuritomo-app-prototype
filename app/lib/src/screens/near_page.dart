import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../util/format.dart';
import 'recruitment_create_sheet.dart';
import 'recruitment_detail_screen.dart';
import 'spot_page.dart';
import 'map_screen.dart';
import 'store_sheet.dart';
import 'user_detail_screen.dart';
import 'widgets.dart';

/// 「近く」タブ。
/// [募集] アクティブな募集を距離順に表示（FR-2-2）
/// [人] 近くの一般ユーザーのアイコンが並ぶ（要望: 位置情報から近くの一般ユーザー）
/// [店] 近くのビジネスユーザーのアイコンが並ぶ（要望: 近くのビジネスユーザー）
/// [釣り場] 近くの釣り場を探す（Googleマップ連携）
class NearPage extends StatefulWidget {
  const NearPage({super.key});

  @override
  State<NearPage> createState() => _NearPageState();
}

enum NearTab { recruit, people, business, spot }

class _NearPageState extends State<NearPage> {
  Timer? _ticker;
  NearTab _tab = NearTab.recruit;
  final TextEditingController _storeSearch = TextEditingController();
  // 一覧は50件ずつ表示（「さらに表示」で追加）
  static const int batchSize = 50;
  int _peopleShown = batchSize;
  int _storesShown = batchSize;

  @override
  void dispose() {
    _ticker?.cancel();
    _storeSearch.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
        const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.near_me,
                      size: 18, color: appState.gpsAvailable
                          ? theme.colorScheme.primary
                          : Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appState.gpsAvailable
                          ? '現在地周辺（GPS取得済み）'
                          : '現在地: 東京駅（GPS未取得のフォールバック）',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  // 近くの人・募集の距離計算にのみ位置を使い、UIには粗いバンド表示のみ出す（FR-2-2）
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<NearTab>(
                segments: const [
                  ButtonSegment(
                      value: NearTab.recruit,
                      icon: Icon(Icons.campaign),
                      label: Text('募集')),
                  ButtonSegment(
                      value: NearTab.people,
                      icon: Icon(Icons.people_outline),
                      label: Text('人')),
                  ButtonSegment(
                      value: NearTab.business,
                      icon: Icon(Icons.storefront),
                      label: Text('店')),
                  ButtonSegment(
                      value: NearTab.spot,
                      icon: Icon(Icons.phishing),
                      label: Text('釣り場')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: appState,
                builder: (context, _) {
                  Widget body;
                  switch (_tab) {
                    case NearTab.recruit:
                      body = _recruitList(context);
                      break;
                    case NearTab.people:
                      body = _peopleList(context);
                      break;
                    case NearTab.business:
                      body = _businessList(context);
                      break;
                    case NearTab.spot:
                      body = const SpotPage();
                      break;
                  }
                  // Supabase モードでは引き更新で実データを再取得
                  return RefreshIndicator(
                    onRefresh: () => appState.refreshFromRemote(),
                    child: body,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tab == NearTab.recruit
          ? FloatingActionButton.extended(
              onPressed: () => showRecruitmentCreateSheet(context),
              icon: const Icon(Icons.campaign),
              label: const Text('募集をかける'),
            )
          : null,
    );
  }

  // ----------------------------------------------------------- 募集

  Widget _recruitList(BuildContext context) {
    final list = appState.activeRecruitments();
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '近くにアクティブな募集がありません。\n'
            '「募集をかける」ボタンから、あなたから募集を始められます。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      itemBuilder: (context, i) => RecruitmentCard(
        recruitment: list[i],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                RecruitmentDetailScreen(recruitmentId: list[i].id),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- 近くの人

  Widget _peopleList(BuildContext context) {
    final people = appState.generalUsers..sort((a, b) => _km(a).compareTo(_km(b)));
    if (people.isEmpty) {
      return const Center(child: Text('近くに一般ユーザーがいません'));
    }
    // 50件ずつ表示（「さらに表示」で追加）
    final visible = people.take(_peopleShown).toList();
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final u = visible[i];
              return InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => UserDetailScreen(userId: u.id),
                  ),
                ),
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    userAvatar(u.id, size: 64),
                    const SizedBox(height: 6),
                    Text(
                      u.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      appState.userDistanceLabel(u),
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    if (u.isOtherApp)
                      Text(
                        u.appSourceLabel,
                        style: TextStyle(
                            fontSize: 10, color: Colors.teal.shade700),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (people.length > _peopleShown)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: OutlinedButton(
              onPressed: () => setState(() => _peopleShown += batchSize),
              child:
                  Text('さらに表示（残り${people.length - _peopleShown}人）'),
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------- 近くの店

  Widget _businessList(BuildContext context) {
    final stores = appState.businessUsers
      ..sort((a, b) => _km(a).compareTo(_km(b)));
    final keyword = _storeSearch.text.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? stores
        : stores
            .where((s) =>
                s.nickname.toLowerCase().contains(keyword) ||
                s.storeType.toLowerCase().contains(keyword) ||
                s.bio.toLowerCase().contains(keyword))
            .toList();
    if (stores.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('まだ近くに店が登録されていません'),
              const SizedBox(height: 8),
              Text(
                'ビジネスユーザーとして会員登録すると、あなたのお店をここに'
                '出せます（ベータ期間中は無料です）。友人のお店を「招待・紹介」で'
                '呼ぶのもおすすめです。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _storeSearch,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '店を探す（店名・業態・雰囲気で検索）',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
              filled: true,
              fillColor: Colors.grey.shade50,
              suffixIcon: keyword.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _storeSearch.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: const Text('近くの店をマップで見る'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MapScreen(),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('検索に一致する店がありません'))
              : Builder(builder: (context) {
                  // 50件ずつ表示（「さらに表示」で追加）
                  final visible = filtered.take(_storesShown).toList();
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount:
                        visible.length + (filtered.length > _storesShown ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= visible.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: OutlinedButton(
                            onPressed: () =>
                                setState(() => _storesShown += batchSize),
                            child: Text(
                                'さらに表示（残り${filtered.length - _storesShown}件）'),
                          ),
                        );
                      }
                      final s = visible[i];
                      return Card(
                        child: ListTile(
                          leading: userAvatar(s.id, size: 48),
                          title: Text(s.nickname,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${s.storeType} / ${appState.userDistanceLabel(s)}',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.blue.shade200),
                            ),
                            child: Text(
                              'お店',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade900),
                            ),
                          ),
                          onTap: () => showStoreSheet(context, s),
                        ),
                      );
                    },
                  );
                }),
        ),
      ],
    );
  }

  double _km(AppUser u) {
    final me = appState.me!;
    return haversineKm(me.lat, me.lng, u.lat, u.lng);
  }
}

class RecruitmentCard extends StatelessWidget {
  const RecruitmentCard(
      {super.key, required this.recruitment, required this.onTap});

  final Recruitment recruitment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final host = appState.userById(recruitment.hostId);
    final theme = Theme.of(context);
    final isMine = recruitment.hostId == appState.me!.id;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  userAvatar(host.id, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          host.nickname,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${host.decade} / ${host.genderLabel}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isMine
                        ? 'あなたの募集'
                        : appState.recruitmentDistanceLabel(recruitment),
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                recruitment.title,
                style: theme.textTheme.titleMedium!
                    .copyWith(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                recruitment.body,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  genreChip(recruitment.genreId),
                  const SizedBox(width: 8),
                  Icon(Icons.group, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 2),
                  Text('あと${recruitment.remainingSlots}人',
                      style: TextStyle(color: Colors.grey.shade700)),
                  const SizedBox(width: 8),
                  Icon(Icons.place, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      recruitment.meetup,
                      style: TextStyle(color: Colors.grey.shade700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    remainingLabel(recruitment.expiresAt, now),
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
