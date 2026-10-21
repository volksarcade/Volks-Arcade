-- Add indexes for uncovered foreign-key columns reported by Supabase's database linter.
-- These keep parent deletes/updates and scoped lookups efficient as the community grows.
create index if not exists challenge_actions_cycle_key_idx on public.challenge_actions (cycle_key);
create index if not exists challenge_progress_cycle_key_idx on public.challenge_progress (cycle_key);
create index if not exists chat_messages_author_id_idx on public.chat_messages (author_id);
create index if not exists chat_messages_deleted_by_idx on public.chat_messages (deleted_by);
create index if not exists chat_messages_pinned_by_idx on public.chat_messages (pinned_by);
create index if not exists chat_rooms_faction_id_idx on public.chat_rooms (faction_id);
create index if not exists community_xp_claims_reviewed_by_idx on public.community_xp_claims (reviewed_by);
create index if not exists faction_applications_faction_id_idx on public.faction_applications (faction_id);
create index if not exists faction_applications_faction_id_rank_key_idx on public.faction_applications (faction_id, rank_key);
create index if not exists faction_applications_reviewed_by_idx on public.faction_applications (reviewed_by);
create index if not exists faction_applications_user_id_idx on public.faction_applications (user_id);
create index if not exists faction_memberships_approved_by_idx on public.faction_memberships (approved_by);
create index if not exists faction_memberships_faction_id_idx on public.faction_memberships (faction_id);
create index if not exists faction_memberships_faction_id_rank_key_idx on public.faction_memberships (faction_id, rank_key);
create index if not exists faction_memberships_user_id_idx on public.faction_memberships (user_id);
create index if not exists moderation_actions_moderator_id_idx on public.moderation_actions (moderator_id);
create index if not exists moderation_actions_user_id_idx on public.moderation_actions (user_id);
create index if not exists moderator_applications_reviewed_by_idx on public.moderator_applications (reviewed_by);
create index if not exists moderator_applications_user_id_idx on public.moderator_applications (user_id);
create index if not exists staff_assignments_assigned_by_idx on public.staff_assignments (assigned_by);
create index if not exists staff_notes_author_id_idx on public.staff_notes (author_id);
create index if not exists staff_notes_updated_by_idx on public.staff_notes (updated_by);
create index if not exists store_purchases_item_id_idx on public.store_purchases (item_id);
create index if not exists support_applications_reviewed_by_idx on public.support_applications (reviewed_by);
create index if not exists support_applications_user_id_idx on public.support_applications (user_id);
