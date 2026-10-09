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
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!auth || !url || !anon || !serviceKey) return respond({ error: 'Authentication required' }, 401);
  const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return respond({ error: 'Invalid session' }, 401);
  const admin = createClient(url, serviceKey);
  const bucket = admin.storage.from('body-composition-images');
  const { data: files, error: listError } = await bucket.list(user.id, { limit: 1000 });
  if (listError) return respond({ error: 'Could not remove personal image files' }, 500);
  const names = (files || []).filter((file) => file.id).map((file) => `${user.id}/${file.name}`);
  if (names.length) {
    const { error: removeError } = await bucket.remove(names);
    if (removeError) return respond({ error: 'Could not remove personal image files' }, 500);
  }
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return respond({ error: 'Could not delete account' }, 500);
  return respond({ deleted: true });
});

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
