CREATE OR REPLACE FUNCTION private.record_arcade_event(p_game_key text, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if p_game_key not in ('snake','ladders','reaction','tetris','checkers','noughts','chess','pacman','space-invaders','dino','pong','flappy-bird','breakout') or p_action not in ('play','complete') then
    raise exception 'Invalid arcade event';
  end if;
  perform public.ensure_current_challenges();

  if p_action='complete' then
    insert into public.xp_ledger(user_id,amount,source,reference_id)
      values((select auth.uid()),15,'arcade_game','round:'||gen_random_uuid()::text)
      returning id into ledger_id;
    if ledger_id is not null then
      update public.xp_wallets set lifetime_xp=lifetime_xp+15,spendable_xp=spendable_xp+15,updated_at=now()
        where user_id=(select auth.uid());
      game_reward := 15;
    end if;
    return jsonb_build_object('reward',game_reward,'game_reward',game_reward,'already_counted',false);
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
$function$


create or replace function public.public_member_directory()
returns table (
  user_id uuid,
  username text,
  bio text,
  favorite_games text[],
  avatar_url text,
  show_online boolean,
  created_at timestamptz,
  lifetime_xp bigint,
  faction_memberships jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.bio, p.favorite_games, p.avatar_url, p.show_online, p.created_at,
         coalesce(w.lifetime_xp, 0)::bigint,
         coalesce((
           select jsonb_agg(jsonb_build_object(
             'faction_id', fm.faction_id,
             'rank_key', fm.rank_key,
             'is_leader', fm.is_leader
           ) order by fm.faction_id)
           from public.faction_memberships fm
           where fm.user_id = p.id
         ), '[]'::jsonb)
  from public.profiles p
  left join public.xp_wallets w on w.user_id = p.id
  where (select auth.uid()) is not null
    and p.is_public = true
  order by p.created_at desc
  limit 100;
$$;
revoke all on function public.public_member_directory() from public, anon;
grant execute on function public.public_member_directory() to authenticated;

create or replace function private.notify_chat_mentions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  mentioned_handle text;
  recipient record;
  sender_name text;
begin
  select p.username into sender_name
  from public.profiles p
  where p.id = new.author_id;

  for mentioned_handle in
    select distinct lower(matches.captures[1])
    from regexp_matches(new.body, '@([[:alnum:]_.-]{2,40})', 'gi') as matches(captures)
  loop
    for recipient in
      select p.id, p.username
      from public.profiles p
      where lower(p.username) = mentioned_handle
        and p.id <> new.author_id
    loop
      insert into public.notifications(user_id,kind,title,body,target_url,dedupe_key)
      values(
        recipient.id,
        'chat_mention',
        'You were mentioned in chat',
        coalesce(sender_name, 'A player') || ' mentioned you in ' || new.room_id || '.',
        '#platform',
        'chat-mention:' || new.id::text
      )
      on conflict (user_id,dedupe_key) where dedupe_key is not null do nothing;
    end loop;
  end loop;
  return new;
end;
$$;
revoke all on function private.notify_chat_mentions() from public, anon, authenticated;
drop trigger if exists chat_messages_notify_mentions on public.chat_messages;
create trigger chat_messages_notify_mentions
after insert on public.chat_messages
for each row execute function private.notify_chat_mentions();

update public.notifications
set title = 'Faction application approved',
    body = 'Your in-game faction rank was verified. +250 XP awarded.'
where kind = 'faction_approved'
  and (title = 'Faction application approved' or body = 'Membership verified. +250 XP');

update storage.buckets set file_size_limit = 2800000 where id = 'va-profile-media';
