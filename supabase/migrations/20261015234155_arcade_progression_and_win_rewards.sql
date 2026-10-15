create or replace function public.record_arcade_event(p_game_key text, p_action text)
returns jsonb
language plpgsql
set search_path = pg_catalog, public, private
as $$
begin
  if p_action = 'complete' then
    raise exception 'Use the run completion endpoint to record a game result.';
  end if;
  if p_action <> 'play' then
    raise exception 'Invalid arcade event.';
  end if;
  return private.record_arcade_event(p_game_key, p_action);
end;
$$;

create or replace function public.record_arcade_completion(
  p_game_key text,
  p_progression_count integer,
  p_won boolean,
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  uid uuid := (select auth.uid());
  stage_count integer := greatest(1, least(coalesce(p_progression_count, 1), 50));
  reward integer := 15;
  ledger_id uuid;
  progression_games text[] := array['tetris','space-invaders'];
  winning_games text[] := array['ladders','checkers','chess','pacman','pong','breakout'];
begin
  if uid is null then raise exception 'Sign in required'; end if;
  if p_game_key not in ('snake','ladders','reaction','tetris','checkers','noughts','chess','pacman','space-invaders','dino','pong','flappy-bird','breakout')
     or p_run_id is null or p_progression_count is null or p_progression_count < 1 then
    raise exception 'Invalid game result';
  end if;

  if p_game_key = any(progression_games) then
    select coalesce(sum(round(15 * power(1.05::numeric, level_no - 1))::integer), 15)
      into reward
      from generate_series(1, stage_count) as level_no;
  elsif coalesce(p_won, false) and p_game_key = any(winning_games) then
    reward := 100;
  end if;

  insert into public.xp_ledger(user_id, amount, source, reference_id)
    values(uid, reward, 'arcade_game', 'run:' || p_run_id::text)
    on conflict(user_id, source, reference_id) do nothing
    returning id into ledger_id;

  if ledger_id is not null then
    update public.xp_wallets
      set lifetime_xp = lifetime_xp + reward,
          spendable_xp = spendable_xp + reward,
          updated_at = now()
      where user_id = uid;
    return jsonb_build_object('game_reward', reward, 'already_counted', false, 'progression_count', stage_count);
  end if;

  return jsonb_build_object('game_reward', 0, 'already_counted', true, 'progression_count', stage_count);
end;
$$;
revoke all on function public.record_arcade_completion(text, integer, boolean, uuid) from public, anon;
grant execute on function public.record_arcade_completion(text, integer, boolean, uuid) to authenticated;