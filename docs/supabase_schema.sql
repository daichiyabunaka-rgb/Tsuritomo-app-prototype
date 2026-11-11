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
