-- Keep all staff-role and moderator-scope changes restricted to owner/admin.
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
          and required_scope is distinct from 'manage-staff'
          and (required_scope is null or required_scope = any(s.scopes))
        )
      )
  );
$function$;

alter policy staff_manage_scoped
on public.staff_assignments
using (
  public.is_staff_for('manage-moderators')
  and role <> all (array['owner'::text, 'administrator'::text])
)
with check (
  public.is_staff_for('manage-moderators')
  and role <> all (array['owner'::text, 'administrator'::text])
);
