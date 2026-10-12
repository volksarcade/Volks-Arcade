-- Public profiles can appear in the community directory and recent-join activity.
-- Profiles marked private remain visible only to their owner and authorized staff.
drop policy if exists profiles_read_public on public.profiles;
create policy profiles_read_public
  on public.profiles
  for select
  to anon, authenticated
  using (is_public = true);

-- Visitors only need these fields for the home-page recent-join list.
-- Authenticated staff keep their existing table-level SELECT grant.
grant select (username, created_at, is_public) on table public.profiles to anon;

