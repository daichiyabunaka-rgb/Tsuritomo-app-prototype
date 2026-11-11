-- ============================================================
-- 釣りとも！ 追加修正パック: chat_rooms 系ポリシーと制約
-- 新しい Supabase プロジェクトではテーブル作成時に RLS が自動有効化されるため、
-- ポリシー未定義のテーブルは全行が見えなくなる。このSQLで以下を修正する:
--   1. chat_rooms の type に community を追加（コミュニティチャット用）
--   2. chat_rooms の閲覧・作成ポリシー
--   3. chat_room_members: ホストが自分の募集の部屋にメンバーを追加できる
--   4. chat_room_members: 同じ部屋の参加者一覧が見える
--   5. reports（通報）のポリシー
-- すべて冪等（何度実行しても可）。
-- ============================================================

-- ---------- ヘルパー（RLS の無限再帰を避けるため security definer） ----------
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

-- ---------- 1. chat_rooms の type に community を追加 ----------
do $$
declare
  v_constraint text;
begin
  select conname into v_constraint
    from pg_constraint
   where conrelid = 'public.chat_rooms'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%type%';
  if v_constraint is not null then
    execute format('alter table public.chat_rooms drop constraint %I', v_constraint);
  end if;
end $$;
alter table public.chat_rooms
  drop constraint if exists chat_rooms_type_check;
alter table public.chat_rooms
  add constraint chat_rooms_type_check check (type in ('group', 'dm', 'community'));

-- ---------- 2. chat_rooms の RLS とポリシー ----------
alter table public.chat_rooms enable row level security;

drop policy if exists "部屋はメンバー・コミュニティ参加者が閲覧" on public.chat_rooms;
create policy "部屋はメンバー・コミュニティ参加者が閲覧" on public.chat_rooms
  for select using (
    public.is_room_member(chat_rooms.id)
    or (
      chat_rooms.community_id is not null
      and exists (
        select 1 from public.community_members cm
        where cm.community_id = chat_rooms.community_id
          and cm.user_id = auth.uid()
      )
    )
  );

drop policy if exists "認証ユーザーは部屋を作成可" on public.chat_rooms;
create policy "認証ユーザーは部屋を作成可" on public.chat_rooms
  for insert to authenticated
  with check (type in ('group', 'community'));

-- ---------- 3. chat_room_members: ホストによるメンバー追加 ----------
drop policy if exists "本人のみ自分の参加を追加" on public.chat_room_members;
create policy "本人のみ自分の参加を追加" on public.chat_room_members
  for insert with check (
    auth.uid() = user_id
    or public.is_recruitment_host(room_id)
  );

-- ---------- 4. chat_room_members: 同じ部屋の参加者一覧 ----------
drop policy if exists "メンバーは自分の参加情報を閲覧" on public.chat_room_members;
create policy "メンバーは自分の参加情報を閲覧" on public.chat_room_members
  for select using (
    auth.uid() = user_id
    or public.is_room_member(chat_room_members.room_id)
  );

-- ---------- 5. reports（通報）のポリシー ----------
alter table public.reports enable row level security;
drop policy if exists "通報は本人が作成" on public.reports;
create policy "通報は本人が作成" on public.reports
  for insert to authenticated with check (auth.uid() = reporter_id);
drop policy if exists "通報は本人が閲覧" on public.reports;
create policy "通報は本人が閲覧" on public.reports
  for select using (auth.uid() = reporter_id);
