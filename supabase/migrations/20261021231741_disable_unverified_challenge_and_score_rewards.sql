revoke all on function public.record_arcade_event(text, text) from public, anon, authenticated;
revoke all on function public.submit_monthly_arcade_score(text, bigint) from public, anon, authenticated;
comment on function public.record_arcade_event(text, text) is 'Execution is disabled for browser users until arcade challenge progress is tied to a server-verified game result.';
comment on function public.submit_monthly_arcade_score(text, bigint) is 'Execution is disabled for browser users because submitted scores are client-reported and not independently verified.';
