-- Keep only the daily play reward live until match outcomes are verified server-side.
create or replace function private.record_arcade_event(p_game_key text,p_action text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare day_cycle text; target_cycle text; action_id uuid; grant_user uuid; event_row public.challenge_cycles%rowtype; progress_now int; out_json jsonb := '{}'::jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Sign in required'; end if;
  if p_game_key not in ('snake','ladders','reaction','tetris','checkers','noughts') then raise exception 'Invalid arcade game'; end if;
  if p_action <> 'play' then raise exception 'Verified win rewards are coming soon'; end if;
  perform public.ensure_current_challenges();
  day_cycle := 'daily:'||(now() at time zone 'UTC')::date;
  select cycle_key into target_cycle from public.challenge_cycles where cycle_key=day_cycle and game_key=p_game_key;
  if target_cycle is null then return out_json; end if;
  insert into public.challenge_actions(user_id,cycle_key,game_key,action) values((select auth.uid()),target_cycle,p_game_key,p_action)
    on conflict(user_id,cycle_key,game_key,action,event_day) do nothing returning id into action_id;
  if action_id is null then return jsonb_build_object('already_counted',true); end if;
  select * into event_row from public.challenge_cycles where cycle_key=target_cycle;
  insert into public.challenge_progress(user_id,cycle_key,progress,completed_at)
    values((select auth.uid()),target_cycle,1,case when event_row.target=1 then now() else null end)
    on conflict(user_id,cycle_key) do update set progress=least(event_row.target,public.challenge_progress.progress+1),
      completed_at=case when public.challenge_progress.progress+1>=event_row.target then coalesce(public.challenge_progress.completed_at,now()) else public.challenge_progress.completed_at end;
  update public.challenge_progress set reward_issued_at=now() where user_id=(select auth.uid()) and cycle_key=target_cycle
    and progress>=event_row.target and reward_issued_at is null returning user_id into grant_user;
  if grant_user is not null then
    insert into public.xp_ledger(user_id,amount,source,reference_id) values(grant_user,event_row.xp_reward,'challenge',target_cycle) on conflict(user_id,source,reference_id) do nothing returning id into action_id;
    if action_id is not null then update public.xp_wallets set lifetime_xp=lifetime_xp+event_row.xp_reward,spendable_xp=spendable_xp+event_row.xp_reward,updated_at=now() where user_id=grant_user; end if;
  end if;
  select progress into progress_now from public.challenge_progress where user_id=(select auth.uid()) and cycle_key=target_cycle;
  return jsonb_build_object('cycle',target_cycle,'progress',progress_now,'target',event_row.target,'reward',case when grant_user is null then 0 else event_row.xp_reward end);
end;
$$;
revoke all on function private.record_arcade_event(text,text) from public,anon;
grant execute on function private.record_arcade_event(text,text) to authenticated;