-- Enforce that only the site owner or administrators can grant moderator access.
-- Moderators must never gain this authority through a delegated scope.
create or replace function public.is_staff_for(required_scope text default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.staff_assignments s
    where s.user_id = (select auth.uid())
      and (
        s.role in ('owner', 'administrator')
        or (
          s.role = 'moderator'
          and required_scope is distinct from 'manage-moderators'
          and (required_scope is null or required_scope = any(s.scopes))
        )
      )
  );
$function$;

create or replace function public.assign_scoped_moderator(p_user_id uuid, p_scopes text[])
returns public.staff_assignments
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor public.staff_assignments;
  target public.staff_assignments;
  valid_scopes text[] := array[
    'website', 'platform-chat', 'discord', 'tiktok', 'twitch', 'kick',
    'staff-notes', 'review-claims', 'review-premium', 'review-community',
    'manage-factions', 'faction:house-volkah', 'faction:ueeif',
    'faction:vampiric-hierarchy'
  ];
  clean_scopes text[];
begin
  if (select auth.uid()) is null or p_user_id is null then
    raise exception 'Not authorized';
  end if;

  select * into actor
  from public.staff_assignments
  where user_id = (select auth.uid());

  if not found or actor.role not in ('owner', 'administrator') then
    raise exception 'Only the owner or an administrator can manage moderators';
  end if;

  select * into target
  from public.staff_assignments
  where user_id = p_user_id;

  if target.role in ('owner', 'administrator') then
    raise exception 'Owner and administrator roles cannot be changed here';
  end if;

  select coalesce(array_agg(distinct s), array[]::text[])
  into clean_scopes
  from unnest(coalesce(p_scopes, array[]::text[])) s;

  if exists (
    select 1 from unnest(clean_scopes) s where not (s = any(valid_scopes))
  ) then
    raise exception 'Unknown moderator scope';
  end if;

  if cardinality(clean_scopes) = 0 then
    delete from public.staff_assignments
    where user_id = p_user_id and role = 'moderator';
    return null;
  end if;

  insert into public.staff_assignments(user_id, role, scopes, assigned_by)
  values (p_user_id, 'moderator', clean_scopes, (select auth.uid()))
  on conflict(user_id) do update
    set role = 'moderator',
        scopes = excluded.scopes,
        assigned_by = excluded.assigned_by
    where public.staff_assignments.role = 'moderator'
  returning * into target;

  if target.user_id is null then
    raise exception 'This member already has another staff role';
  end if;

  return target;
end;
$function$;
