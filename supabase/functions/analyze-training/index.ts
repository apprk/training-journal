import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return respond({ error: 'Method not allowed' }, 405);
  const auth = req.headers.get('Authorization');
  if (!auth) return respond({ error: 'Authentication required' }, 401);
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const aiKey = Deno.env.get('OPENAI_API_KEY');
  if (!url || !anon || !aiKey) return respond({ error: 'Server configuration is incomplete' }, 500);
  const db = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: { user }, error: authError } = await db.auth.getUser();
  if (authError || !user) return respond({ error: 'Invalid session' }, 401);
  let periodDays = 30;
  try { const body = await req.json(); periodDays = Math.min(90, Math.max(7, Number(body.period_days) || 30)); } catch { /* use default */ }
  const end = new Date();
  const start = new Date(end); start.setDate(start.getDate() - periodDays);
  const startDate = start.toISOString().slice(0, 10);
  const [workouts, runs, bodyRecords] = await Promise.all([
    db.from('workout_sessions').select('performed_at,notes,workout_exercises(name,muscle_group,workout_sets(weight_kg,reps,rpe))').gte('performed_at', startDate).order('performed_at', { ascending: false }).limit(40),
    db.from('running_sessions').select('started_at,distance_km,duration_seconds,average_heart_rate,notes').gte('started_at', start.toISOString()).order('started_at', { ascending: false }).limit(40),
    db.from('body_composition_records').select('measured_at,weight_kg,body_fat_pct,muscle_mass_kg').gte('measured_at', start.toISOString()).order('measured_at', { ascending: false }).limit(40),
  ]);
  const queryError = workouts.error || runs.error || bodyRecords.error;
  if (queryError) return respond({ error: 'Could not read personal records' }, 400);
  const payload = { period_days: periodDays, workouts: workouts.data || [], runs: runs.data || [], body_records: bodyRecords.data || [] };
  const hasData = payload.workouts.length + payload.runs.length + payload.body_records.length > 0;
  if (!hasData) return respond({ error: '分析できる記録がありません。先に記録を追加してください。' }, 422);
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST', headers: { Authorization: `Bearer ${aiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: Deno.env.get('AI_MODEL') || 'gpt-4o-mini', temperature: 0.4,
      messages: [
        { role: 'system', content: 'あなたは筋力トレーニングとランニングの記録を振り返る日本語アシスタントです。入力された本人の記録だけを根拠に、断定を避けて簡潔に回答してください。医療診断・治療・薬の指示はせず、健康上の懸念は医療専門家への相談を促してください。記録が少ない場合はその限界を明示してください。JSONで title, content, recommendations の3つの文字列を返してください。' },
        { role: 'user', content: `直近${periodDays}日間の自分の記録を分析してください。短い振り返りと次回への現実的なヒントを作成してください。記録データ(JSON): ${JSON.stringify(payload)}` },
      ], response_format: { type: 'json_object' },
    }),
  });
  if (!response.ok) return respond({ error: 'AI provider request failed' }, 502);
  const ai = await response.json();
  let result;
  try { result = JSON.parse(ai.choices?.[0]?.message?.content || '{}'); } catch { return respond({ error: 'AI returned an invalid response' }, 502); }
  const report = { user_id: user.id, title: String(result.title || 'トレーニング分析'), content: String(result.content || ''), recommendations: String(result.recommendations || ''), period_start: startDate, period_end: end.toISOString().slice(0, 10), data_types: [payload.workouts.length && 'workout', payload.runs.length && 'running', payload.body_records.length && 'body_composition'].filter(Boolean), model: Deno.env.get('AI_MODEL') || 'gpt-4o-mini' };
  const { data: saved, error: saveError } = await db.from('ai_analysis_reports').insert(report).select().single();
  if (saveError) return respond({ error: 'Could not save analysis' }, 500);
  return respond({ report: saved }, 200);
});

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
