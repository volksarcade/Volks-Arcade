-- Enable server-replayed Pong results and award XP only for a verified win.
alter table public.verified_arcade_runs
  drop constraint if exists verified_arcade_runs_game_key_check;
alter table public.verified_arcade_runs
  add constraint verified_arcade_runs_game_key_check
  check (game_key = any (array['noughts','ladders','tetris','checkers','chess','dino','flappy-bird','pong']::text[]));

create or replace function public.record_verified_board_run(
  p_run_id uuid,
  p_game_key text,
  p_score bigint,
  p_progression_count integer,
  p_won boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.verified_arcade_runs%rowtype;
  v_ledger_id uuid;
  v_month date := date_trunc('month', timezone('utc', now()))::date;
  v_best bigint;
  v_reward integer := 0;
begin
  if (select auth.role()) <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_run_id is null
    or p_game_key not in ('noughts','ladders','tetris','checkers','chess','dino','pong')
    or p_score is null or p_progression_count is null or p_won is null then
    raise exception 'Invalid verified arcade result';
  end if;

  select * into v_run from public.verified_arcade_runs where id = p_run_id for update;
  if not found or v_run.game_key <> p_game_key then raise exception 'Arcade run not found'; end if;
  if v_run.finished_at is not null then
    return jsonb_build_object('score',v_run.score,'xp_reward',0,'already_counted',true);
  end if;
  if p_score < 0 or p_score > 100000000 or p_progression_count < 1 or p_progression_count > 500 then
    raise exception 'Invalid verified arcade result';
  end if;
  if p_game_key = 'noughts' and (p_progression_count < 3 or v_run.started_at > now()-interval '1500 milliseconds') then raise exception 'Complete a full Noughts & Crosses round first'; end if;
  if p_game_key = 'ladders' and (p_progression_count < 1 or v_run.started_at > now()-interval '4 seconds') then raise exception 'Complete a full Snakes & Ladders match first'; end if;
  if p_game_key = 'tetris' and v_run.started_at > now()-interval '4 seconds' then raise exception 'Complete a Tetris run first'; end if;
  if p_game_key = 'checkers' and (p_progression_count < 5 or v_run.started_at > now()-interval '5 seconds') then raise exception 'Complete a full Checkers match first'; end if;
  if p_game_key = 'chess' and (p_progression_count < 4 or v_run.started_at > now()-interval '4 seconds') then raise exception 'Complete a full Chess match first'; end if;
  if p_game_key = 'dino' and (p_score < 30 or v_run.started_at > now()-interval '5 seconds') then raise exception 'Survive for at least five seconds before submitting Dino Run'; end if;
  if p_game_key = 'pong' and (p_progression_count <> 1 or v_run.started_at > now()-interval '4 seconds') then raise exception 'Complete a full Pong match first'; end if;

  update public.verified_arcade_runs
  set finished_at=now(),score=p_score,progression_count=p_progression_count,won=p_won
  where id=p_run_id;

  if p_game_key = 'noughts' then v_reward := 15;
  elsif p_game_key = 'ladders' and p_won then v_reward := 100;
  elsif p_game_key in ('checkers','chess','pong') and p_won then v_reward := 100;
  elsif p_game_key in ('tetris','dino') then
    select coalesce(sum(round(15*power(1.05::numeric,level_no-1))::integer),15)
    into v_reward from generate_series(1,p_progression_count) as level_no;
  end if;

  if v_reward > 0 then
    insert into public.xp_ledger(user_id,amount,source,reference_id)
    values(v_run.user_id,v_reward,'arcade_game','verified-board:'||p_run_id::text)
    on conflict(user_id,source,reference_id) do nothing returning id into v_ledger_id;
    if v_ledger_id is null then v_reward := 0;
    else
      insert into public.xp_wallets(user_id,lifetime_xp,spendable_xp,updated_at)
      values(v_run.user_id,v_reward,v_reward,now())
      on conflict(user_id) do update
      set lifetime_xp=public.xp_wallets.lifetime_xp+excluded.lifetime_xp,
          spendable_xp=public.xp_wallets.spendable_xp+excluded.spendable_xp,
          updated_at=now();
    end if;
  end if;

  insert into public.arcade_monthly_scores(user_id,game_key,month_start,best_score,updated_at)
  values(v_run.user_id,p_game_key,v_month,p_score,now())
  on conflict(user_id,game_key,month_start) do update
  set best_score=greatest(public.arcade_monthly_scores.best_score,excluded.best_score),updated_at=now();
  select best_score into v_best from public.arcade_monthly_scores
  where user_id=v_run.user_id and game_key=p_game_key and month_start=v_month;
  return jsonb_build_object('score',p_score,'xp_reward',v_reward,'best_score',v_best,'progression_count',p_progression_count,'already_counted',false);
end;
$function$;

revoke all on function public.record_verified_board_run(uuid,text,bigint,integer,boolean) from public, anon, authenticated;
grant execute on function public.record_verified_board_run(uuid,text,bigint,integer,boolean) to service_role;
