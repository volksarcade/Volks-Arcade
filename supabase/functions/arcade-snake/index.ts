import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const allowedOrigins = new Set([
  'https://volksarcade.github.io',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
]);

const userClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

function respond(body: unknown, status: number, origin: string | null) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin' };
  if (origin && allowedOrigins.has(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Headers'] = 'authorization, apikey, content-type, x-client-info';
    headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
  }
  return new Response(status === 204 ? null : JSON.stringify(body), { status, headers });
}

type Point = { x: number; y: number };
function replay(seedInput: number, moves: string[]) {
  if (!Array.isArray(moves) || moves.length < 25 || moves.length > 5000 || moves.some((move) => !['U', 'D', 'L', 'R'].includes(move))) {
    throw new Error('Invalid Snake move history.');
  }
  let seed = seedInput >>> 0;
  if (seed === 0) seed = 0x6d2b79f5;
  const random = () => {
    seed ^= seed << 13;
    seed ^= seed >>> 17;
    seed ^= seed << 5;
    return (seed >>> 0) / 4294967296;
  };
  const snake: Point[] = [{ x: 5, y: 7 }, { x: 4, y: 7 }, { x: 3, y: 7 }];
  const directions: Record<string, Point> = { U: { x: 0, y: -1 }, D: { x: 0, y: 1 }, L: { x: -1, y: 0 }, R: { x: 1, y: 0 } };
  let current = 'R';
  let food: Point | null = { x: 15, y: 7 };
  let score = 0;
  let ended = false;
  for (let index = 0; index < moves.length; index++) {
    const next = moves[index];
    if (directions[current].x === -directions[next].x && directions[current].y === -directions[next].y) throw new Error('Invalid reverse move.');
    current = next;
    const head = { x: snake[0].x + directions[current].x, y: snake[0].y + directions[current].y };
    if (head.x < 0 || head.y < 0 || head.x >= 21 || head.y >= 15 || snake.some((part, partIndex) => partIndex > 0 && part.x === head.x && part.y === head.y)) {
      if (index !== moves.length - 1) throw new Error('Moves continue after the run ended.');
      ended = true;
      break;
    }
    snake.unshift(head);
    if (food && head.x === food.x && head.y === food.y) {
      score += 10;
      const free: Point[] = [];
      for (let y = 0; y < 15; y++) for (let x = 0; x < 21; x++) if (!snake.some((part) => part.x === x && part.y === y)) free.push({ x, y });
      food = free.length ? free[Math.floor(random() * free.length)] : null;
      if (!food) { ended = true; if (index !== moves.length - 1) throw new Error('Moves continue after the board is cleared.'); }
    } else {
      snake.pop();
    }
  }
  if (!ended) throw new Error('Finish the Snake run before submitting it.');
  return { score, steps: moves.length };
}

Deno.serve(async (request) => {
  const origin = request.headers.get('origin');
  if (origin && !allowedOrigins.has(origin)) return respond({ error: 'Origin not allowed.' }, 403, null);
  if (request.method === 'OPTIONS') return respond({}, 204, origin);
  if (request.method !== 'POST') return respond({ error: 'POST required.' }, 405, origin);

  const token = request.headers.get('authorization')?.replace(/^Bearer\\s+/i, '');
  if (!token) return respond({ error: 'Sign in to save a Snake result.' }, 401, origin);
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) return respond({ error: 'Your session could not be verified. Sign in again.' }, 401, origin);

  try {
    const body = await request.json();
    if (body.action === 'start') {
      const { count, error: countError } = await admin.from('arcade_snake_runs')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', authData.user.id)
        .gt('started_at', new Date(Date.now() - 60_000).toISOString());
      if (countError) throw countError;
      if ((count || 0) >= 10) return respond({ error: 'Please wait a minute before starting another run.' }, 429, origin);
      const bytes = new Uint32Array(1);
      crypto.getRandomValues(bytes);
      const seed = bytes[0] || 0x6d2b79f5;
      const { data, error } = await admin.from('arcade_snake_runs')
        .insert({ user_id: authData.user.id, seed })
        .select('id')
        .single();
      if (error) throw error;
      return respond({ runId: data.id, seed }, 200, origin);
    }

    if (body.action !== 'finish' || typeof body.runId !== 'string') return respond({ error: 'Invalid Snake request.' }, 400, origin);
    const { data: run, error: runError } = await admin.from('arcade_snake_runs')
      .select('id,user_id,seed,finished_at,score')
      .eq('id', body.runId)
      .maybeSingle();
    if (runError) throw runError;
    if (!run || run.user_id !== authData.user.id) return respond({ error: 'Snake run not found.' }, 404, origin);
    if (run.finished_at) return respond({ score: run.score, xp_reward: 0, already_counted: true }, 200, origin);

    const result = replay(Number(run.seed), body.moves);
    const { data, error } = await admin.rpc('record_verified_snake_run', {
      p_run_id: run.id,
      p_score: result.score,
      p_step_count: result.steps,
    });
    if (error) throw error;
    return respond(data, 200, origin);
  } catch (error) {
    console.error('Snake result rejected:', error);
    const message = error instanceof Error && /Invalid|reverse|ended|Finish/.test(error.message)
      ? error.message
      : 'The run could not be saved. No XP was awarded.';
    return respond({ error: message }, 400, origin);
  }
});
