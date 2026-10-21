(() => {
  const config = window.VOLKS_ARCADE_BACKEND;
  if (!config?.enabled || !config.supabaseUrl || !config.publishableKey) return;

  window.VABackendReady = (async () => {
    const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');
    const client = createClient(config.supabaseUrl, config.publishableKey, {
      auth: { flowType: 'pkce', autoRefreshToken: true, persistSession: true, detectSessionInUrl: true }
    });
    const unwrap = result => {
      if (result.error) throw result.error;
      return result.data;
    };
    const api = {
      client,
      async signUp(email, password, displayName) {
        return unwrap(await client.auth.signUp({ email, password, options: { data: { display_name: displayName, profile_complete: true }, emailRedirectTo: `${window.location.origin}${window.location.pathname}` } }));
      },
      async signIn(email, password) {
        return unwrap(await client.auth.signInWithPassword({ email, password }));
      },
      async signInWithGoogle() {
        return unwrap(await client.auth.signInWithOAuth({
          provider: 'google',
          options: { redirectTo: new URL(window.location.pathname, window.location.origin).href, queryParams: { prompt: 'select_account' } }
        }));
      },
      async resendSignupConfirmation(email) {
        return unwrap(await client.auth.resend({
          type: 'signup',
          email,
          options: { emailRedirectTo: `${window.location.origin}${window.location.pathname}` }
        }));
      },
      async signOut() { return unwrap(await client.auth.signOut()); },
      async session() { return unwrap(await client.auth.getSession()); },
      async currentUser() { return unwrap(await client.auth.getUser()); },
      async completeGoogleProfile(displayName) {
        return unwrap(await client.auth.updateUser({ data: { display_name: displayName, profile_complete: true } }));
      },
      async profile(userId) {
        const result = await client.from('profiles').select('id,username,bio,favorite_games,social_links,avatar_url,banner_url,is_public,show_online').eq('id', userId).single();
        return unwrap(result);
      },
      async weeklyXpLeaderboard(limit = 10) {
        return unwrap(await client.rpc('weekly_xp_leaderboard', { result_limit: Math.max(1, Math.min(25, Number(limit) || 10)) }));
      },
      async moderationActions() {
        return unwrap(await client.from('moderation_actions').select('id,user_id,moderator_id,action,reason,categories,starts_at,ends_at,created_at').order('created_at', { ascending:false }).limit(250));
      },
      async moderateMember(userId, action, reason, categories = [], durationHours = null) {
        return unwrap(await client.rpc('moderate_member', { p_user_id:userId, p_action:action, p_reason:reason, p_categories:categories, p_duration_hours:durationHours }));
      },
      async recentSignups(limit = 3) {
        return unwrap(await client.from('profiles').select('username,created_at,is_public').eq('is_public', true).order('created_at', { ascending: false }).limit(Math.max(1, Math.min(10, Number(limit) || 3))));
      },
      async memberDirectory() {
        return unwrap(await client.rpc('public_member_directory'));
      },
      async publicMemberProfile(userId) {
        const rows=unwrap(await client.rpc('public_member_profile', { p_user_id:userId }));
        return Array.isArray(rows)?(rows[0]||null):rows;
      },
      async publicMemberProfileByUsername(username) {
        const rows=unwrap(await client.rpc('public_member_profile_by_username', { p_username:username }));
        return Array.isArray(rows)?(rows[0]||null):rows;
      },
      async memberFactionMemberships(userIds) {
        if (!userIds.length) return [];
        return unwrap(await client.from('faction_memberships').select('user_id,faction_id,rank_key,character_name').in('user_id', userIds));
      },
      async memberProgress(userIds) {
        if (!userIds.length) return [];
        return unwrap(await client.from('xp_wallets').select('user_id,lifetime_xp').in('user_id', userIds));
      },
      async wallet(userId) {
        const result = await client.from('xp_wallets').select('lifetime_xp,spendable_xp,va_coins').eq('user_id', userId).maybeSingle();
        return unwrap(result);
      },
      async coinLedger(userId) {
        return unwrap(await client.from('store_coin_ledger').select('amount,source,created_at').eq('user_id', userId).order('created_at', { ascending: false }).limit(12));
      },
      async ownedStoreItems(userId) {
        return unwrap(await client.from('store_purchases').select('item_id,price_coins,created_at').eq('user_id', userId).order('created_at'));
      },
      async purchaseStoreItem(itemId) {
        return unwrap(await client.rpc('purchase_store_item', { p_item_id: itemId }));
      },
      async exchangeXp(xp, requestId) {
        return unwrap(await client.rpc('exchange_spendable_xp', { p_xp: xp, p_request_id: requestId }));
      },
      async challengeProgress(userId) {
        return unwrap(await client.from('challenge_progress').select('cycle_key,progress,completed_at,reward_issued_at').eq('user_id', userId));
      },
      async checkDailyStreakReminder() { return unwrap(await client.rpc('check_daily_streak_reminder')); },
      async notifications(userId) {
        return unwrap(await client.from('notifications').select('id,kind,title,body,target_url,read_at,created_at').eq('user_id',userId).order('created_at',{ascending:false}).limit(25));
      },
      async markNotificationsRead(userId) {
        return unwrap(await client.from('notifications').update({read_at:new Date().toISOString()}).eq('user_id',userId).is('read_at',null));
      },
      async deleteNotification(notificationId, userId) {
        return unwrap(await client.from('notifications').delete().eq('id',notificationId).eq('user_id',userId));
      },
      async clearNotifications(userId) {
        return unwrap(await client.from('notifications').delete().eq('user_id',userId));
      },
      async staffAssignment(userId) {
        const result = await client.from('staff_assignments').select('role,scopes').eq('user_id', userId).maybeSingle();
        return unwrap(result);
      },
      async profileByUsername(username) {
        const result = await client.from('profiles').select('id,username').eq('username', username).maybeSingle();
        return unwrap(result);
      },
      async saveStaffAssignment(userId, role, scopes = [], assignedBy = null) {
        const result = await client.from('staff_assignments').upsert({ user_id:userId, role, scopes, assigned_by:assignedBy }, { onConflict:'user_id' }).select('user_id,role,scopes,assigned_by,created_at').single();
        return unwrap(result);
      },
      async removeStaffAssignment(userId) {
        return unwrap(await client.from('staff_assignments').delete().eq('user_id', userId));
      },
      async saveModeratorScopes(userId, scopes = [], assignedBy = null) {
        const existing = await this.staffAssignment(userId);
        if (existing && existing.role !== 'moderator') throw new Error('This account has a site-wide role; manage that role in Site Admins.');
        if (!scopes.length) {
          if (existing?.role === 'moderator') await this.removeStaffAssignment(userId);
          return null;
        }
        return this.saveStaffAssignment(userId, 'moderator', scopes, assignedBy);
      },
      async uploadProfileImage(userId, slot, file) {
        const extensions = { 'image/jpeg':'jpg', 'image/png':'png', 'image/webp':'webp' };
        const extension = extensions[file?.type];
        if (!['logo','avatar','banner'].includes(slot) || !extension) throw new Error('Choose a PNG, JPG or WebP image.');
        if (file.size > 2800000) throw new Error('Images must be 2.8 MB or smaller.');
        const auth = await client.auth.getUser();
        if (auth.error) throw auth.error;
        if (!auth.data.user || auth.data.user.id !== userId) throw new Error('Sign in to the account that owns this profile.');
        const path = `${userId}/profile-${slot}.${extension}`;
        const bucket = client.storage.from('va-profile-media');
        const uploaded = await bucket.upload(path, file, { cacheControl:'3600', upsert:true, contentType:file.type });
        if (uploaded.error) throw uploaded.error;
        const publicUrl = bucket.getPublicUrl(path).data.publicUrl;
        return { path, publicUrl: `${publicUrl}?v=${Date.now()}` };
      },
      async saveProfile(userId, profile) {
        const result = await client.from('profiles').update(profile).eq('id', userId).select().single();
        return unwrap(result);
      },
      async submitFactionApplication(application) {
        return unwrap(await client.from('faction_applications').insert(application).select().single());
      },
      async factionApplications(userId) {
        return unwrap(await client.from('faction_applications').select('id,faction_id,character_name,rank_key,status,created_at').eq('user_id', userId).order('created_at'));
      },
      async pendingFactionApplications() {
        return unwrap(await client.from('faction_applications').select('id,user_id,faction_id,character_name,rank_key,status,created_at').eq('status', 'pending').order('created_at'));
      },
      async pendingSupportApplications() {
        return unwrap(await client.from('support_applications').select('id,user_id,category,provider,plan_key,external_reference,access_code,status,created_at').eq('status', 'pending').order('created_at'));
      },
      async supportApplications(userId) {
        return unwrap(await client.from('support_applications').select('id,category,provider,plan_key,external_reference,access_code,status,created_at').eq('user_id', userId).order('created_at'));
      },
      async premiumEntitlements(userId) {
        return unwrap(await client.from('entitlements').select('entitlement_key,source,starts_at,ends_at,external_reference').eq('user_id', userId).eq('entitlement_key', 'premium').order('starts_at', { ascending: false }));
      },
      async reviewSupportApplication(id, approve, durationMonths) {
        return unwrap(await client.rpc('review_support_application', { p_application_id:id, p_approve:approve, p_duration_months:durationMonths }));
      },
      async pendingModeratorApplications() {
        return unwrap(await client.from('moderator_applications').select('id,user_id,requested_scopes,decisions,status,created_at').in('status', ['pending','partial']).order('created_at'));
      },
      async staffAssignments() {
        return unwrap(await client.from('staff_assignments').select('user_id,role,scopes,assigned_by,created_at'));
      },
      async siteSettings() {
        const result = await client.from('site_config').select('settings,updated_at').eq('config_key', 'main').single();
        return unwrap(result);
      },
      async saveSiteSettings(settings) {
        const result = await client.from('site_config').update({ settings, updated_at: new Date().toISOString() }).eq('config_key', 'main').select('settings,updated_at').single();
        return unwrap(result);
      },
      async pendingCommunityXpClaims() {
        return unwrap(await client.from('community_xp_claims').select('id,user_id,mission_key,provider,proof,xp_reward,status,created_at').eq('status', 'pending').order('created_at'));
      },
      async communityXpClaims(userId) {
        return unwrap(await client.from('community_xp_claims').select('id,mission_key,provider,proof,xp_reward,status,created_at').eq('user_id', userId).order('created_at'));
      },
      async submitCommunityXpClaim(claim) {
        return unwrap(await client.from('community_xp_claims').insert(claim).select().single());
      },
      async reviewCommunityXpClaim(id, approve) {
        return unwrap(await client.rpc('review_community_xp_claim', { p_claim_id:id, p_approve:approve }));
      },
      async profilesFor(userIds) {
        if (!userIds.length) return [];
        return unwrap(await client.from('profiles').select('id,username').in('id', userIds));
      },
      async reviewFactionApplication(id, approve) {
        return unwrap(await client.rpc('review_faction_application', { p_application_id: id, p_approve: approve }));
      },
      async reviewModeratorApplication(id, decisions) {
        return unwrap(await client.rpc('review_moderator_application', { p_application_id: id, p_decisions: decisions }));
      },
      async submitSupportApplication(application) {
        return unwrap(await client.from('support_applications').insert(application).select().single());
      },
      async submitModeratorApplication(application) {
        return unwrap(await client.from('moderator_applications').insert(application).select().single());
      },
      async isStaff(scope = null) {
        return unwrap(await client.rpc('is_staff_for', { required_scope: scope }));
      },
      async messages(roomId) {
        return unwrap(await client.rpc('read_chat_messages', { target_room: roomId }));
      },
      async sendMessage(roomId, authorId, body) {
        return unwrap(await client.from('chat_messages').insert({ room_id: roomId, author_id: authorId, body }).select().single());
      },
      async editMessage(messageId, body) {
        return unwrap(await client.from('chat_messages').update({ body, edited_at: new Date().toISOString() }).eq('id', messageId).select().single());
      },
      async deleteMessage(messageId) { return unwrap(await client.from('chat_messages').delete().eq('id', messageId)); },
      async pinMessage(messageId) { return unwrap(await client.rpc('pin_chat_message', { message_id: messageId })); },
      subscribeMessages(roomId, onChange) {
        return client.channel(`chat:${roomId}`).on('postgres_changes', {
          event: '*', schema: 'public', table: 'chat_messages', filter: `room_id=eq.${roomId}`
        }, onChange).subscribe();
      },
      async recordArcadeEvent(gameKey, action) {
        return unwrap(await client.rpc('record_arcade_event', { p_game_key: gameKey, p_action: action }));
      },
      async recordArcadeCompletion(gameKey, progressionCount = 1, won = false, runId) {
        return unwrap(await client.rpc('record_arcade_completion', {
          p_game_key:gameKey,p_progression_count:progressionCount,p_won:Boolean(won),p_run_id:runId
        }));
      },
      async submitMonthlyArcadeScore(gameKey, score) {
        return unwrap(await client.rpc('submit_monthly_arcade_score', { p_game_key:gameKey, p_score:Math.floor(Number(score)||0) }));
      },
      async monthlyArcadeLeaderboard() {
        return unwrap(await client.rpc('monthly_arcade_leaderboard'));
      },
      async assignScopedModerator(userId, scopes) {
        return unwrap(await client.rpc('assign_scoped_moderator', { p_user_id:userId, p_scopes:scopes }));
      },
      async assignFactionMembership(userId, factionId, rankKey, characterName) {
        return unwrap(await client.rpc('assign_faction_membership', { p_user_id:userId, p_faction_id:factionId, p_rank_key:rankKey, p_character_name:characterName }));
      },
      async challengeCycles() {
        await client.rpc('ensure_current_challenges');
        return unwrap(await client.from('challenge_cycles').select('*').gte('ends_at', new Date().toISOString()).order('starts_at'));
      },
      async staffNotes() {
        return unwrap(await client.from('staff_notes').select('id,author_id,body,state,created_at,updated_at').order('created_at', { ascending: false }).limit(100));
      },
      async addStaffNote(body, authorId) {
        return unwrap(await client.from('staff_notes').insert({ body, author_id: authorId, state: 'open' }).select('id,author_id,body,state,created_at,updated_at').single());
      },
      async updateStaffNote(id, state, updatedBy) {
        return unwrap(await client.from('staff_notes').update({ state, updated_by: updatedBy, updated_at: new Date().toISOString() }).eq('id', id).select('id,author_id,body,state,created_at,updated_at').single());
      },
      async deleteStaffNote(id) {
        return unwrap(await client.from('staff_notes').delete().eq('id', id));
      }
    };
    window.VABackend = Object.freeze(api);
    return api;
  })();
  window.VABackendReady.catch(error => {
    console.error('Volks Arcade database connection failed:', error);
    window.VABackendError = error;
  });
})();

