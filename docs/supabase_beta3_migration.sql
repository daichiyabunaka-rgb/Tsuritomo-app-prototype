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
