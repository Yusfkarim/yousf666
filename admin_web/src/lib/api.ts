export type User = { id: string; email?: string };
export type Session = { access_token: string; token_type: string; user: User };
export type ApiResponse<T> = { data: T; error: null } | { data: null; error: { message: string } };

const TOKEN_KEY = 'yousf-admin-token';

const ok = <T>(data: T): ApiResponse<T> => ({ data, error: null });
const fail = <T>(message: string): ApiResponse<T> => ({ data: null, error: { message } });

class AuthApi {
  private listeners = new Set<(event: string, session: Session | null) => void>();

  get token() {
    try {
      return window.localStorage.getItem(TOKEN_KEY) || '';
    } catch {
      return '';
    }
  }

  private setToken(token: string) {
    try {
      if (token) window.localStorage.setItem(TOKEN_KEY, token);
      else window.localStorage.removeItem(TOKEN_KEY);
    } catch {
      /* storage unavailable for this session */
    }
  }

  private emit(event: string, session: Session | null) {
    this.listeners.forEach((listener) => listener(event, session));
  }

  onAuthStateChange(callback: (event: string, session: Session | null) => void) {
    this.listeners.add(callback);
    return {
      data: {
        subscription: {
          unsubscribe: () => this.listeners.delete(callback),
        },
      },
    };
  }

  async getSession(): Promise<{ data: { session: Session | null }; error: null }> {
    const token = this.token;
    if (!token) return { data: { session: null }, error: null };
    try {
      const response = await fetch('/auth/v1/user', {
        headers: { Authorization: `Bearer ${token}`, apikey: 'local-anon-key' },
      });
      if (!response.ok) throw new Error('Session expired');
      const user = (await response.json()) as User;
      return { data: { session: { access_token: token, token_type: 'bearer', user } }, error: null };
    } catch {
      this.setToken('');
      return { data: { session: null }, error: null };
    }
  }

  async signInWithPassword({ email, password }: { email: string; password: string }) {
    try {
      const response = await fetch('/auth/v1/token?grant_type=password', {
        method: 'POST',
        headers: { 'content-type': 'application/json', apikey: 'local-anon-key' },
        body: JSON.stringify({ email, password }),
      });
      const payload = await response.json();
      if (!response.ok) return fail(payload?.error?.message || 'چوونەژوورەوە شکستی هێنا.');
      this.setToken(payload.access_token);
      const session: Session = {
        access_token: payload.access_token,
        token_type: payload.token_type,
        user: payload.user,
      };
      this.emit('SIGNED_IN', session);
      return ok(session);
    } catch (error) {
      return fail(error instanceof Error ? error.message : 'چوونەژوورەوە شکستی هێنا.');
    }
  }

  async signOut() {
    try {
      await fetch('/auth/v1/logout', { method: 'POST' });
    } catch {
      /* local cleanup still applies */
    }
    this.setToken('');
    this.emit('SIGNED_OUT', null);
    return { error: null };
  }
}

class QueryBuilder<T> implements PromiseLike<ApiResponse<T>> {
  private params = new URLSearchParams();
  private table: string;
  private singleRow = false;

  constructor(table: string) {
    this.table = table;
  }

  select(columns = '*') {
    this.params.set('select', columns);
    return this;
  }

  eq(column: string, value: string | number | boolean) {
    this.params.set(column, `eq.${value}`);
    return this;
  }

  order(column: string, options: { ascending?: boolean } = {}) {
    this.params.set('order', `${column}.${options.ascending === false ? 'desc' : 'asc'}`);
    return this;
  }

  limit(count: number) {
    this.params.set('limit', String(count));
    return this;
  }

  maybeSingle() {
    this.singleRow = true;
    return this;
  }

  async run(): Promise<ApiResponse<T>> {
    try {
      const response = await fetch(`/rest/v1/${this.table}?${this.params.toString()}`, {
        headers: {
          Authorization: `Bearer ${auth.token}`,
          apikey: 'local-anon-key',
          accept: 'application/json',
        },
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) return fail(payload?.message || `داواکاری شکستی هێنا (${response.status})`);
      return ok((this.singleRow ? ((payload as T[])[0] ?? null) : payload) as T);
    } catch (error) {
      return fail(error instanceof Error ? error.message : 'پەیوەندی شکستی هێنا.');
    }
  }

  then<TResult1 = ApiResponse<T>, TResult2 = never>(
    onfulfilled?: ((value: ApiResponse<T>) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null
  ): PromiseLike<TResult1 | TResult2> {
    return this.run().then(onfulfilled as never, onrejected as never);
  }
}

class LiveChannel {
  private timer?: number;

  on(_event: string, _filter: Record<string, unknown>, callback: () => void) {
    this.timer = window.setInterval(callback, 4000);
    return this;
  }

  subscribe() {
    return this;
  }

  stop() {
    if (this.timer !== undefined) window.clearInterval(this.timer);
  }
}

export class ApiClient {
  auth = new AuthApi();

  from<T = Record<string, unknown>>(table: string) {
    return new QueryBuilder<T>(table);
  }

  async rpc<T = unknown>(name: string, params: Record<string, unknown> = {}): Promise<ApiResponse<T>> {
    try {
      const response = await fetch(`/rest/v1/rpc/${name}`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          Authorization: `Bearer ${auth.token}`,
          apikey: 'local-anon-key',
        },
        body: JSON.stringify(params),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) return fail(payload?.message || `RPC شکستی هێنا (${response.status})`);
      return ok(payload as T);
    } catch (error) {
      return fail(error instanceof Error ? error.message : 'پەیوەندی شکستی هێنا.');
    }
  }

  channel(_name: string) {
    return new LiveChannel();
  }

  async removeChannel(channel: LiveChannel) {
    channel.stop();
  }
}

const auth = new AuthApi();
export const apiClient = Object.assign(new ApiClient(), { auth });
