import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const siteOrigin = "https://volksarcade.github.io";
const allowedOrigins = new Set([siteOrigin, "http://127.0.0.1:3000", "http://localhost:3000"]);
const packages = {
  starter: { coins: 100, pence: 99, amount: "0.99", name: "100 VA Coins" },
  popular: { coins: 550, pence: 499, amount: "4.99", name: "550 VA Coins" },
  bundle: { coins: 1200, pence: 999, amount: "9.99", name: "1,200 VA Coins" },
} as const;

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || siteOrigin;
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : siteOrigin,
    "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
function settings() {
  const mode = Deno.env.get("PAYPAL_MODE") || "";
  const clientId = Deno.env.get("PAYPAL_CLIENT_ID") || "";
  const clientSecret = Deno.env.get("PAYPAL_CLIENT_SECRET") || "";
  const secretMap = Deno.env.get("SUPABASE_SECRET_KEYS");
  let newSecret = "";
  try { newSecret = secretMap ? (JSON.parse(secretMap).default || "") : ""; } catch { /* use legacy environment below */ }
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || newSecret;
  const baseUrl = mode === "live" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";
  return { mode, clientId, clientSecret, supabaseKey, baseUrl, configured: Boolean(clientId && clientSecret && supabaseKey && (mode === "live" || mode === "sandbox")) };
}
function publishableKey() {
  const raw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (raw) {
    try { return JSON.parse(raw).default || ""; } catch { /* fall back to legacy anon key */ }
  }
  return Deno.env.get("SUPABASE_ANON_KEY") || "";
}
async function authenticate(req: Request) {
  const authorization = req.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) return null;
  const projectUrl = Deno.env.get("SUPABASE_URL") || "";
  const publicKey = publishableKey();
  if (!projectUrl || !publicKey) return null;
  const response = await fetch(projectUrl + "/auth/v1/user", { headers: { apikey: publicKey, Authorization: authorization } });
  if (!response.ok) return null;
  const user = await response.json();
  return typeof user.id === "string" ? { id: user.id } : null;
}
async function paypalToken(cfg: ReturnType<typeof settings>) {
  const credentials = btoa(cfg.clientId + ":" + cfg.clientSecret);
  const response = await fetch(cfg.baseUrl + "/v1/oauth2/token", {
    method: "POST",
    headers: { Authorization: "Basic " + credentials, "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=client_credentials",
  });
  if (!response.ok) throw new Error("PayPal credentials could not be verified.");
  const body = await response.json();
  if (typeof body.access_token !== "string") throw new Error("PayPal did not provide an access token.");
  return body.access_token as string;
}
async function paypalRequest(cfg: ReturnType<typeof settings>, token: string, path: string, init: RequestInit = {}) {
  const response = await fetch(cfg.baseUrl + path, {
    ...init,
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error("PayPal API error", response.status, JSON.stringify({ name: body.name || body.error || "unknown", debug_id: body.debug_id || null, details: Array.isArray(body.details) ? body.details.map((entry: any) => ({ field: entry?.field || "", issue: entry?.issue || "" })) : [] }));
    throw new Error("PayPal could not complete this checkout. Please try again or contact support.");
  }
  return body;
}
async function databaseRequest(cfg: ReturnType<typeof settings>, path: string, init: RequestInit = {}) {
  const projectUrl = Deno.env.get("SUPABASE_URL") || "";
  const response = await fetch(projectUrl + "/rest/v1/" + path, {
    ...init,
    headers: {
      apikey: cfg.supabaseKey,
      Authorization: "Bearer " + cfg.supabaseKey,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) {
    console.error("VA Coin database operation failed", response.status, body?.code || "unknown");
    throw new Error("VA Coin order could not be saved securely. No coins were credited.");
  }
  return body;
}
async function getOrder(cfg: ReturnType<typeof settings>, orderId: string, userId: string) {
  const rows = await databaseRequest(cfg, "va_coin_orders?select=paypal_order_id,user_id,package_key,coin_amount,amount_pence,currency,status,capture_id&paypal_order_id=eq." + encodeURIComponent(orderId) + "&user_id=eq." + encodeURIComponent(userId) + "&limit=1");
  return Array.isArray(rows) ? rows[0] || null : null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);
  const user = await authenticate(req);
  if (!user) return json(req, { error: "Sign in to continue." }, 401);
  const cfg = settings();
  const body = await req.json().catch(() => ({}));
  const action = body?.action;

  if (action === "status") {
    if (!cfg.configured) return json(req, { ready: false, reason: "paypal_setup_required" });
    try {
      await paypalToken(cfg);
      return json(req, { ready: true, clientId: cfg.clientId, mode: cfg.mode });
    } catch {
      return json(req, { ready: false, reason: "paypal_credentials_invalid" });
    }
  }

  if (!cfg.configured) return json(req, { error: "PayPal checkout is not configured yet." }, 503);

  try {
    const token = await paypalToken(cfg);

    if (action === "create") {
      const packageKey = String(body?.packageKey || "") as keyof typeof packages;
      const pack = packages[packageKey];
      if (!pack) return json(req, { error: "Choose a valid VA Coin pack." }, 400);
      const orderBody = {
        intent: "CAPTURE",
        purchase_units: [{
          reference_id: packageKey,
          custom_id: user.id,
          description: "VOLKS ARCADE · " + pack.name,
          amount: { currency_code: "GBP", value: pack.amount, breakdown: { item_total: { currency_code: "GBP", value: pack.amount } } },
          items: [{
            name: pack.name,
            quantity: "1",
            unit_amount: { currency_code: "GBP", value: pack.amount },
            category: "DIGITAL_GOODS",
          }],
        }],
        application_context: {
          brand_name: "VOLKS ARCADE",
          user_action: "PAY_NOW",
          shipping_preference: "NO_SHIPPING",
          return_url: siteOrigin + "/Volks-Arcade/#store",
          cancel_url: siteOrigin + "/Volks-Arcade/#store",
        },
      };
      const paypalOrder = await paypalRequest(cfg, token, "/v2/checkout/orders", {
        method: "POST",
        headers: { "PayPal-Request-Id": crypto.randomUUID() },
        body: JSON.stringify(orderBody),
      });
      if (typeof paypalOrder.id !== "string") throw new Error("PayPal did not return an order ID.");
      await databaseRequest(cfg, "va_coin_orders", {
        method: "POST",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          paypal_order_id: paypalOrder.id,
          user_id: user.id,
          package_key: packageKey,
          coin_amount: pack.coins,
          amount_pence: pack.pence,
          currency: "GBP",
          status: "created",
        }),
      });
      return json(req, { orderId: paypalOrder.id });
    }

    if (action === "capture") {
      const orderId = String(body?.orderId || "");
      if (!orderId || orderId.length > 128) return json(req, { error: "Invalid PayPal order." }, 400);
      const savedOrder = await getOrder(cfg, orderId, user.id);
      if (!savedOrder) return json(req, { error: "This order does not belong to your account." }, 404);
      if (savedOrder.status === "completed") return json(req, { alreadyFulfilled: true, coins: Number(savedOrder.coin_amount) });

      let order = await paypalRequest(cfg, token, "/v2/checkout/orders/" + encodeURIComponent(orderId));
      const verifyOrder = (value: any) => {
        const unit = value?.purchase_units?.length === 1 ? value.purchase_units[0] : null;
        return Boolean(unit
          && unit.reference_id === savedOrder.package_key
          && unit.custom_id === user.id
          && unit.amount?.currency_code === "GBP"
          && unit.amount?.value === (Number(savedOrder.amount_pence) / 100).toFixed(2));
      };
      if (!verifyOrder(order)) return json(req, { error: "The PayPal order details do not match this VA Coin pack." }, 400);

      if (order.status === "APPROVED") {
        order = await paypalRequest(cfg, token, "/v2/checkout/orders/" + encodeURIComponent(orderId) + "/capture", {
          method: "POST",
          headers: { "PayPal-Request-Id": crypto.randomUUID() },
          body: "{}",
        });
      }
      const unit = order?.purchase_units?.[0];
      const captures = unit?.payments?.captures || [];
      const capture = captures.find((entry: any) => entry?.status === "COMPLETED");
      if (order?.status !== "COMPLETED" || captures.length !== 1 || !capture?.id
          || capture.amount?.currency_code !== "GBP"
          || capture.amount?.value !== (Number(savedOrder.amount_pence) / 100).toFixed(2)) {
        return json(req, { error: "PayPal has not confirmed a completed payment. No coins were credited." }, 409);
      }
      const merchantId = Deno.env.get("PAYPAL_MERCHANT_ID");
      if (merchantId && unit?.payee?.merchant_id !== merchantId) {
        return json(req, { error: "PayPal payment was sent to an unexpected merchant account. Contact support." }, 409);
      }
      const fulfilled = await databaseRequest(cfg, "rpc/fulfill_va_coin_order", {
        method: "POST",
        body: JSON.stringify({
          p_order_id: orderId,
          p_capture_id: capture.id,
          p_user_id: user.id,
          p_package_key: savedOrder.package_key,
          p_amount_pence: Number(savedOrder.amount_pence),
          p_currency: "GBP",
          p_custom_id: user.id,
        }),
      });
      return json(req, { ok: true, coins: Number(fulfilled.coin_amount), alreadyFulfilled: Boolean(fulfilled.already_fulfilled) });
    }

    return json(req, { error: "Unknown checkout action." }, 400);
  } catch (error) {
    console.error("VA Coin checkout failed", error instanceof Error ? error.message : "unknown");
    return json(req, { error: error instanceof Error ? error.message : "VA Coin checkout failed." }, 502);
  }
});
