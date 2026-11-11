-- 釣りとも！ 最終修正: 募集のホストは自分の募集のグループ部屋を閲覧できる
-- （承認フローで部屋を作成した直後、自分はまだメンバーでないため
--   insert().select() が空返しになる問題への対処）

drop policy if exists "部屋はメンバー・コミュニティ参加者が閲覧" on public.chat_rooms;
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
