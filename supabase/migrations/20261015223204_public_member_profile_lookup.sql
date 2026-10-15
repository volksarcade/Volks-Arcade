create or replace function public.public_member_profile(p_user_id uuid)
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
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in to view player profiles';
  end if;

  return query
    select p.id as user_id, p.username, p.bio, p.favorite_games, p.avatar_url,
      p.show_online, p.created_at, coalesce(w.lifetime_xp, 0)::bigint as lifetime_xp,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'faction_id', fm.faction_id,
          'rank_key', fm.rank_key,
          'is_leader', fm.is_leader
        ) order by fm.faction_id)
        from public.faction_memberships as fm
        where fm.user_id = p.id
      ), '[]'::jsonb) as faction_memberships
    from public.profiles as p
    left join public.xp_wallets as w on w.user_id = p.id
    where p.id = p_user_id and p.is_public is true;
end;
$$;

revoke all on function public.public_member_profile(uuid) from public, anon;
grant execute on function public.public_member_profile(uuid) to authenticated;