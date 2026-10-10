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
        return unwrap(await client.auth.signUp({ email, password, options: { data: { display_name: displayName }, emailRedirectTo: `${window.location.origin}${window.location.pathname}` } }));
      },
      async signIn(email, password) {
        return unwrap(await client.auth.signInWithPassword({ email, password }));
      },
      async signOut() { return unwrap(await client.auth.signOut()); },
      async session() { return unwrap(await client.auth.getSession()); },
      async currentUser() { return unwrap(await client.auth.getUser()); },
      async profile(userId) {
        const result = await client.from('profiles').select('id,username,bio,favorite_games,social_links,avatar_url,banner_url,is_public,show_online').eq('id', userId).single();
        return unwrap(result);
      },
      async wallet(userId) {
        const result = await client.from('xp_wallets').select('lifetime_xp,spendable_xp,va_coins').eq('user_id', userId).maybeSingle();
        return unwrap(result);
      },
      async staffAssignment(userId) {
        const result = await client.from('staff_assignments').select('role,scopes').eq('user_id', userId).maybeSingle();
        return unwrap(result);
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
      async challengeCycles() {
        await client.rpc('ensure_current_challenges');
        return unwrap(await client.from('challenge_cycles').select('*').gte('ends_at', new Date().toISOString()).order('starts_at'));
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
