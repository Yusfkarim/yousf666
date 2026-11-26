import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL?.trim()
  || (typeof window !== 'undefined' ? window.location.origin : '');
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim() || 'local-anon-key';

export const supabase = url && anonKey
  ? createClient(url, anonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
      realtime: { params: { eventsPerSecond: 5 } },
    })
  : null;
