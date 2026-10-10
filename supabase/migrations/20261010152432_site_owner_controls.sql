create table public.site_config (
  config_key text primary key check (config_key = 'main'),
  settings jsonb not null default '{}'::jsonb check (jsonb_typeof(settings) = 'object'),
  updated_at timestamptz not null default now()
);

alter table public.site_config enable row level security;
grant select on public.site_config to anon, authenticated;
grant update on public.site_config to authenticated;

create policy "Public can read site settings"
  on public.site_config for select
  to anon, authenticated
  using (true);

create policy "Only site owner can update site settings"
  on public.site_config for update
  to authenticated
  using ((select public.is_site_owner()))
  with check ((select public.is_site_owner()));

insert into public.site_config (config_key, settings)
values ('main', jsonb_build_object(
  'status', 'online',
  'statusMessage', '',
  'maintenance', jsonb_build_object(),
  'broadcasts', jsonb_build_object(),
  'featuredVideos', jsonb_build_array()
));

