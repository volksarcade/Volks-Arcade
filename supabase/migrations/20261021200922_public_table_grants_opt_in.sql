-- Stop automatic Data API grants on future public tables created by postgres.
-- Existing table grants are unchanged. Every future table migration must enable RLS,
-- add its policies, and explicitly grant only the operations each client role needs.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
