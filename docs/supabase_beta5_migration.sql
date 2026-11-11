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
