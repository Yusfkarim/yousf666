import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-webhook-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type WebhookRecord = Record<string, unknown>;
type WebhookPayload = { type?: string; eventType?: string; table?: string; record?: WebhookRecord; old_record?: WebhookRecord };
type FirebaseServiceAccount = { project_id: string; client_email: string; private_key: string; token_uri?: string };

function base64Url(input: string | Uint8Array): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function getFirebaseAccessToken(account: FirebaseServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64Url(JSON.stringify({
    iss: account.client_email,
    sub: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: account.token_uri ?? 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const pem = account.private_key.replace(/\\n/g, '\n').replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  const keyBytes = Uint8Array.from(atob(pem), (character) => character.charCodeAt(0));
  const signingKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', signingKey, new TextEncoder().encode(unsigned));
  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;
  const tokenResponse = await fetch(account.token_uri ?? 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  const tokenBody = await tokenResponse.json();
  if (!tokenResponse.ok || typeof tokenBody.access_token !== 'string') throw new Error('Firebase access token exchange failed');
  return tokenBody.access_token;
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: corsHeaders });

  const expectedSecret = Deno.env.get('WEBHOOK_SECRET');
  if (!expectedSecret || request.headers.get('x-webhook-secret') !== expectedSecret) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders });
  }

  try {
    const payload = await request.json() as WebhookPayload;
    const event = (payload.type ?? payload.eventType ?? '').toUpperCase();
    const record = payload.record;
    const oldRecord = payload.old_record;
    if (payload.table !== 'orders' || !record || !['INSERT', 'UPDATE'].includes(event)) {
      return Response.json({ ignored: true }, { headers: corsHeaders });
    }

    const status = String(record.status ?? 'pending');
    const statusChanged = event === 'INSERT' || oldRecord?.status !== record.status;
    const driverAssigned = event === 'UPDATE' && oldRecord?.driver_id !== record.driver_id && record.driver_id != null;
    if (!statusChanged && !driverAssigned) return Response.json({ ignored: true }, { headers: corsHeaders });

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const rawAccount = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!supabaseUrl || !serviceRoleKey || !rawAccount) throw new Error('Notification secrets are not configured');
    const account = JSON.parse(rawAccount) as FirebaseServiceAccount;
    const client = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });

    const { data: store, error: storeError } = await client.from('stores').select('owner_id,name').eq('id', record.store_id).single();
    if (storeError || !store) throw new Error('Order store could not be resolved');

    const recipients = new Set<string>();
    if (event === 'INSERT') {
      recipients.add(store.owner_id as string);
    } else {
      if (statusChanged && typeof record.buyer_id === 'string') recipients.add(record.buyer_id);
      if ((driverAssigned || statusChanged) && typeof record.driver_id === 'string') recipients.add(record.driver_id);
      recipients.add(store.owner_id as string);
    }
    recipients.delete('');

    const { data: profiles, error: profilesError } = await client
      .from('profiles')
      .select('fcm_token')
      .in('id', [...recipients]);
    if (profilesError) throw new Error('Push recipients could not be resolved');
    const tokens = [...new Set((profiles ?? []).map((profile) => profile.fcm_token).filter((token): token is string => typeof token === 'string' && token.length > 0))];
    if (tokens.length === 0) return Response.json({ sent: 0 }, { headers: corsHeaders });

    const accessToken = await getFirebaseAccessToken(account);
    const title = event === 'INSERT' ? 'داواکاریی نوێ' : driverAssigned && !statusChanged ? 'گەیاندن پێسپێردرا' : 'نوێکاریی داواکاری';
    const body = event === 'INSERT'
      ? `داواکاریی نوێ بۆ ${store.name} هاتووە.`
      : `دۆخی داواکاری #${record.order_number ?? ''}: ${status}.`;
    const results = await Promise.all(tokens.map(async (token) => {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: { order_id: String(record.id ?? ''), order_number: String(record.order_number ?? ''), status },
            android: { priority: 'high' },
          },
        }),
      });
      return response.ok;
    }));

    return Response.json({ sent: results.filter(Boolean).length, failed: results.length - results.filter(Boolean).length }, { headers: corsHeaders });
  } catch (error) {
    console.error('order notification hook failed', error);
    return Response.json({ error: 'Notification delivery failed' }, { status: 500, headers: corsHeaders });
  }
});
