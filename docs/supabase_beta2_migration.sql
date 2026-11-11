-- ベータ版 v2.1 マイグレーション: コミュニティ機能
-- （店舗ファンコミュニティ / クラブ / イベント企画・参加 / コミュニティチャット）

-- 1. コミュニティ本体（誰でも作成可能。オーナー主導で運営）
create table if not exists public.communities (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  description text not null default '',
  linked_store text,
  created_at timestamptz not null default now()
);

alter table public.communities enable row level security;
create policy "コミュニティは全員が閲覧可" on public.communities
  for select using (true);
create policy "コミュニティは本人が作成" on public.communities
  for insert with check (auth.uid() = owner_id);
create policy "コミュニティはオーナーが更新" on public.communities
  for update using (auth.uid() = owner_id);

-- 2. コミュニティメンバー（参加/脱退）
create table if not exists public.community_members (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);

alter table public.community_members enable row level security;
create policy "メンバーリストは全員に見える" on public.community_members
  for select using (true);
create policy "本人のみ参加追加" on public.community_members
  for insert with check (auth.uid() = user_id);
create policy "本人のみ脱退" on public.community_members
  for delete using (auth.uid() = user_id);

-- 3. コミュニティチャットは既存 chat_rooms / chat_messages を再利用する
alter table public.chat_rooms
  add column if not exists community_id uuid;

-- 4. イベント・クラブ（コミュニティ内で誰でも企画可能）
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  host_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null default '',
  event_time text not null default '',
  location_name text not null default '',
  capacity int not null default 20,
  created_at timestamptz not null default now()
);

alter table public.events enable row level security;
create policy "イベントは全員が閲覧可" on public.events
  for select using (true);
create policy "イベントは本人が作成" on public.events
  for insert with check (auth.uid() = host_id);
create policy "イベントは主催者が更新" on public.events
  for update using (auth.uid() = host_id);
create policy "イベントは主催者が削除" on public.events
  for delete using (auth.uid() = host_id);

create table if not exists public.event_participants (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

alter table public.event_participants enable row level security;
create policy "参加者リストは全員に見える" on public.event_participants
  for select using (true);
create policy "本人のみ参加追加" on public.event_participants
  for insert with check (auth.uid() = user_id);
create policy "本人のみ参加取消" on public.event_participants
  for delete using (auth.uid() = user_id);
