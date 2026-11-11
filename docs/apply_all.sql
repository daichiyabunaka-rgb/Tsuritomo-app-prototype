-- ============================================================
-- 釣りとも！ Supabase セットアップ SQL（全ファイル結合・このファイルだけ実行すれば良い）
-- 実行場所: Supabase Dashboard の SQL Editor で全選択して Run

-- ============================================================
-- supabase_schema.sql
-- ============================================================

-- 釣りとも！ Supabase スキーマ（v1.5 バックエンド設計）
-- 使い方: Supabase プロジェクトを作成し、SQL Editor でこのファイルを実行する。
-- その後、アプリ側で supabase_flutter を導入し、モックサービス
-- (AuthService / AppState のデータ層) を Supabase 実装に差し替える。

-- ============================================================
-- 1. プロフィール
-- ============================================================
-- Supabase Auth の auth.users に紐づける（auth.uid() を主キーにする）
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  birth_decade text not null,              -- '18〜19歳' | '20代' ...
  gender text not null default 'undisclosed',
  role text not null default 'general' check (role in ('general','business')),
  icon_category_id text,                  -- 趣味アイコンセットのID
  icon_image_path text,                   -- Supabase Storage のパス（投稿画像）
  interest_ids text[] not null default '{}',
  bio text not null default '',
  -- 位置は geohash のみ保持（生の緯度経度は保存しない方針も可能。
  -- 近傍検索は geohash プレフィックス照合で行う）
  location_geohash text,
  online boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "自分のプロフィールは本人が管理" on public.profiles
  for all using (auth.uid() = id);

create policy "プロフィールは全ログインユーザーが閲覧可" on public.profiles
  for select using (true);

-- ============================================================
-- 2. 募集 / 応募
-- ============================================================
create table public.recruitments (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles(id) on delete cascade,
  genre_id text not null,
  title text not null,
  body text not null default '',
  meetup text not null default '',
  capacity int not null default 3,
  status text not null default 'active'
    check (status in ('active','fulfilled','expired','cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null  -- 期限切れはバッチで expired 化
);

alter table public.recruitments enable row level security;

create policy "募集は全ログインユーザーが閲覧可" on public.recruitments
  for select using (true);

create policy "募集は本人が作成・更新" on public.recruitments
  for all using (auth.uid() = host_id);

create table public.join_applications (
  id uuid primary key default gen_random_uuid(),
  recruitment_id uuid not null references public.recruitments(id) on delete cascade,
  applicant_id uuid not null references public.profiles(id) on delete cascade,
  message text not null default '',
  status text not null default 'pending'
    check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  unique (recruitment_id, applicant_id)
);

alter table public.join_applications enable row level security;

create policy "応募はホストと応募者のみ閲覧可" on public.join_applications
  for select using (
    auth.uid() = applicant_id
    or auth.uid() in (
      select host_id from public.recruitments r where r.id = recruitment_id
    )
  );

create policy "応募は本人が作成" on public.join_applications
  for insert with check (auth.uid() = applicant_id);

create policy "応募の承認却下はホストのみ" on public.join_applications
  for update using (
    auth.uid() in (
      select host_id from public.recruitments r where r.id = recruitment_id
    )
  );

-- ============================================================
-- 3. チャット（グループ + DM）
-- ============================================================
create table public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  recruitment_id uuid,                    -- DM・コミュニティの場合は null
  community_id uuid,                      -- コミュニティチャットの場合（beta2で追加。新規プロジェクトでは最初から持つ）
  type text not null default 'group' check (type in ('group','dm','community')),
  created_at timestamptz not null default now()
);

create table public.chat_room_members (
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  is_system boolean not null default false,
  sent_at timestamptz not null default now()
);

alter table public.chat_room_members enable row level security;
create policy "メンバーは自分の参加情報を閲覧" on public.chat_room_members
  for select using (
    auth.uid() = user_id
    or public.is_room_member(chat_room_members.room_id)
  );
create policy "本人のみ自分の参加を追加" on public.chat_room_members
  for insert with check (
    auth.uid() = user_id
    or public.is_recruitment_host(room_id)
  );
-- NOTE: グループ部屋のメンバー追加（承認時）は募集のホストが行う。
-- DM の作成は get_or_create_dm（security definer）で本人確認してから行う

-- RLS ポリシー内で同じテーブルを参照すると無限再帰するため、
-- ヘルパーは security definer でメンバーシップのみを確認する
create or replace function public.is_room_member(p_room uuid)
returns boolean
language sql security definer stable set search_path = public
as $$
  select exists (
    select 1 from public.chat_room_members m
    where m.room_id = p_room and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_recruitment_host(p_room uuid)
returns boolean
language sql security definer stable set search_path = public
as $$
  select exists (
    select 1
      from public.recruitments r
      join public.chat_rooms c on c.recruitment_id = r.id
     where c.id = p_room and r.host_id = auth.uid()
  );
$$;

-- 最近の Supabase プロジェクトはテーブル作成時に RLS が自動有効化されるため、
-- chat_rooms にも明示的にポリシーが必要
alter table public.chat_rooms enable row level security;
create policy "部屋はメンバー・コミュニティ参加者が閲覧" on public.chat_rooms
  for select using (
    public.is_room_member(chat_rooms.id)
    or public.is_recruitment_host(chat_rooms.id)
    or (
      chat_rooms.community_id is not null
      and exists (
        select 1 from public.community_members cm
        where cm.community_id = chat_rooms.community_id
          and cm.user_id = auth.uid()
      )
    )
  );
create policy "認証ユーザーは部屋を作成可" on public.chat_rooms
  for insert to authenticated
  with check (type in ('group', 'community'));

alter table public.chat_messages enable row level security;
create policy "メンバーのみメッセージを閲覧" on public.chat_messages
  for select using (
    exists (
      select 1 from public.chat_room_members m
      where m.room_id = room_id and m.user_id = auth.uid()
    )
  );

create policy "メンバーのみメッセージを送信" on public.chat_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.chat_room_members m
      where m.room_id = room_id and m.user_id = auth.uid()
    )
  );

-- リアルタイム配信（Supabase Realtime）
alter publication supabase_realtime add table public.chat_messages;

-- ============================================================
-- 4. 店舗（ビジネスユーザー）
-- ============================================================
create table public.stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  industry_type text not null,            -- '釣具店' | '乗り合い船・渡船' ...
  serves_alcohol boolean not null default false,
  address text not null default '',
  location_geohash text,
  business_hours jsonb not null default '{}',
  bio text not null default '',
  created_at timestamptz not null default now()
);

alter table public.stores enable row level security;
create policy "店舗は全員が閲覧可" on public.stores
  for select using (true);
create policy "店舗はオーナーが管理" on public.stores
  for all using (auth.uid() = owner_id);

-- ============================================================
-- 5. AI接客ログ（ビジネスユーザー向け有料機能）
-- ============================================================
create table public.ai_concierge_logs (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  question text not null,
  answer text not null,
  created_at timestamptz not null default now()
);

alter table public.ai_concierge_logs enable row level security;
create policy "ログは店舗オーナーと発話者のみ閲覧可" on public.ai_concierge_logs
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.stores s
      where s.id = store_id and s.owner_id = auth.uid()
    )
  );

-- ============================================================
-- 6. 通報 / ブロック（モデレーション）
-- ============================================================
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('user','recruitment','message')),
  target_id text not null,
  reason text not null,
  status text not null default 'open' check (status in ('open','reviewed','actioned')),
  created_at timestamptz not null default now()
);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

alter table public.reports enable row level security;
create policy "通報は本人が作成" on public.reports
  for insert to authenticated with check (auth.uid() = reporter_id);
create policy "通報は本人が閲覧" on public.reports
  for select using (auth.uid() = reporter_id);

alter table public.blocks enable row level security;
create policy "ブロックは本人のみ" on public.blocks
  for all using (auth.uid() = blocker_id);

-- ------------------------------------------------------------
-- 6.x 釣果速報の登録（近隣共有。位置は geohash のみ保持）
-- 海・川・湖の釣果を近隣の釣り人と共有する（遊漁ルールの遵守を常に案内）
-- ------------------------------------------------------------
create table public.catch_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('sea', 'fresh')),
  fish_description text not null,
  area_name text not null,
  detail text not null default '',
  photo_path text,                           -- 投稿写真（Storage 'catch-photos' バケットの公開URL）
  location_geohash text not null,
  closed boolean not null default false,
  created_at timestamptz not null default now()
);
create index catch_reports_geohash_idx on public.catch_reports (location_geohash);

alter table public.catch_reports enable row level security;
create policy "釣果速報は誰でも閲覧可" on public.catch_reports
  for select using (true);
create policy "登録は本人のみ" on public.catch_reports
  for insert with check (auth.uid() = reporter_id);
create policy "更新削除は本人のみ" on public.catch_reports
  for update using (auth.uid() = reporter_id);
create policy "削除は本人のみ" on public.catch_reports
  for delete using (auth.uid() = reporter_id);

-- ============================================================
-- 7. 補助関数
-- ============================================================
-- 近くの募集を geohash プレフィックス（精度5: 約4.8km 四方）で引く
create or replace function public.nearby_recruitments(
  p_geohash text,
  p_prefix_len int default 5
)
returns setof public.recruitments
language sql
stable
as $$
  select r.*
  from public.recruitments r
  join public.profiles p on p.id = r.host_id
  where r.status = 'active'
    and p.location_geohash is not null
    and left(p.location_geohash, p_prefix_len) = left(p_geohash, p_prefix_len)
$$;

-- DM ルームの取得（なければ作成）
create or replace function public.get_or_create_dm(p_other_user uuid)
returns uuid
language plpgsql
security definer
as $$
declare
  v_room uuid;
begin
  select a.room_id into v_room
  from public.chat_room_members a
  join public.chat_rooms c on c.id = a.room_id and c.type = 'dm'
  join public.chat_room_members b on b.room_id = a.room_id
  where a.user_id = auth.uid() and b.user_id = p_other_user
  limit 1;

  if v_room is null then
    insert into public.chat_rooms (type) values ('dm') returning id into v_room;
    insert into public.chat_room_members (room_id, user_id)
      values (v_room, auth.uid()), (v_room, p_other_user);
  end if;

  return v_room;
end;
$$;


-- ============================================================
-- supabase_beta_migration.sql
-- ============================================================

-- ベータ版（v2.0.0）マイグレーション
-- 既存の docs/supabase_schema.sql 適用済みプロジェクトに追加で実行する。

-- 1. プロフィールに SNS / URL / 電話を公開できるようにする
alter table public.profiles
  add column if not exists website_url text,
  add column if not exists sns_note text,
  add column if not exists phone text,
  add column if not exists store_type text;

-- 2. 募集に参加者リストを持たせる（承認済みの応募者 + ホスト）
alter table public.recruitments
  add column if not exists member_ids uuid[] not null default '{}';

-- 3. 店舗に電話番号
alter table public.stores
  add column if not exists phone text;

-- 4. 募集作成・更新時に host を member_ids に入れるトリガー
create or replace function public.set_recruitment_host_member()
returns trigger
language plpgsql
as $$
begin
  if new.member_ids is null or array_length(new.member_ids, 1) is null then
    new.member_ids := array[new.host_id];
  elsif not (new.host_id = any(new.member_ids)) then
    new.member_ids := new.member_ids || new.host_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_recruitment_host_member on public.recruitments;
create trigger trg_recruitment_host_member
  before insert or update on public.recruitments
  for each row execute function public.set_recruitment_host_member();

-- 5. 近くのユーザー（geohash プレフィックス照合）
create or replace function public.nearby_profiles(
  p_geohash text,
  p_prefix_len int default 5,
  p_limit int default 50
)
returns setof public.profiles
language sql
stable
as $$
  select p.*
  from public.profiles p
  where p.location_geohash is not null
    and left(p.location_geohash, p_prefix_len) = left(p_geohash, p_prefix_len)
  limit p_limit
$$;


-- ============================================================
-- supabase_beta2_migration.sql
-- ============================================================

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


-- ============================================================
-- supabase_beta3_migration.sql
-- ============================================================

-- ベータ版 v2.2 マイグレーション: アイコン画像を Supabase Storage で共有
-- これまでは端末内保存のため他のユーザーから見えなかった。
-- 公開バケット icons を作り、ユーザーごとに自分の UUID 名前空間へ配置する。

insert into storage.buckets (id, name, public)
values ('icons', 'icons', true)
on conflict (id) do nothing;

-- ポリシーの重複対策
drop policy if exists "アイコンは公開読み取り可" on storage.objects;
drop policy if exists "認証ユーザーは自分のフォルダにアップロード可" on storage.objects;
drop policy if exists "認証ユーザーは自分のアイコンを更新可" on storage.objects;

-- 公開バケットなので誰でも閲覧可（プロフィール表示に必要）
create policy "アイコンは公開読み取り可" on storage.objects
  for select using (bucket_id = 'icons');

-- アップロードは認証ユーザー本人の名前空間（<uuid>/...）のみ
create policy "認証ユーザーは自分のフォルダにアップロード可" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'icons'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "認証ユーザーは自分のアイコンを更新可" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'icons'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ============================================================
-- supabase_beta4_migration.sql
-- ============================================================

-- ベータ版 v2.3 マイグレーション: ユーザーが興味カテゴリを自由に追加できる仕組み

-- アプリ内蔵のデフォルトカテゴリとは別に、ユーザー作成のカテゴリを保存する。
-- 全ユーザーに共有され、プロフィール・検索・募集で使える。
create table if not exists public.categories (
  id text primary key,
  label text not null unique,
  icon text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.categories enable row level security;

create policy "カテゴリは全員が閲覧可" on public.categories
  for select using (true);

create policy "認証ユーザーはカテゴリを作成可" on public.categories
  for insert to authenticated
  with check (auth.uid() = created_by);


-- ============================================================
-- supabase_beta5_migration.sql
-- ============================================================

-- ベータ版 v2.4 マイグレーション: アカウント削除（自己完結型）
-- このプロジェクトの Supabase 世代には auth.delete_user(uuid) が無いため、
-- auth.users への直接削除を使う（認証スキーマの子テーブルはすべて
-- ON DELETE CASCADE なので、トークンや identities も自動的に消える）。
drop function if exists public.delete_my_account();

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- 公開スキーマ上の自分の行を全て削除
  delete from public.community_members where user_id = auth.uid();
  delete from public.event_participants where user_id = auth.uid();
  delete from public.chat_room_members where user_id = auth.uid();
  delete from public.join_applications where applicant_id = auth.uid();
  delete from public.recruitments where host_id = auth.uid();
  delete from public.communities where owner_id = auth.uid();
  delete from public.categories where created_by = auth.uid();
  delete from public.blocks where blocker_id = auth.uid() or blocked_id = auth.uid();
  delete from public.reports where reporter_id = auth.uid();
  delete from public.profiles where id = auth.uid();

  -- auth 側を削除（ログイン不能になる。子テーブルは CASCADE で消える）
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;


-- ============================================================
-- supabase_beta6_tsuritomo_storage.sql
-- ============================================================

-- 釣りとも！ベータ版マイグレーション: 釣果速報の投稿写真バケット
-- docs/supabase_schema.sql の catch_reports テーブルと合わせて使う。
-- 公開バケット catch-photos を作り、ユーザーごとの UUID 名前空間へ配置する。

insert into storage.buckets (id, name, public)
values ('catch-photos', 'catch-photos', true)
on conflict (id) do nothing;

-- ポリシーの重複対策
drop policy if exists "釣果写真は公開読み取り可" on storage.objects;
drop policy if exists "認証ユーザーは自分の釣果写真をアップロード可" on storage.objects;
drop policy if exists "認証ユーザーは自分の釣果写真を削除可" on storage.objects;

-- 公開バケットなので誰でも閲覧可（一覧表示に必要）
create policy "釣果写真は公開読み取り可" on storage.objects
  for select using (bucket_id = 'catch-photos');

-- アップロードは認証ユーザー本人の名前空間（<uuid>/...）のみ
create policy "認証ユーザーは自分の釣果写真をアップロード可" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'catch-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "認証ユーザーは自分の釣果写真を削除可" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'catch-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
