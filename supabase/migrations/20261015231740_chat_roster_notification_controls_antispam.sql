begin;
create policy notifications_delete_own on public.notifications
  for delete to authenticated using (user_id = (select auth.uid()));
grant delete on public.notifications to authenticated;
create or replace function public.enforce_chat_message_rate_limit()
returns trigger language plpgsql security definer set search_path = pg_catalog, public
as $$
declare normalized_body text;
begin
  if (select auth.uid()) is null or new.author_id <> (select auth.uid()) then raise exception 'Sign in to send chat messages.'; end if;
  normalized_body := lower(regexp_replace(trim(new.body), '\\s+', ' ', 'g'));
  if length(normalized_body) = 0 then raise exception 'Write a message before sending.'; end if;
  perform pg_advisory_xact_lock(hashtextextended((select auth.uid())::text, 0));
  if exists (select 1 from public.chat_messages m where m.author_id = (select auth.uid()) and m.created_at > now() - interval '3 seconds') then
    raise exception 'Please wait a few seconds before sending another message.';
  end if;
  if exists (select 1 from public.chat_messages m where m.author_id = (select auth.uid())
    and lower(regexp_replace(trim(m.body), '\\s+', ' ', 'g')) = normalized_body
    and m.created_at > now() - interval '60 seconds') then
    raise exception 'You already sent that message recently. Please say something new.';
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_chat_message_rate_limit() from public, anon, authenticated;
drop trigger if exists chat_messages_rate_limit on public.chat_messages;
create trigger chat_messages_rate_limit before insert on public.chat_messages
  for each row execute function public.enforce_chat_message_rate_limit();
commit;
