-- Payment events contain provider callbacks and payment identifiers. Browser roles must not have any direct table privileges.
-- The payment Edge Function uses server-side credentials and the table remains protected by RLS.
revoke all privileges on table public.payment_events from anon, authenticated;
