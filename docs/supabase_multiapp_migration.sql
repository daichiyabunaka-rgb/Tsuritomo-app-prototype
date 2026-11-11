-- ============================================================
-- 「犬とも！×釣りとも！」共有プロジェクト化マイグレーション
-- 対象: 犬とも！の稼働中Supabaseプロジェクト（追加のみ・非破壊・トランザクション）
--
-- 内容:
--   1. アプリ分離列 app_id
--      （recruitments / communities / events / chat_rooms / categories）
--      既存データはすべて 'inutomo' 扱い。既存の犬ともAPK（列を知らない）
--      からのINSERTも DEFAULT 'inutomo' で壊れない。
--   2. profiles を「ユーザー × アプリ」の複数行構成に変更
--      （アカウント〈auth.users〉は全アプリ共通のまま、
--        ニックネーム・アイコン・自己紹介・興味はアプリごとに別）
--   3. profiles を参照していた外部キーを auth.users へ張り替え
--   4. 釣りとも用オブジェクトの追加
--      （catch_reports テーブル・Storageバケット catch-photos）
--   5. 共有RPC/関数のアプリ対応
--      （get_or_create_dm にアプリ引数を追加。旧署名は犬とも互換で残す）
--
-- 前提: 犬とも本番（docs/apply_all.sql 相当）が適用済みであること。
-- 犬とも旧機能の protected_dogs テーブル等は触らない（残置）。
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. アプリ分離列
-- ------------------------------------------------------------
alter table public.recruitments  add column if not exists app_id text default 'inutomo';
alter table public.communities    add column if not exists app_id text default 'inutomo';
alter table public.events         add column if not exists app_id text default 'inutomo';
alter table public.chat_rooms     add column if not exists app_id text default 'inutomo';
alter table public.categories     add column if not exists app_id text default 'inutomo';

update public.recruitments  set app_id = 'inutomo' where app_id is null;
update public.communities    set app_id = 'inutomo' where app_id is null;
update public.events         set app_id = 'inutomo' where app_id is null;
update public.chat_rooms     set app_id = 'inutomo' where app_id is null;
update public.categories     set app_id = 'inutomo' where app_id is null;

-- ------------------------------------------------------------
-- 2. profiles を（ユーザー × アプリ）構成へ
-- ------------------------------------------------------------
alter table public.profiles add column if not exists app_id text default 'inutomo';
update public.profiles set app_id = 'inutomo' where app_id is null;

-- profiles を参照する外部キーをすべて外す（後で auth.users 参照に付け直す）
do $$
declare r record;
begin
  for r in
    select conrelid::regclass as tbl, conname
    from pg_constraint
    where contype = 'f'
      and confrelid = 'public.profiles'::regclass
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end $$;

alter table public.profiles drop constraint if exists profiles_pkey;
alter table public.profiles alter column app_id set not null;
alter table public.profiles add primary key (id, app_id);

-- ------------------------------------------------------------
-- 3. 外部キーを auth.users 参照に張り替え
--    （複数行化した profiles は参照元にできないため。
--      カスケード削除の挙動は従来どおり auth.users 削除で全部消える）
-- ------------------------------------------------------------
alter table public.recruitments
  add constraint recruitments_host_id_fkey
  foreign key (host_id) references auth.users(id) on delete cascade;

alter table public.join_applications
  add constraint join_applications_applicant_id_fkey
  foreign key (applicant_id) references auth.users(id) on delete cascade;

alter table public.chat_room_members
  add constraint chat_room_members_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.chat_messages
  add constraint chat_messages_sender_id_fkey
  foreign key (sender_id) references auth.users(id) on delete cascade;

alter table public.communities
  add constraint communities_owner_id_fkey
  foreign key (owner_id) references auth.users(id) on delete cascade;

alter table public.community_members
  add constraint community_members_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.events
  add constraint events_host_id_fkey
  foreign key (host_id) references auth.users(id) on delete cascade;

alter table public.event_participants
  add constraint event_participants_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.categories
  add constraint categories_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

alter table public.blocks
  add constraint blocks_blocker_id_fkey
  foreign key (blocker_id) references auth.users(id) on delete cascade;

alter table public.blocks
  add constraint blocks_blocked_id_fkey
  foreign key (blocked_id) references auth.users(id) on delete cascade;

alter table public.stores
  add constraint stores_owner_id_fkey
  foreign key (owner_id) references auth.users(id) on delete cascade;

alter table public.ai_concierge_logs
  add constraint ai_concierge_logs_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.reports
  add constraint reports_reporter_id_fkey
  foreign key (reporter_id) references auth.users(id) on delete cascade;

-- ------------------------------------------------------------
-- 4. 釣りとも用オブジェクトの追加
-- ------------------------------------------------------------
create table if not exists public.catch_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('sea', 'fresh')),
  fish_description text not null,
  area_name text not null,
  detail text not null default '',
  photo_path text,
  location_geohash text not null,
  closed boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists catch_reports_geohash_idx
  on public.catch_reports (location_geohash);

alter table public.catch_reports enable row level security;
create policy "釣果速報は誰でも閲覧可" on public.catch_reports
  for select using (true);
create policy "登録は本人のみ" on public.catch_reports
  for insert with check (auth.uid() = reporter_id);
create policy "更新削除は本人のみ" on public.catch_reports
  for update using (auth.uid() = reporter_id);
create policy "釣果削除は本人のみ" on public.catch_reports
  for delete using (auth.uid() = reporter_id);

insert into storage.buckets (id, name, public)
values ('catch-photos', 'catch-photos', true)
on conflict (id) do nothing;

drop policy if exists "釣果写真は公開読み取り可" on storage.objects;
drop policy if exists "認証ユーザーは自分の釣果写真をアップロード可" on storage.objects;
drop policy if exists "認証ユーザーは自分の釣果写真を削除可" on storage.objects;

create policy "釣果写真は公開読み取り可" on storage.objects
  for select using (bucket_id = 'catch-photos');

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

-- ------------------------------------------------------------
-- 5. 関数の共有対応
-- ------------------------------------------------------------

-- 近くの募集（app_idで絞る。デフォルト=犬とも）
create or replace function public.nearby_recruitments(
  p_geohash text,
  p_prefix_len int default 5,
  p_app text default 'inutomo'
)
returns setof public.recruitments
language sql
stable
as $$
  select r.*
  from public.recruitments r
  join public.profiles p on p.id = r.host_id and p.app_id = p_app
  where r.status = 'active'
    and r.app_id = p_app
    and p.location_geohash is not null
    and left(p.location_geohash, p_prefix_len) = left(p_geohash, p_prefix_len)
$$;

-- 近くのユーザー（app_idで絞る。デフォルト=犬とも）
create or replace function public.nearby_profiles(
  p_geohash text,
  p_prefix_len int default 5,
  p_limit int default 50,
  p_app text default 'inutomo'
)
returns setof public.profiles
language sql
stable
as $$
  select p.*
  from public.profiles p
  where p.app_id = p_app
    and p.location_geohash is not null
    and left(p.location_geohash, p_prefix_len) = left(p_geohash, p_prefix_len)
  limit p_limit
$$;

-- DM部屋の取得（アプリ別）。新署名
create or replace function public.get_or_create_dm(p_other_user uuid, p_app text)
returns uuid
language plpgsql
security definer
as $$
declare
  v_room uuid;
begin
  select a.room_id into v_room
  from public.chat_room_members a
  join public.chat_rooms c on c.id = a.room_id and c.type = 'dm' and c.app_id = p_app
  join public.chat_room_members b on b.room_id = a.room_id
  where a.user_id = auth.uid() and b.user_id = p_other_user
  limit 1;

  if v_room is null then
    insert into public.chat_rooms (type, app_id) values ('dm', p_app)
    returning id into v_room;
    insert into public.chat_room_members (room_id, user_id)
      values (v_room, auth.uid()), (v_room, p_other_user);
  end if;

  return v_room;
end;
$$;

-- 旧署名（犬とも旧APK互換。inutomo固定）。全APK更新後に削除してよい
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
  join public.chat_rooms c on c.id = a.room_id and c.type = 'dm' and c.app_id = 'inutomo'
  join public.chat_room_members b on b.room_id = a.room_id
  where a.user_id = auth.uid() and b.user_id = p_other_user
  limit 1;

  if v_room is null then
    insert into public.chat_rooms (type, app_id) values ('dm', 'inutomo')
    returning id into v_room;
    insert into public.chat_room_members (room_id, user_id)
      values (v_room, auth.uid()), (v_room, p_other_user);
  end if;

  return v_room;
end;
$$;

-- アカウント削除（釣りとのものデータも消す。プロフィールは全アプリ分行ごと削除）
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

  delete from public.community_members where user_id = auth.uid();
  delete from public.event_participants where user_id = auth.uid();
  delete from public.chat_room_members where user_id = auth.uid();
  delete from public.join_applications where applicant_id = auth.uid();
  delete from public.recruitments where host_id = auth.uid();
  delete from public.communities where owner_id = auth.uid();
  delete from public.categories where created_by = auth.uid();
  delete from public.blocks where blocker_id = auth.uid() or blocked_id = auth.uid();
  delete from public.reports where reporter_id = auth.uid();
  delete from public.catch_reports where reporter_id = auth.uid();
  delete from public.profiles where id = auth.uid();

  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

commit;
