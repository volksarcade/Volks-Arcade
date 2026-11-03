alter table public.verified_arcade_runs drop constraint if exists verified_arcade_runs_game_key_check;
alter table public.verified_arcade_runs add constraint verified_arcade_runs_game_key_check
check (game_key = any (array['noughts','ladders','tetris','checkers','chess','dino','flappy-bird']::text[]));

create or replace function public.record_verified_flappy_run(p_run_id uuid,p_score bigint,p_progression_count integer)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_run public.verified_arcade_runs%rowtype; v_ledger_id uuid; v_month date:=date_trunc('month',timezone('utc',now()))::date; v_best bigint; v_reward integer:=15;
begin
  if (select auth.role())<>'service_role' then raise exception 'Service role required'; end if;
  if p_run_id is null or p_score is null or p_progression_count is null then raise exception 'Invalid verified Flappy Bird result'; end if;
  select * into v_run from public.verified_arcade_runs where id=p_run_id for update;
  if not found or v_run.game_key<>'flappy-bird' then raise exception 'Arcade run not found'; end if;
  if v_run.finished_at is not null then return jsonb_build_object('score',v_run.score,'xp_reward',0,'already_counted',true); end if;
  if p_score<1 or p_score>100000000 or p_progression_count<1 or p_progression_count>500 or p_score<>p_progression_count then raise exception 'Pass at least one pipe in Flappy Bird before submitting a score'; end if;
  if v_run.started_at>now()-interval '3 seconds' then raise exception 'Play Flappy Bird for at least three seconds before submitting the result'; end if;
  update public.verified_arcade_runs set finished_at=now(),score=p_score,progression_count=p_progression_count,won=false where id=p_run_id;
  insert into public.xp_ledger(user_id,amount,source,reference_id) values(v_run.user_id,v_reward,'arcade_game','verified-flappy:'||p_run_id::text) on conflict(user_id,source,reference_id) do nothing returning id into v_ledger_id;
  if v_ledger_id is null then v_reward:=0;
  else insert into public.xp_wallets(user_id,lifetime_xp,spendable_xp,updated_at) values(v_run.user_id,v_reward,v_reward,now())
    on conflict(user_id) do update set lifetime_xp=public.xp_wallets.lifetime_xp+excluded.lifetime_xp,spendable_xp=public.xp_wallets.spendable_xp+excluded.spendable_xp,updated_at=now();
  end if;
  insert into public.arcade_monthly_scores(user_id,game_key,month_start,best_score,updated_at) values(v_run.user_id,'flappy-bird',v_month,p_score,now())
    on conflict(user_id,game_key,month_start) do update set best_score=greatest(public.arcade_monthly_scores.best_score,excluded.best_score),updated_at=now();
  select best_score into v_best from public.arcade_monthly_scores where user_id=v_run.user_id and game_key='flappy-bird' and month_start=v_month;
  return jsonb_build_object('score',p_score,'xp_reward',v_reward,'best_score',v_best,'progression_count',p_progression_count,'already_counted',false);
end;
$function$;
revoke all on function public.record_verified_flappy_run(uuid,bigint,integer) from public,anon,authenticated;
grant execute on function public.record_verified_flappy_run(uuid,bigint,integer) to service_role;