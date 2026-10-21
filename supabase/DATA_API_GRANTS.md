# Supabase Data API grants

Supabase's October 30, 2026 change stops automatically granting Data API access to new tables in the `public` schema. Volks Arcade has opted into this safer behavior early.

The migrations `20261021200922_public_table_grants_opt_in.sql` and `20261021200942_public_function_sequence_grants_opt_in.sql` remove default API access for future objects created by the `postgres` role. They do not change grants on existing tables, functions, or sequences.

When adding a future table:

1. Enable row-level security.
2. Add policies for the intended users and operations.
3. Explicitly grant only the required privileges to `anon`, `authenticated`, and/or `service_role`.
4. If a table uses a sequence, grant sequence access only when required.
5. For RPC functions, explicitly grant `EXECUTE` only to the roles that should call them.

Example for a private account-owned table:

```sql
alter table public.example enable row level security;
create policy example_read_own on public.example
  for select to authenticated using (user_id = (select auth.uid()));
grant select on table public.example to authenticated;
```

Add grants in the same migration as the table, its RLS policies, and any RPCs. Do not grant every privilege to every API role by default. RLS filters rows, while grants decide whether a role can reach an object at all.
