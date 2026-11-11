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
