-- Run once in Supabase Dashboard -> SQL Editor.
-- Adds "delete for me" / "delete for all" support for chat messages.
-- Reply and forward are handled client-side (they re-encrypt content), so no
-- schema change is needed for those.

-- Per-user soft deletion. Messages where auth.uid() is present in this array
-- are hidden from that user only.
alter table public.chat_messages
add column if not exists deleted_for uuid[] not null default '{}';

create or replace function public.delete_chat_message_for_all(p_message_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Sign in to delete a message.';
  end if;

  delete from public.chat_messages m
  where m.id = p_message_id
    and exists (
      select 1 from public.chat_conversations c
      where c.id = m.conversation_id
        and (current_user_id = c.user_a or current_user_id = c.user_b)
    );

  if not found then
    raise exception 'Message not found or you cannot delete it.';
  end if;
end;
$$;

create or replace function public.delete_chat_message_for_me(p_message_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Sign in to delete a message.';
  end if;

  update public.chat_messages m
  set deleted_for = (
    select coalesce(array_agg(distinct x), '{}'::uuid[])
    from unnest(m.deleted_for || array[current_user_id]) as x
  )
  where m.id = p_message_id
    and exists (
      select 1 from public.chat_conversations c
      where c.id = m.conversation_id
        and (current_user_id = c.user_a or current_user_id = c.user_b)
    );

  if not found then
    raise exception 'Message not found or you cannot delete it.';
  end if;
end;
$$;

revoke all on function public.delete_chat_message_for_all(bigint) from public;
revoke all on function public.delete_chat_message_for_me(bigint) from public;

grant execute on function public.delete_chat_message_for_all(bigint) to authenticated;
grant execute on function public.delete_chat_message_for_me(bigint) to authenticated;
