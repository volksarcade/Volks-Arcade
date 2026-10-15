create table if not exists public.arcade_monthly_scores (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null check (game_key = any (array['snake','ladders','reaction','tetris','checkers','noughts','chess','pacman','space-invaders','dino','pong','flappy-bird','breakout']::text[])),
  month_start date not null,
  best_score bigint not null check (best_score >= 0 and best_score <= 100000000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, game_key, month_start)
);
alter table public.arcade_monthly_scores enable row level security;
revoke all on table public.arcade_monthly_scores from anon, authenticated;
grant usage on schema public to authenticated;

create or replace function public.submit_monthly_arcade_score(p_game_key text, p_score bigint)
returns public.arcade_monthly_scores
language plpgsql
security definer
set search_path = ''
as $function$
declare result_row public.arcade_monthly_scores;
begin
  if (select auth.uid()) is null then raise exception 'Sign in to save a monthly score'; end if;
  if p_game_key is null or not (p_game_key = any(array['snake','ladders','reaction','tetris','checkers','noughts','chess','pacman','space-invaders','dino','pong','flappy-bird','breakout']::text[])) then raise exception 'Unknown arcade game'; end if;
  if p_score is null or p_score < 0 or p_score > 100000000 then raise exception 'Invalid score'; end if;
  insert into public.arcade_monthly_scores(user_id,game_key,month_start,best_score)
  values((select auth.uid()),p_game_key,date_trunc('month',timezone('utc',now()))::date,p_score)
  on conflict(user_id,game_key,month_start) do update
    set best_score=greatest(public.arcade_monthly_scores.best_score,excluded.best_score),updated_at=now()
  returning * into result_row;
  return result_row;
end;
$function$;
revoke all on function public.submit_monthly_arcade_score(text,bigint) from public, anon;
grant execute on function public.submit_monthly_arcade_score(text,bigint) to authenticated;

create or replace function public.monthly_arcade_leaderboard()
returns table(game_key text, user_id uuid, username text, score bigint, avatar_url text, player_level integer, place bigint)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null then raise exception 'Sign in to view monthly rankings'; end if;
  return query
  with ranked as (
    select s.game_key,s.user_id,p.username,s.best_score,p.avatar_url,
      (select coalesce(w.lifetime_xp,0) from public.xp_wallets w where w.user_id=s.user_id) as lifetime_xp,
      row_number() over(partition by s.game_key order by s.best_score desc,p.username asc) as rn
    from public.arcade_monthly_scores s
    join public.profiles p on p.id=s.user_id and p.is_public
    where s.month_start=date_trunc('month',timezone('utc',now()))::date
  )
  select r.game_key,r.user_id,r.username,r.best_score,r.avatar_url,
    coalesce((select max(t.level_no)::integer from unnest(array[0,100,250,450,700,1000,1350,1750,2200,2700,3250,3500,3650,3800,3925,4025,4125,4250,5000,6000,7000,8000,9000,10000,11000,12000,13000,14000,15000,16000,17500,19000,20500,22000,23500,25000,26500,28000,29500,31000,32500,34000,35500,37000,38500,40000,41500,43000,44500,46000]::bigint[]) with ordinality as t(xp_required,level_no) where t.xp_required<=r.lifetime_xp),1),
    r.rn
  from ranked r where r.rn<=10
  order by r.game_key,r.rn;
end;
$function$;
revoke all on function public.monthly_arcade_leaderboard() from public, anon;
grant execute on function public.monthly_arcade_leaderboard() to authenticated;

create or replace function public.assign_scoped_moderator(p_user_id uuid, p_scopes text[])
returns public.staff_assignments
language plpgsql
security definer
set search_path = ''
as $function$
declare actor public.staff_assignments; target public.staff_assignments; valid_scopes text[] := array['website','platform-chat','discord','tiktok','twitch','kick','staff-notes','review-claims','review-premium','review-community','manage-factions','manage-moderators','faction:house-volkah','faction:ueeif','faction:vampiric-hierarchy']; clean_scopes text[];
begin
  if (select auth.uid()) is null or p_user_id is null then raise exception 'Not authorized'; end if;
  select * into actor from public.staff_assignments where user_id=(select auth.uid());
  if not found or actor.role not in ('owner','administrator','moderator') then raise exception 'Not authorized'; end if;
  select * into target from public.staff_assignments where user_id=p_user_id;
  if target.role in ('owner','administrator') then raise exception 'Owner and administrator roles cannot be changed here'; end if;
  select coalesce(array_agg(distinct s),array[]::text[]) into clean_scopes from unnest(coalesce(p_scopes,array[]::text[])) s;
  if exists(select 1 from unnest(clean_scopes) s where not (s=any(valid_scopes))) then raise exception 'Unknown moderator scope'; end if;
  if actor.role='moderator' and exists(select 1 from unnest(clean_scopes) s where not (s=any(actor.scopes))) then raise exception 'Moderators can only delegate their own access areas'; end if;
  if cardinality(clean_scopes)=0 then
    delete from public.staff_assignments where user_id=p_user_id and role='moderator';
    return null;
  end if;
  insert into public.staff_assignments(user_id,role,scopes,assigned_by)
  values(p_user_id,'moderator',clean_scopes,(select auth.uid()))
  on conflict(user_id) do update set role='moderator',scopes=excluded.scopes,assigned_by=excluded.assigned_by
  where public.staff_assignments.role='moderator'
  returning * into target;
  if target.user_id is null then raise exception 'This member already has another staff role'; end if;
  return target;
end;
$function$;
revoke all on function public.assign_scoped_moderator(uuid,text[]) from public, anon;
grant execute on function public.assign_scoped_moderator(uuid,text[]) to authenticated;

create or replace function public.assign_faction_membership(p_user_id uuid,p_faction_id text,p_rank_key text,p_character_name text)
returns public.faction_memberships
language plpgsql
security definer
set search_path = ''
as $function$
declare result_row public.faction_memberships; allowed_ranks text[];
begin
  if (select auth.uid()) is null or p_user_id is null then raise exception 'Not authorized'; end if;
  if not (public.is_staff_for('manage-factions') or public.is_staff_for('faction:'||p_faction_id)) then raise exception 'Not authorized for this faction'; end if;
  allowed_ranks:=case p_faction_id
    when 'house-volkah' then array['bekk','la-commander','boq-colonel','sa-general','aj-admiral','council','joh']
    when 'ueeif' then array['colonel','major','warrant-officer','sergeant','private','recruit']
    when 'vampiric-hierarchy' then array['vampire-overlord','vampire-council','royal-vampire','vampire-lord','vampire-general','vampire','purebloods']
    else null end;
  if allowed_ranks is null or not (p_rank_key=any(allowed_ranks)) then raise exception 'Unknown faction rank'; end if;
  if nullif(trim(p_character_name),'') is null then raise exception 'Enter the in-game character name'; end if;
  insert into public.faction_memberships(faction_id,user_id,rank_key,character_name,is_leader,approved_by)
  values(p_faction_id,p_user_id,p_rank_key,trim(p_character_name),p_rank_key=any(array['joh','colonel','vampire-overlord']), (select auth.uid()))
  on conflict(faction_id,user_id) do update set rank_key=excluded.rank_key,character_name=excluded.character_name,is_leader=excluded.is_leader,approved_by=excluded.approved_by,joined_at=now()
  returning * into result_row;
  return result_row;
end;
$function$;
revoke all on function public.assign_faction_membership(uuid,text,text,text) from public, anon;
grant execute on function public.assign_faction_membership(uuid,text,text,text) to authenticated;
