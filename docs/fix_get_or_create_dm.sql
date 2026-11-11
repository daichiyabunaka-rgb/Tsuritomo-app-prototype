-- get_or_create_dm の修正（room_id 列の曖昧参照エラー対応）
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