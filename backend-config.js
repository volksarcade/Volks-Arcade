// Browser-visible Supabase settings. The publishable key is safe for browsers only because
// every exposed table uses Row Level Security. Never add a secret/service-role or PayPal key.
window.VOLKS_ARCADE_BACKEND = Object.freeze({
  enabled: true,
  supabaseUrl: 'https://vwmntsvcozsvfxlpgygg.supabase.co',
  publishableKey: 'sb_publishable_YVSoR3DmmtjEOP4E8yjMhg_dZZfcSYN',
  googleOAuthEnabled: true,
  subscriptionsEnabled: false
});
