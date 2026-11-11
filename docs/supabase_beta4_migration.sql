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
