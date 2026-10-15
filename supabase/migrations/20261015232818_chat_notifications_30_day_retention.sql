create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

create or replace function public.purge_expired_chat_data()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  delete from public.chat_messages
  where created_at < now() - interval '30 days';
  delete from public.notifications
  where created_at < now() - interval '30 days';
end;
$$;
revoke all on function public.purge_expired_chat_data() from public, anon, authenticated;

do $$
declare existing_job record;
begin
  for existing_job in select jobid from cron.job where jobname = 'va-chat-retention-30-days'
  loop
    perform cron.unschedule(existing_job.jobid);
  end loop;
end;
$$;

select cron.schedule('va-chat-retention-30-days', '15 3 * * *', 'select public.purge_expired_chat_data();');
