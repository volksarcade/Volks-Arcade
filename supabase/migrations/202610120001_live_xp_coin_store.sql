-- Server-authoritative VA Coin exchange and store purchases.
-- Public wrappers are SECURITY INVOKER; privileged transaction bodies live in
-- the non-API private schema and validate auth.uid() on every request.

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

insert into public.store_items(id,name,item_type,price_coins,minimum_level,is_active) values
  ('custom-logo-slot','Custom profile logo slot','unlock',150,5,true),
  ('crimson-frame','Crimson Profile Frame','frame',90,5,true),
  ('custom-banner-slot','Custom banner upload slot','unlock',300,10,true),
  ('arcade-regular-badge','Arcade Regular Badge','badge',200,10,true),
  ('neon-banner','Neon Signal Banner','banner',300,12,true),
  ('faction-insignia','Faction Insignia','badge',400,15,true),
  ('champion-title','Champion Title','title',600,20,true),
  ('legendary-effect','Legendary Profile Effect','effect',950,30,true)
on conflict(id) do update set name=excluded.name,item_type=excluded.item_type,
  price_coins=excluded.price_coins,minimum_level=excluded.minimum_level,is_active=true;

-- Allow a player to count a genuine win in the same game once on each UTC day.
alter table public.challenge_actions add column if not exists event_day date not null default ((now() at time zone 'UTC')::date);
update public.challenge_actions set event_day=(created_at at time zone 'UTC')::date;
alter table public.challenge_actions drop constraint if exists challenge_actions_user_id_cycle_key_game_key_action_key;
create unique index if not exists challenge_actions_daily_unique on public.challenge_actions(user_id,cycle_key,game_key,action,event_day);

create or replace function private.record_arcade_event(p_game_key text,p_action text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare day_cycle text; week_cycle text; target_cycle text; action_id uuid; grant_user uuid; event_row public.challenge_cycles%rowtype; progress_now int; out_json jsonb := '{}'::jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Sign in required'; end if;
  if p_game_key not in ('snake','ladders','reaction','tetris','checkers','noughts') or p_action not in ('play','win') then raise exception 'Invalid arcade event'; end if;
  perform public.ensure_current_challenges();
  day_cycle := 'daily:'||(now() at time zone 'UTC')::date;
  week_cycle := 'weekly:'||date_trunc('week',now() at time zone 'UTC')::date;
  if p_action='play' then select cycle_key into target_cycle from public.challenge_cycles where cycle_key=day_cycle and game_key=p_game_key;
  elsif p_game_key in ('ladders','checkers','noughts') then target_cycle := week_cycle; end if;
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
create or replace function public.record_arcade_event(p_game_key text,p_action text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.record_arcade_event(p_game_key,p_action);
$$;
revoke all on function public.record_arcade_event(text,text) from public,anon;
grant execute on function public.record_arcade_event(text,text) to authenticated;

create or replace function private.va_level_for_xp(p_xp bigint)
returns integer language sql immutable security invoker set search_path = '' as $$
  select coalesce(max(level::int),1)
  from unnest(array[0,100,250,450,700,1000,1350,1750,2200,2700,3250,3500,3650,3800,3925,4025,4125,4250,5000,6000,7000,8000,9000,10000,11000,12000,13000,14000,15000,16000,17500,19000,20500,22000,23500,25000,26500,28000,29500,31000,32500,34000,35500,37000,38500,40000,41500,43000,44500,46000]::bigint[]) with ordinality as t(threshold,level)
  where threshold <= greatest(p_xp,0);
$$;

create or replace function private.exchange_spendable_xp(p_xp bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); coin_amount bigint; old_balance public.xp_wallets%rowtype;
begin
  if uid is null then raise exception 'Sign in required'; end if;
  coin_amount := case p_xp when 250 then 50 when 1000 then 225 when 2500 then 600 else null end;
  if coin_amount is null or p_request_id is null then raise exception 'Choose one of the listed XP exchange packs'; end if;
  select * into old_balance from public.xp_wallets where user_id=uid for update;
  if not found then raise exception 'Wallet not found'; end if;
  if exists(select 1 from public.xp_ledger where user_id=uid and source='exchange' and reference_id=p_request_id::text) then
    return jsonb_build_object('already_processed',true,'spendable_xp',old_balance.spendable_xp,'va_coins',old_balance.va_coins);
  end if;
  if old_balance.spendable_xp < p_xp then raise exception 'Not enough spendable XP'; end if;
  update public.xp_wallets set spendable_xp=spendable_xp-p_xp,va_coins=va_coins+coin_amount,updated_at=now() where user_id=uid
    returning * into old_balance;
  insert into public.xp_ledger(user_id,amount,source,reference_id) values(uid,-p_xp,'exchange',p_request_id::text);
  insert into public.store_coin_ledger(user_id,amount,source,reference_id) values(uid,coin_amount,'xp-exchange',p_request_id::text);
  return jsonb_build_object('already_processed',false,'spent_xp',p_xp,'earned_coins',coin_amount,'spendable_xp',old_balance.spendable_xp,'va_coins',old_balance.va_coins);
end;
$$;
revoke all on function private.exchange_spendable_xp(bigint,uuid) from public,anon;
grant execute on function private.exchange_spendable_xp(bigint,uuid) to authenticated;

create or replace function public.exchange_spendable_xp(p_xp bigint,p_request_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.exchange_spendable_xp(p_xp,p_request_id);
$$;
revoke all on function public.exchange_spendable_xp(bigint,uuid) from public,anon;
grant execute on function public.exchange_spendable_xp(bigint,uuid) to authenticated;

create or replace function private.purchase_store_item(p_item_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); item public.store_items%rowtype; wallet public.xp_wallets%rowtype;
begin
  if uid is null then raise exception 'Sign in required'; end if;
  if p_item_id is null or char_length(p_item_id)>80 then raise exception 'Invalid store item'; end if;
  select * into item from public.store_items where id=p_item_id and is_active for share;
  if not found then raise exception 'This reward is unavailable'; end if;
  select * into wallet from public.xp_wallets where user_id=uid for update;
  if not found then raise exception 'Wallet not found'; end if;
  if exists(select 1 from public.store_purchases where user_id=uid and item_id=item.id) then raise exception 'This reward is already owned'; end if;
  if private.va_level_for_xp(wallet.lifetime_xp)<item.minimum_level then raise exception 'Reach the required level first'; end if;
  if wallet.va_coins<item.price_coins then raise exception 'Not enough VA Coins'; end if;
  update public.xp_wallets set va_coins=va_coins-item.price_coins,updated_at=now() where user_id=uid returning * into wallet;
  insert into public.store_purchases(user_id,item_id,price_coins) values(uid,item.id,item.price_coins);
  insert into public.store_coin_ledger(user_id,amount,source,reference_id) values(uid,-item.price_coins,'store-purchase',item.id);
  return jsonb_build_object('item_id',item.id,'price_coins',item.price_coins,'va_coins',wallet.va_coins,'spendable_xp',wallet.spendable_xp);
end;
$$;
revoke all on function private.purchase_store_item(text) from public,anon;
grant execute on function private.purchase_store_item(text) to authenticated;

create or replace function public.purchase_store_item(p_item_id text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.purchase_store_item(p_item_id);
$$;
revoke all on function public.purchase_store_item(text) from public,anon;
grant execute on function public.purchase_store_item(text) to authenticated;

