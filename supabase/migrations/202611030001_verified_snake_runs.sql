create table if not exists public.arcade_snake_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  seed bigint not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  score integer,
  step_count integer,
  constraint arcade_snake_runs_score_check check (score is null or (score >= 0 and score <= 3120 and score % 10 = 0)),
  constraint arcade_snake_runs_step_count_check check (step_count is null or (step_count >= 0 and step_count <= 5000))
);

create index if not exists arcade_snake_runs_user_started_idx
  on public.arcade_snake_runs(user_id, started_at desc);

alter table public.arcade_snake_runs enable row level security;
revoke all on table public.arcade_snake_runs from public, anon, authenticated;
grant all on table public.arcade_snake_runs to service_role;

create or replace function public.record_verified_snake_run(
  p_run_id uuid,
  p_score integer,
  p_step_count integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.arcade_snake_runs%rowtype;
  v_ledger_id uuid;
  v_month date := date_trunc('month', timezone('utc', now()))::date;
  v_best bigint;
  v_xp integer := 0;
begin
  if (select auth.role()) <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_run_id is null or p_score is null or p_step_count is null then
    raise exception 'Invalid Snake result';
  end if;

  select * into v_run
  from public.arcade_snake_runs
  where id = p_run_id
  for update;

  if not found then raise exception 'Snake run not found'; end if;
  if v_run.finished_at is not null then
    return jsonb_build_object('score', v_run.score, 'xp_reward', 0, 'already_counted', true);
  end if;
  if p_score < 0 or p_score > 3120 or p_score % 10 <> 0
     or p_step_count < 25 or p_step_count > 5000
     or v_run.started_at > now() - interval '4 seconds' then
    raise exception 'Snake run did not meet completion requirements';
  end if;

  update public.arcade_snake_runs
  set finished_at = now(), score = p_score, step_count = p_step_count
  where id = p_run_id;

  insert into public.xp_ledger(user_id, amount, source, reference_id)
  values (v_run.user_id, 15, 'arcade_game', 'snake-run:' || p_run_id::text)
  on conflict (user_id, source, reference_id) do nothing
  returning id into v_ledger_id;

  if v_ledger_id is not null then
    insert into public.xp_wallets(user_id, lifetime_xp, spendable_xp, updated_at)
    values (v_run.user_id, 15, 15, now())
    on conflict (user_id) do update set
      lifetime_xp = public.xp_wallets.lifetime_xp + 15,
      spendable_xp = public.xp_wallets.spendable_xp + 15,
      updated_at = now();
    v_xp := 15;
  end if;

  insert into public.arcade_monthly_scores(user_id, game_key, month_start, best_score, updated_at)
  values (v_run.user_id, 'snake', v_month, p_score, now())
  on conflict (user_id, game_key, month_start) do update
    set best_score = greatest(public.arcade_monthly_scores.best_score, excluded.best_score),
        updated_at = now();

  select best_score into v_best
  from public.arcade_monthly_scores
  where user_id = v_run.user_id and game_key = 'snake' and month_start = v_month;

  return jsonb_build_object('score', p_score, 'xp_reward', v_xp, 'best_score', v_best, 'already_counted', false);
end;
$function$;

revoke all on function public.record_verified_snake_run(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.record_verified_snake_run(uuid, integer, integer) to service_role;

create or replace function public.purge_expired_chat_data()
returns void
language plpgsql
security definer
set search_path = 'pg_catalog', 'public'
as $cleanup$
begin
  delete from public.chat_messages where created_at < now() - interval '30 days';
  delete from public.notifications where created_at < now() - interval '30 days';
  delete from public.arcade_snake_runs where started_at < now() - interval '30 days';
end;
$cleanup$;
