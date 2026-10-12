insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('va-profile-media', 'Volks Arcade Profile Media', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "VA profile media owner read" on storage.objects;
drop policy if exists "VA profile media purchased upload" on storage.objects;
drop policy if exists "VA profile media purchased update" on storage.objects;
drop policy if exists "VA profile media owner delete" on storage.objects;

create policy "VA profile media owner read"
on storage.objects for select to authenticated
using (bucket_id = 'va-profile-media' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "VA profile media purchased upload"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'va-profile-media'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and split_part(name, '/', 2) ~ '^profile-(logo|banner)\.(jpg|jpeg|png|webp)$'
  and exists (
    select 1 from public.store_purchases p
    where p.user_id = (select auth.uid())
      and p.item_id = case
        when split_part(name, '/', 2) ~ '^profile-logo\.' then 'custom-logo-slot'
        else 'custom-banner-slot'
      end
  )
);

create policy "VA profile media purchased update"
on storage.objects for update to authenticated
using (bucket_id = 'va-profile-media' and (storage.foldername(name))[1] = (select auth.uid()::text))
with check (
  bucket_id = 'va-profile-media'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and split_part(name, '/', 2) ~ '^profile-(logo|banner)\.(jpg|jpeg|png|webp)$'
  and exists (
    select 1 from public.store_purchases p
    where p.user_id = (select auth.uid())
      and p.item_id = case
        when split_part(name, '/', 2) ~ '^profile-logo\.' then 'custom-logo-slot'
        else 'custom-banner-slot'
      end
  )
);

create policy "VA profile media owner delete"
on storage.objects for delete to authenticated
using (bucket_id = 'va-profile-media' and (storage.foldername(name))[1] = (select auth.uid()::text));