create or replace function public.weekly_xp_leaderboard(result_limit integer default 10)
returns table(username text, weekly_xp bigint, place bigint)
language sql stable security definer set search_path = '' as $$
  select p.username, coalesce(sum(l.amount),0)::bigint as weekly_xp,
         row_number() over (order by coalesce(sum(l.amount),0) desc, p.username asc) as place
  from public.profiles p
  left join public.xp_ledger l on l.user_id=p.id and l.amount>0
    and l.created_at >= (date_trunc('week', (now() at time zone 'UTC')) at time zone 'UTC')
  where p.is_public = true
  group by p.id, p.username
  order by weekly_xp desc, p.username asc
  limit greatest(1, least(coalesce(result_limit, 10), 25));
$$;
revoke all on function public.weekly_xp_leaderboard(integer) from public;
grant execute on function public.weekly_xp_leaderboard(integer) to anon, authenticated;

create or replace function public.can_manage_members()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_assignments s
    where s.user_id=(select auth.uid())
      and (s.role in ('owner','administrator') or
        (s.role='moderator' and (
          s.scopes && array['website','platform-chat']::text[] or
          exists(select 1 from unnest(s.scopes) scope where scope like 'faction:%')
        )))
  );
$$;
revoke all on function public.can_manage_members() from public;
grant execute on function public.can_manage_members() to authenticated;
drop policy if exists profiles_read_self_and_staff on public.profiles;
create policy profiles_read_self_and_staff on public.profiles for select to authenticated
using (id=(select auth.uid()) or public.can_manage_members() or public.is_staff_for('website') or public.is_staff_for('platform-chat') or public.is_staff_for('manage-moderators') or public.is_staff_for('review-claims'));
drop policy if exists moderation_staff_read on public.moderation_actions;
create policy moderation_staff_read on public.moderation_actions for select to authenticated
using (public.can_manage_members() or user_id=(select auth.uid()));

create or replace function public.moderate_member(
  p_user_id uuid,p_action text,p_reason text,p_categories text[] default '{}',p_duration_hours integer default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare action_id uuid;
begin
  if auth.uid() is null or not public.can_manage_members() then raise exception 'You do not have permission to moderate members.' using errcode='42501'; end if;
  if p_user_id is null or p_user_id=auth.uid() then raise exception 'Staff cannot moderate their own account.' using errcode='22023'; end if;
  if exists(select 1 from public.staff_assignments s where s.user_id=p_user_id and s.role in ('owner','administrator')) then raise exception 'Owner and administrator accounts cannot be moderated here.' using errcode='42501'; end if;
  if p_action not in ('warning','suspend','ban','restore') then raise exception 'Unsupported moderation action.' using errcode='22023'; end if;
  if char_length(trim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'Add a reason between 1 and 500 characters.' using errcode='22023'; end if;
  if exists(select 1 from unnest(coalesce(p_categories,'{}')) c where c not in ('chat','premium','arcade','community','platform')) then raise exception 'One or more moderation categories are invalid.' using errcode='22023'; end if;
  if p_action='suspend' and p_duration_hours not in (1,12,72,168) then raise exception 'Choose a supported suspension duration.' using errcode='22023'; end if;
  if not exists(select 1 from auth.users u where u.id=p_user_id) then raise exception 'That player account no longer exists.' using errcode='22023'; end if;
  insert into public.moderation_actions(user_id,moderator_id,action,reason,categories,starts_at,ends_at)
  values(p_user_id,auth.uid(),p_action,trim(p_reason),coalesce(p_categories,'{}'),now(),
    case when p_action='suspend' then now()+make_interval(hours=>p_duration_hours) else null end)
  returning id into action_id;
  return action_id;
end;
$$;
revoke all on function public.moderate_member(uuid,text,text,text[],integer) from public;
grant execute on function public.moderate_member(uuid,text,text,text[],integer) to authenticated;

create or replace function public.can_post_chat_room(target_room text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.can_read_chat_room(target_room) and (public.is_staff_for('platform-chat') or not exists(
    select 1 from public.moderation_actions a
    where a.user_id=(select auth.uid()) and a.action in ('suspend','ban')
      and (a.ends_at is null or a.ends_at>now())
      and (a.action='ban' or cardinality(a.categories)=0 or 'chat'=any(a.categories) or 'platform'=any(a.categories))
      and not exists(select 1 from public.moderation_actions restored
        where restored.user_id=a.user_id and restored.action='restore' and restored.created_at>a.created_at)
  ));
$$;