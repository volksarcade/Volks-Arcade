-- Staff can update note status and audit fields, but cannot rewrite another
-- moderator's note text or move its author record through the Data API.
revoke update on public.staff_notes from authenticated;
grant update(state,updated_by,updated_at) on public.staff_notes to authenticated;

