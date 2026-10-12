# Volks Arcade backend setup

The VolksArcade Supabase project is live. The connected project has 12 applied migrations. The website uses the public publishable key from `backend-config.js`; never put a secret/service-role key in the website.

## What the schema covers

- Supabase Auth user profiles, profile visibility and trusted staff assignments.
- The three user-supplied factions and their rank ladders, membership claims and approval records.
- Separate lifetime XP, spendable XP, VA Coins and append-only XP records.
- Daily/weekly challenge definitions and progress, global/faction/leader chat rooms, pin notifications, sanctions and premium applications.
- Row Level Security policies for player-owned data, faction membership, staff scopes, and own-message edit/delete.
- Server-side RPCs for challenge awards, XP-to-VA-Coin exchanges, store purchases, faction/moderator reviews and support reviews. Approved paid subscriptions receive an expiring Premium entitlement only after staff manually verify payment. Do not grant clients direct write access to wallets, XP ledgers, entitlements, payment events or staff roles.

## Connect this to your own project

1. Sign up on the website with your owner email and confirm it from your email inbox.
2. In Supabase SQL Editor, open `bootstrap-owner.sql`, replace `REPLACE_WITH_YOUR_ACCOUNT_EMAIL`, and run it once. This grants the first account the protected Owner role.
3. In Supabase Authentication settings, make sure the site's published URL is an allowed redirect URL. The sign-up confirmation link returns to the current site URL.
4. Keep the database password and all secret/service-role keys private. The URL and `sb_publishable_...` key in `backend-config.js` are browser-visible and rely on the RLS policies.

## Not live yet

The website uses Supabase Auth for account creation/sign-in, saves profile text/social links, faction/support/moderator applications, reads the private account wallet, tracks rotating daily/weekly arcade challenges, exchanges spendable XP for VA Coins, and processes level-gated cosmetic purchases. Staff handover notes are shared through the database. Faction and moderator application decisions are database-backed; staff can verify support manually and grant a time-limited Premium entitlement. Automatic PayPal subscription checkout, renewal/cancellation processing, donor totals, profile image storage, sanctions and some chat administration still need secure server-backed integration. Subscription checkout remains disabled until verified PayPal webhooks are connected. PayPal donations still use the supplied business page. Do not enable subscriptions by changing the frontend flag alone.

The schema is an early production foundation, not a completed production launch. Confirm email recovery and redirect settings, storage bucket policies, moderation retention, anti-abuse controls and payment webhook events before turning on those features. The SQL editor's security advisor warns about several `SECURITY DEFINER` RPCs; each callable RPC has an explicit signed-in user check or staff-scope check, while `handle_new_user` and the automatic-RLS trigger helper are not browser-callable.

