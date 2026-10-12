-- Raise the profile-media cap to decimal 2.5 MB.
update storage.buckets set file_size_limit=2500000 where id='va-profile-media';

-- One durable streak row per account. Only the security-definer arcade RPC may change it.
create table if not exists public.player_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0 check (current_streak >= 0),
  best_streak integer not null default 0 check (best_streak >= 0),
  last_active_day date,
  updated_at timestamptz not null default now()
);
alter table public.player_streaks enable row level security;
drop policy if exists player_streaks_read_own on public.player_streaks;
create policy player_streaks_read_own on public.player_streaks for select to authenticated using (user_id=(select auth.uid()));
grant select on public.player_streaks to authenticated;

-- Notification reminders are idempotent for each UTC day.
alter table public.notifications add column if not exists dedupe_key text;
create unique index if not exists notifications_user_dedupe_key
  on public.notifications(user_id,dedupe_key) where dedupe_key is not null;

-- "complete" events award one small, daily-capped reward per game; wins remain unsupported.
alter table public.challenge_actions drop constraint if exists challenge_actions_action_check;
alter table public.challenge_actions add constraint challenge_actions_action_check check (action = any (array['play','win','complete']::text[]));

-- Change this week's old unverified-win mission to a rotating play goal.
do $$
declare monday_utc date := date_trunc('week',now() at time zone 'UTC')::date;
declare games text[] := array['snake','ladders','reaction','tetris','checkers','noughts'];
declare game_index int;
declare week_key text := 'weekly:'||monday_utc;
begin
  game_index := mod(abs(hashtext(monday_utc::text)::bigint),array_length(games,1))+1;
  delete from public.challenge_actions where cycle_key=week_key;
  delete from public.challenge_progress where cycle_key=week_key;
  update public.challenge_cycles
    set title='Play '||games[game_index]||' on five days',game_key=games[game_index],target=5,xp_reward=350
    where cycle_key=week_key;
end $$;

create or replace function public.ensure_current_challenges()
returns void language plpgsql security definer set search_path = '' as $$
declare
  today_utc date := (now() at time zone 'UTC')::date;
  monday_utc date := date_trunc('week',now() at time zone 'UTC')::date;
  games text[] := array['snake','ladders','reaction','tetris','checkers','noughts'];
  game_index int;
  weekly_game_index int;
begin
  game_index := mod(today_utc-date '1970-01-01',array_length(games,1))+1;
  weekly_game_index := mod(abs(hashtext(monday_utc::text)::bigint),array_length(games,1))+1;
  insert into public.challenge_cycles(cycle_key,cadence,title,game_key,target,xp_reward,starts_at,ends_at) values
    ('daily:'||today_utc,'daily','Play '||games[game_index],games[game_index],1,40,today_utc::timestamp at time zone 'UTC',(today_utc+1)::timestamp at time zone 'UTC')
    on conflict(cycle_key) do nothing;
  insert into public.challenge_cycles(cycle_key,cadence,title,game_key,target,xp_reward,starts_at,ends_at) values
    ('weekly:'||monday_utc,'weekly','Play '||games[weekly_game_index]||' on five days',games[weekly_game_index],5,350,monday_utc::timestamp at time zone 'UTC',(monday_utc+7)::timestamp at time zone 'UTC')
    on conflict(cycle_key) do nothing;
end;
$$;
revoke all on function public.ensure_current_challenges() from public,anon;
grant execute on function public.ensure_current_challenges() to authenticated;

create or replace function private.record_arcade_event(p_game_key text,p_action text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  today_utc date := (now() at time zone 'UTC')::date;
  day_cycle text := 'daily:'||(now() at time zone 'UTC')::date;
  week_cycle text := 'weekly:'||date_trunc('week',now() at time zone 'UTC')::date;
  daily_row public.challenge_cycles%rowtype;
  weekly_row public.challenge_cycles%rowtype;
  action_id uuid;
  grant_user uuid;
  ledger_id uuid;
  progress_now int;
  streak_now int := 0;
  streak_bonus int := 0;
  daily_reward int := 0;
  weekly_reward int := 0;
  game_reward int := 0;
begin
  if (select auth.uid()) is null then raise exception 'Sign in required'; end if;
  if p_game_key not in ('snake','ladders','reaction','tetris','checkers','noughts') or p_action not in ('play','complete') then
    raise exception 'Invalid arcade event';
  end if;
  perform public.ensure_current_challenges();

  if p_action='complete' then
    insert into public.challenge_actions(user_id,cycle_key,game_key,action)
      values((select auth.uid()),day_cycle,p_game_key,'complete')
      on conflict(user_id,cycle_key,game_key,action,event_day) do nothing returning id into action_id;
    if action_id is null then return jsonb_build_object('already_counted',true,'reward',0); end if;
    insert into public.xp_ledger(user_id,amount,source,reference_id)
      values((select auth.uid()),15,'arcade_game',today_utc||':'||p_game_key)
      on conflict(user_id,source,reference_id) do nothing returning id into ledger_id;
    if ledger_id is not null then
      update public.xp_wallets set lifetime_xp=lifetime_xp+15,spendable_xp=spendable_xp+15,updated_at=now()
        where user_id=(select auth.uid());
      game_reward := 15;
    end if;
    return jsonb_build_object('reward',game_reward,'game_reward',game_reward,'already_counted',game_reward=0);
  end if;

  select * into daily_row from public.challenge_cycles where cycle_key=day_cycle;
  if daily_row.cycle_key is not null and daily_row.game_key=p_game_key then
    action_id := null;
    insert into public.challenge_actions(user_id,cycle_key,game_key,action)
      values((select auth.uid()),day_cycle,p_game_key,'play')
      on conflict(user_id,cycle_key,game_key,action,event_day) do nothing returning id into action_id;
    if action_id is not null then
      insert into public.challenge_progress(user_id,cycle_key,progress,completed_at)
        values((select auth.uid()),day_cycle,1,case when daily_row.target=1 then now() else null end)
        on conflict(user_id,cycle_key) do update set
          progress=least(daily_row.target,public.challenge_progress.progress+1),
          completed_at=case when public.challenge_progress.progress+1>=daily_row.target then coalesce(public.challenge_progress.completed_at,now()) else public.challenge_progress.completed_at end
        returning progress into progress_now;
      grant_user := null;
      if progress_now>=daily_row.target then
        update public.challenge_progress set reward_issued_at=now()
          where user_id=(select auth.uid()) and cycle_key=day_cycle and reward_issued_at is null
          returning user_id into grant_user;
      end if;
      if grant_user is not null then
        insert into public.player_streaks(user_id,current_streak,best_streak,last_active_day,updated_at)
          values(grant_user,1,1,today_utc,now())
          on conflict(user_id) do update set
            current_streak=case
              when public.player_streaks.last_active_day=today_utc then public.player_streaks.current_streak
              when public.player_streaks.last_active_day=today_utc-1 then public.player_streaks.current_streak+1
              else 1 end,
            best_streak=greatest(public.player_streaks.best_streak,case
              when public.player_streaks.last_active_day=today_utc then public.player_streaks.current_streak
              when public.player_streaks.last_active_day=today_utc-1 then public.player_streaks.current_streak+1
              else 1 end),
            last_active_day=today_utc,updated_at=now()
          returning current_streak into streak_now;
        streak_bonus := least(streak_now*5,50);
        insert into public.xp_ledger(user_id,amount,source,reference_id)
          values(grant_user,daily_row.xp_reward,'challenge',day_cycle)
          on conflict(user_id,source,reference_id) do nothing returning id into ledger_id;
        if ledger_id is not null then
          update public.xp_wallets set lifetime_xp=lifetime_xp+daily_row.xp_reward,spendable_xp=spendable_xp+daily_row.xp_reward,updated_at=now()
            where user_id=grant_user;
          daily_reward := daily_row.xp_reward;
        end if;
        if streak_bonus>0 then
          insert into public.xp_ledger(user_id,amount,source,reference_id)
            values(grant_user,streak_bonus,'daily_streak',day_cycle)
            on conflict(user_id,source,reference_id) do nothing returning id into ledger_id;
          if ledger_id is not null then
            update public.xp_wallets set lifetime_xp=lifetime_xp+streak_bonus,spendable_xp=spendable_xp+streak_bonus,updated_at=now()
              where user_id=grant_user;
          else streak_bonus := 0;
          end if;
        end if;
        update public.notifications set read_at=now()
          where user_id=grant_user and dedupe_key='streak-reminder:'||today_utc and read_at is null;
      end if;
    end if;
  end if;

  select * into weekly_row from public.challenge_cycles where cycle_key=week_cycle;
  if weekly_row.cycle_key is not null and weekly_row.game_key=p_game_key then
    action_id := null;
    insert into public.challenge_actions(user_id,cycle_key,game_key,action)
      values((select auth.uid()),week_cycle,p_game_key,'play')
      on conflict(user_id,cycle_key,game_key,action,event_day) do nothing returning id into action_id;
    if action_id is not null then
      insert into public.challenge_progress(user_id,cycle_key,progress,completed_at)
        values((select auth.uid()),week_cycle,1,case when weekly_row.target=1 then now() else null end)
        on conflict(user_id,cycle_key) do update set
          progress=least(weekly_row.target,public.challenge_progress.progress+1),
          completed_at=case when public.challenge_progress.progress+1>=weekly_row.target then coalesce(public.challenge_progress.completed_at,now()) else public.challenge_progress.completed_at end
        returning progress into progress_now;
      grant_user := null;
      if progress_now>=weekly_row.target then
        update public.challenge_progress set reward_issued_at=now()
          where user_id=(select auth.uid()) and cycle_key=week_cycle and reward_issued_at is null
          returning user_id into grant_user;
      end if;
      if grant_user is not null then
        insert into public.xp_ledger(user_id,amount,source,reference_id)
          values(grant_user,weekly_row.xp_reward,'weekly_arcade',week_cycle)
          on conflict(user_id,source,reference_id) do nothing returning id into ledger_id;
        if ledger_id is not null then
          update public.xp_wallets set lifetime_xp=lifetime_xp+weekly_row.xp_reward,spendable_xp=spendable_xp+weekly_row.xp_reward,updated_at=now()
            where user_id=grant_user;
          weekly_reward := weekly_row.xp_reward;
        end if;
      end if;
    end if;
  end if;

  return jsonb_build_object('reward',daily_reward+weekly_reward,'daily_reward',daily_reward,'weekly_reward',weekly_reward,
    'streak_bonus',streak_bonus,'current_streak',coalesce(streak_now,0));
end;
$$;
revoke all on function private.record_arcade_event(text,text) from public,anon;
grant execute on function private.record_arcade_event(text,text) to authenticated;

create or replace function public.check_daily_streak_reminder()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  today_utc date := (now() at time zone 'UTC')::date;
  streak_row public.player_streaks%rowtype;
  effective_streak int := 0;
  reminder_id uuid;
begin
  if uid is null then raise exception 'Sign in required'; end if;
  select * into streak_row from public.player_streaks where user_id=uid;
  if not found then
    return jsonb_build_object('current_streak',0,'best_streak',0,'last_active_day',null,'reminder_created',false);
  end if;
  if streak_row.last_active_day>=today_utc-1 then effective_streak:=streak_row.current_streak; end if;
  if streak_row.current_streak>0 and streak_row.last_active_day=today_utc-1
    and (now() at time zone 'UTC')::time>=time '21:00' then
    insert into public.notifications(user_id,kind,title,body,target_url,dedupe_key)
      values(uid,'streak_reminder','Daily streak nearly expired',
        'Your '||streak_row.current_streak||'-day streak is at risk. Play today’s featured game before midnight UTC to keep it.',
        '#community','streak-reminder:'||today_utc)
      on conflict(user_id,dedupe_key) where dedupe_key is not null do nothing
      returning id into reminder_id;
  end if;
  return jsonb_build_object('current_streak',effective_streak,'best_streak',streak_row.best_streak,
    'last_active_day',streak_row.last_active_day,'reminder_created',reminder_id is not null,
    'at_risk',streak_row.last_active_day=today_utc-1 and effective_streak>0);
end;
$$;
revoke all on function public.check_daily_streak_reminder() from public,anon;
grant execute on function public.check_daily_streak_reminder() to authenticated;