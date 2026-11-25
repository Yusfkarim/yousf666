import { useCallback, useEffect, useMemo, useState } from 'react';
import type { FormEvent, ReactNode } from 'react';
import type { Session, SupabaseClient } from '@supabase/supabase-js';
import {
  Activity,
  ArrowDownLeft,
  ArrowUpRight,
  BadgeCheck,
  Banknote,
  BarChart3,
  Check,
  CircleAlert,
  Clock3,
  FileText,
  LayoutDashboard,
  LogOut,
  Menu,
  Moon,
  Package,
  RefreshCw,
  Search,
  ShieldCheck,
  Store,
  Sun,
  Truck,
  Wallet,
  X,
} from 'lucide-react';
import { supabase as configuredClient } from './lib/supabase';

type TabKey = 'overview' | 'stores' | 'orders' | 'settlements';
type AdminProfile = { id: string; full_name: string; role: string; is_active: boolean };
type StoreRow = {
  id: string;
  name: string;
  city: string;
  is_approved: boolean;
  is_open: boolean;
  commission_type: 'percentage' | 'fixed_iqd';
  commission_value: number;
  delivery_mode: 'platform_driver' | 'store_self';
  delivery_fee_iqd: number;
  created_at: string;
};
type FinancialRow = {
  store_id: string;
  store_name: string;
  total_delivered_orders: number;
  gross_sales_iqd: number;
  total_commission_iqd: number;
  total_settled_iqd: number;
  current_balance_due_iqd: number;
};
type AdminSummary = {
  today_orders: number;
  month_orders: number;
  today_gmv_iqd: number;
  month_gmv_iqd: number;
  lifetime_commission_iqd: number;
  month_commission_iqd: number;
  pending_stores: number;
  active_orders: number;
};

const tabs: { key: TabKey; label: string; icon: typeof LayoutDashboard }[] = [
  { key: 'overview', label: 'پوختەی گشتی', icon: LayoutDashboard },
  { key: 'stores', label: 'دوکان و کۆمسیۆن', icon: Store },
  { key: 'orders', label: 'چاودێری داواکاری', icon: Package },
  { key: 'settlements', label: 'پاکتاوکردنی حیسابات', icon: Wallet },
];

function formatIqd(value: number | string | null | undefined) {
  const number = Number(value || 0);
  const latin = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(Number.isFinite(number) ? number : 0);
  const arabic = latin.replace(/[0-9]/g, (digit) => '٠١٢٣٤٥٦٧٨٩'[Number(digit)]);
  return `${arabic} د.ع`;
}

function statusLabel(status: string) {
  const labels: Record<string, string> = {
    pending: 'چاوەڕوانە', accepted: 'قبووڵکرا', preparing: 'لە ئامادەکردندایە',
    on_the_way: 'لە ڕێگادایە', delivered: 'گەیەندرا', rejected: 'ڕەتکرایەوە', cancelled: 'هەڵوەشایەوە',
  };
  return labels[status] ?? status;
}

function StatusPill({ status, approved }: { status?: string; approved?: boolean }) {
  const text = approved !== undefined ? (approved ? 'پەسەندکراوە' : 'چاوەڕوانی پەسەندکردن') : statusLabel(status ?? 'pending');
  const success = approved === true || status === 'delivered' || status === 'accepted';
  const danger = approved === false || status === 'rejected' || status === 'cancelled';
  return <span className={`inline-flex rounded-full px-3 py-1 text-xs font-bold ${success ? 'bg-green-100 text-green-800' : danger ? 'bg-red-100 text-red-700' : 'bg-orange-100 text-orange-deep'}`}>{text}</span>;
}

function App() {
  const client = configuredClient;
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<AdminProfile | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [profileLoading, setProfileLoading] = useState(false);
  const [accessError, setAccessError] = useState('');
  const [activeTab, setActiveTab] = useState<TabKey>('overview');
  const [toast, setToast] = useState('');
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [darkMode, setDarkMode] = useState(() => {
    try { return window.localStorage.getItem('yousf-admin-theme') === 'dark'; } catch { return false; }
  });

  useEffect(() => {
    try { window.localStorage.setItem('yousf-admin-theme', darkMode ? 'dark' : 'light'); } catch { /* Theme still works for this session. */ }
  }, [darkMode]);

  const notify = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(''), 3600);
  }, []);

  useEffect(() => {
    if (!client) {
      setAuthReady(true);
      return;
    }
    let alive = true;
    const { data: { subscription } } = client.auth.onAuthStateChange((_event, nextSession) => {
      if (alive) setSession(nextSession);
    });
    void client.auth.getSession().then(({ data }) => {
      if (!alive) return;
      setSession(data.session);
      setAuthReady(true);
    });
    return () => {
      alive = false;
      subscription.unsubscribe();
    };
  }, [client]);

  useEffect(() => {
    if (!client || !session) {
      setProfile(null);
      setProfileLoading(false);
      return;
    }
    let alive = true;
    setProfileLoading(true);
    setAccessError('');
    void client.from('profiles').select('id, full_name, role, is_active').eq('id', session.user.id).maybeSingle().then(async ({ data, error }) => {
      if (!alive) return;
      if (error || !data) {
        setAccessError(error?.message ?? 'پڕۆفایلی ئەم هەژمارە نییە.');
        setProfileLoading(false);
        return;
      }
      const adminProfile = data as AdminProfile;
      if (adminProfile.role !== 'admin' || !adminProfile.is_active) {
        setAccessError('ئەم داشبۆردە تەنها بۆ بەڕێوەبەرە چالاکەکانە.');
        setProfileLoading(false);
        await client.auth.signOut();
        return;
      }
      setProfile(adminProfile);
      setProfileLoading(false);
    });
    return () => { alive = false; };
  }, [client, session]);

  if (!client) return <SetupNotice />;
  if (!authReady || (session && profileLoading)) return <FullPageLoading />;
  if (!session || !profile) {
    return <LoginScreen client={client} accessError={accessError} onSignedIn={() => setAccessError('')} />;
  }

  const activeTabInfo = tabs.find((tab) => tab.key === activeTab) ?? tabs[0];
  return (
    <div className={`min-h-screen bg-cream text-espresso ${darkMode ? 'theme-dark' : ''}`} dir="rtl">
      <div className="mx-auto flex min-h-screen max-w-[1600px]">
        <aside className={`fixed inset-y-0 right-0 z-40 w-72 border-l border-[#eadfd2] bg-[#fbf8f3] p-5 transition-transform lg:sticky lg:top-0 lg:h-screen lg:translate-x-0 ${mobileMenuOpen ? 'translate-x-0 shadow-2xl' : 'translate-x-full lg:translate-x-0'}`}>
          <div className="mb-8 flex items-center gap-3 rounded-[26px] border border-white bg-gradient-to-br from-white to-ivory p-4 shadow-clay">
            <span className="clay-icon h-12 w-12 shrink-0"><Store size={23} /></span>
            <div><p className="font-extrabold text-orange-deep">بازاڕی یۆسف</p><p className="text-xs text-taupe">کۆنترۆڵی بەڕێوەبەر</p></div>
            <button className="mr-auto rounded-full p-2 text-taupe lg:hidden" onClick={() => setMobileMenuOpen(false)} aria-label="داخستن"><X size={18} /></button>
          </div>
          <div className="mb-3 px-3 text-[11px] font-bold text-taupe">بەڕێوەبردن</div>
          <nav className="space-y-2">
            {tabs.map(({ key, label, icon: Icon }) => (
              <button key={key} onClick={() => { setActiveTab(key); setMobileMenuOpen(false); }} className={`flex w-full items-center gap-3 rounded-2xl px-4 py-3 text-right text-sm font-bold transition ${activeTab === key ? 'bg-gradient-to-l from-orange to-orange-deep text-white shadow-clay-orange' : 'text-taupe hover:bg-peach hover:text-espresso'}`}>
                <Icon size={19} /><span>{label}</span>{key === 'stores' && <span className="mr-auto rounded-full bg-white/25 px-2 py-0.5 text-[10px]">ڕێکخستن</span>}
              </button>
            ))}
          </nav>
          <div className="mt-8 rounded-2xl bg-peach/80 p-4 text-xs leading-6 text-taupe">
            <div className="mb-1 flex items-center gap-2 font-bold text-orange-deep"><ShieldCheck size={16} /> پارێزراو بە RLS</div>
            گۆڕینی کۆمسیۆن و پاکتاو تەنها لە ڕێگەی RPC ـی سێرڤەرەوە ئەنجام دەدرێت.
          </div>
          <div className="absolute inset-x-5 bottom-5 hidden rounded-2xl border border-white bg-white/70 p-3 text-xs lg:block">
            <div className="flex items-center gap-2"><span className="grid h-9 w-9 place-items-center rounded-xl bg-orange-100 text-orange-deep"><ShieldCheck size={17} /></span><div className="min-w-0"><p className="truncate font-bold">{profile.full_name || 'بەڕێوەبەر'}</p><p className="text-taupe">هەژماری بەڕێوەبەر</p></div><button onClick={() => void client.auth.signOut()} className="mr-auto rounded-xl p-2 text-taupe hover:bg-red-50 hover:text-coral" title="چوونەدەرەوە"><LogOut size={17} /></button></div>
          </div>
        </aside>
        {mobileMenuOpen && <button aria-label="داخستن" className="fixed inset-0 z-30 bg-espresso/25 lg:hidden" onClick={() => setMobileMenuOpen(false)} />}

        <main className="min-w-0 flex-1">
          <header className="sticky top-0 z-20 flex items-center justify-between border-b border-[#eadfd2]/70 bg-cream/95 px-4 py-4 backdrop-blur-sm md:px-8">
            <div className="flex items-center gap-3">
              <button onClick={() => setMobileMenuOpen(true)} className="rounded-2xl bg-white p-2.5 text-orange-deep shadow-clay lg:hidden" aria-label="مینو"><Menu size={20} /></button>
              <div className="hidden h-10 w-10 place-items-center rounded-2xl bg-white text-orange-deep shadow-clay sm:grid"><activeTabInfo.icon size={20} /></div>
              <div><h1 className="text-lg font-extrabold md:text-xl">{activeTabInfo.label}</h1><p className="hidden text-xs text-taupe sm:block">سیستەمی بازاڕ و داواکاری · سلێمانی</p></div>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setDarkMode((value) => !value)}
                aria-label={darkMode ? 'چالاککردنی ڕووناکی' : 'چالاککردنی دۆخی تاریک'}
                aria-pressed={darkMode}
                title={darkMode ? 'دۆخی ڕووناک' : 'دۆخی تاریک'}
                className="rounded-full border border-white bg-white/70 p-2.5 text-orange-deep shadow-clay"
              >{darkMode ? <Sun size={17} /> : <Moon size={17} />}</button>
              <span className="hidden rounded-full border border-white bg-white/70 px-3 py-2 text-xs text-taupe sm:inline-flex"><span className="ml-2 h-2 w-2 rounded-full bg-green-500" />COD چالاکە</span>
              <button onClick={() => void client.auth.signOut()} className="flex items-center gap-2 rounded-full border border-white bg-white px-3 py-2 text-xs font-bold text-taupe shadow-clay hover:text-coral"><LogOut size={16} /><span className="hidden sm:inline">چوونەدەرەوە</span></button>
            </div>
          </header>

          <div className="p-4 md:p-8">
            {activeTab === 'overview' && <OverviewPanel client={client} notify={notify} />}
            {activeTab === 'stores' && <StoresPanel client={client} notify={notify} />}
            {activeTab === 'orders' && <OrdersPanel client={client} notify={notify} />}
            {activeTab === 'settlements' && <SettlementsPanel client={client} notify={notify} />}
          </div>
        </main>
      </div>
      {toast && <div role="status" className="fixed bottom-5 left-5 z-50 flex max-w-sm items-center gap-2 rounded-2xl bg-espresso px-4 py-3 text-sm text-white shadow-xl"><Check size={17} className="text-mint" />{toast}</div>}
    </div>
  );
}

function SetupNotice() {
  return <div className="grid min-h-screen place-items-center bg-cream p-5" dir="rtl"><div className="clay-card max-w-lg p-7 text-center"><span className="clay-icon mx-auto mb-4 h-14 w-14"><ShieldCheck size={26} /></span><h1 className="text-xl font-extrabold">ڕێکخستنی Supabase پێویستە</h1><p className="mt-3 text-sm leading-7 text-taupe">فایلی <code>.env</code> لە <code>admin_web</code> دروست بکە و <code>VITE_SUPABASE_URL</code> و <code>VITE_SUPABASE_ANON_KEY</code> دابنێ. پاشان <code>npm run dev</code> بکە.</p></div></div>;
}

function FullPageLoading() {
  return <div className="grid min-h-screen place-items-center bg-cream" dir="rtl"><div className="clay-card flex items-center gap-3 px-6 py-5 text-taupe"><RefreshCw className="animate-spin text-orange" size={20} />پشکنینی دەسەڵاتی بەڕێوەبەر...</div></div>;
}

function LoginScreen({ client, accessError, onSignedIn }: { client: SupabaseClient; accessError: string; onSignedIn: () => void }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setMessage('');
    const { error } = await client.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (error) setMessage(error.message);
    else onSignedIn();
  }
  return <div className="grid min-h-screen place-items-center bg-[radial-gradient(circle_at_top_right,#ffe6d3,transparent_42%),#f7f2e8] p-4" dir="rtl">
    <div className="grid w-full max-w-4xl overflow-hidden rounded-[32px] border border-white bg-white/70 shadow-clay md:grid-cols-2">
      <div className="hidden min-h-[520px] flex-col justify-between bg-gradient-to-br from-[#ffb37b] via-orange to-orange-deep p-10 text-white md:flex">
        <div className="flex items-center gap-3"><span className="grid h-12 w-12 place-items-center rounded-2xl border border-white/50 bg-white/20"><Store size={24} /></span><span className="text-xl font-extrabold">بازاڕی یۆسف</span></div>
        <div><div className="mb-5 grid h-16 w-16 place-items-center rounded-3xl border border-white/50 bg-white/20"><BarChart3 size={32} /></div><h1 className="text-3xl font-extrabold leading-relaxed">چاودێری و بەڕێوەبردنی بازاڕ</h1><p className="mt-3 max-w-sm text-sm leading-7 text-white/85">دوکانەکان پەسەند بکە، داواکارییەکان ببینە و پاکتاوی کۆمسیۆن بە پارێزگاری تۆمار بکە.</p></div>
        <p className="text-xs text-white/75">پلاتفۆرمی ناوخۆیی · پارێزراو بە Supabase RLS</p>
      </div>
      <form onSubmit={submit} className="p-6 sm:p-10">
        <div className="mb-6 flex items-center gap-3 md:hidden"><span className="clay-icon h-12 w-12"><Store size={22} /></span><div><h1 className="font-extrabold text-orange-deep">بازاڕی یۆسف</h1><p className="text-xs text-taupe">داشبۆردی بەڕێوەبەر</p></div></div>
        <div className="mb-7"><span className="mb-3 grid h-12 w-12 place-items-center rounded-2xl bg-orange-100 text-orange-deep"><ShieldCheck size={23} /></span><h2 className="text-2xl font-extrabold">چوونەژوورەوە</h2><p className="mt-2 text-sm text-taupe">تەنها هەژماری پەسەندکراوی بەڕێوەبەر ڕێگەی پێدەدرێت.</p></div>
        <label className="mb-2 block text-sm font-bold">ئیمەیڵ</label><div className="clay-inset mb-4 flex items-center gap-3 px-3"><span className="text-taupe">@</span><input required type="email" value={email} onChange={(event) => setEmail(event.target.value)} className="soft-focus w-full bg-transparent py-3 text-sm" placeholder="admin@example.com" autoComplete="username" /></div>
        <label className="mb-2 block text-sm font-bold">وشەی نهێنی</label><div className="clay-inset mb-5 flex items-center gap-3 px-3"><span className="text-taupe">••</span><input required type="password" value={password} onChange={(event) => setPassword(event.target.value)} className="soft-focus w-full bg-transparent py-3 text-sm" placeholder="وشەی نهێنی" autoComplete="current-password" /></div>
        {(message || accessError) && <div className="mb-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{message || accessError}</div>}
        <button disabled={busy} className="clay-orange flex w-full items-center justify-center gap-2 py-3.5 font-extrabold">{busy ? <RefreshCw className="animate-spin" size={18} /> : <ShieldCheck size={18} />}{busy ? 'پشکنین...' : 'چوونەژوورەوە'}</button>
        <p className="mt-5 text-center text-xs leading-6 text-taupe">هەژماری بەڕێوەبەر لە Supabase SQL Editor بە ڕۆڵی <code>admin</code> چالاک دەکرێت.</p>
      </form>
    </div>
  </div>;
}

function OverviewPanel({ client, notify }: { client: SupabaseClient; notify: (message: string) => void }) {
  const [summary, setSummary] = useState<AdminSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await client.rpc('admin_dashboard_summary');
    if (error) notify(error.message);
    else setSummary(data as AdminSummary);
    setLoading(false);
  }, [client, notify]);
  useEffect(() => { void load(); }, [load]);
  const metrics = [
    { title: 'داواکاریی ئەمڕۆ', value: summary?.today_orders ?? 0, icon: Activity, tint: 'bg-orange-100 text-orange-deep', suffix: 'داواکاری' },
    { title: 'داواکاریی ئەم مانگە', value: summary?.month_orders ?? 0, icon: FileText, tint: 'bg-purple-100 text-purple-700', suffix: 'داواکاری' },
    { title: 'فرۆشی ئەمڕۆ', value: formatIqd(summary?.today_gmv_iqd), icon: Banknote, tint: 'bg-green-100 text-green-700' },
    { title: 'فرۆشی ئەم مانگە', value: formatIqd(summary?.month_gmv_iqd), icon: Banknote, tint: 'bg-green-100 text-green-700' },
    { title: 'کۆمسیۆنی گشتیی پلاتفۆرم', value: formatIqd(summary?.lifetime_commission_iqd), icon: Wallet, tint: 'bg-[#ffe5d2] text-orange-deep' },
  ];
  return <div className="space-y-6">
    <div className="flex flex-wrap items-end justify-between gap-3"><div><p className="text-sm font-semibold text-taupe">بەخێربێیتەوە</p><h2 className="mt-1 text-2xl font-extrabold">پوختەی بازاڕ</h2></div><button onClick={() => void load()} className="clay-card flex items-center gap-2 px-4 py-2.5 text-sm font-bold text-taupe"><RefreshCw size={16} className={loading ? 'animate-spin text-orange' : ''} />نوێکردنەوە</button></div>
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{metrics.map(({ title, value, icon: Icon, tint, suffix }) => <MetricCard key={title} title={title} value={loading ? '…' : value} icon={<Icon size={21} />} tint={tint} suffix={suffix} />)}</div>
    <div className="grid gap-5 xl:grid-cols-[1.5fr_1fr]">
      <div className="clay-card p-5 sm:p-6"><div className="mb-5 flex items-center justify-between"><div><h3 className="font-extrabold">چاودێریی خێرا</h3><p className="mt-1 text-xs text-taupe">دۆخی گەشتی داواکاری و دوکانەکان</p></div><span className="grid h-10 w-10 place-items-center rounded-2xl bg-peach text-orange-deep"><Truck size={19} /></span></div>
        <div className="grid gap-3 sm:grid-cols-2"><QuickTile label="داواکاریی چالاک" value={summary?.active_orders ?? 0} icon={<Clock3 size={17} />} /><QuickTile label="دوکانی چاوەڕوان" value={summary?.pending_stores ?? 0} icon={<Store size={17} />} /></div>
        <div className="mt-5 rounded-2xl bg-peach/65 p-4"><div className="mb-2 flex items-center gap-2 text-sm font-bold"><BadgeCheck size={17} className="text-green" />کۆمسیۆنی مانگانە</div><div className="text-2xl font-extrabold text-orange-deep">{formatIqd(summary?.month_commission_iqd)}</div><p className="mt-1 text-xs text-taupe">هەژمارکراو لەسەر داواکارییە گەیەندراوەکان</p></div>
      </div>
      <div className="clay-card p-5 sm:p-6"><h3 className="font-extrabold">پاراستنی سیستەم</h3><p className="mt-1 text-xs text-taupe">کۆنتڕۆڵی گرنگ لەلایەن PostgreSQL</p><div className="mt-5 space-y-3"><SecurityLine text="کۆمسیۆن لە سێرڤەر هەژمار دەکرێت" /><SecurityLine text="RLS لەسەر هەموو خشتەکان چالاکە" /><SecurityLine text="ژمارەی کڕیار تا قبووڵکردن شاراوەیە" /><SecurityLine text="پاکتاو لە ledger ـی بێ‌گۆڕان تۆمار دەکرێت" /></div></div>
    </div>
  </div>;
}

function MetricCard({ title, value, icon, tint, suffix }: { title: string; value: ReactNode; icon: ReactNode; tint: string; suffix?: string }) {
  return <div className="clay-card p-5"><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-semibold text-taupe">{title}</p><div className="mt-3 text-2xl font-extrabold leading-tight">{value}</div>{suffix && <p className="mt-1 text-xs text-taupe">{suffix}</p>}</div><span className={`grid h-11 w-11 shrink-0 place-items-center rounded-2xl ${tint}`}>{icon}</span></div></div>;
}
function QuickTile({ label, value, icon }: { label: string; value: number; icon: ReactNode }) { return <div className="clay-inset flex items-center gap-3 p-3"><span className="grid h-9 w-9 place-items-center rounded-xl bg-white text-orange-deep shadow-sm">{icon}</span><div><p className="text-xs text-taupe">{label}</p><p className="font-extrabold">{value}</p></div></div>; }
function SecurityLine({ text }: { text: string }) { return <div className="flex items-center gap-2 text-xs"><span className="grid h-6 w-6 place-items-center rounded-full bg-green-100 text-green-700"><Check size={14} /></span><span className="text-taupe">{text}</span></div>; }

function StoresPanel({ client, notify }: { client: SupabaseClient; notify: (message: string) => void }) {
  const [stores, setStores] = useState<StoreRow[]>([]);
  const [financials, setFinancials] = useState<Record<string, FinancialRow>>({});
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [savingId, setSavingId] = useState('');
  const [drafts, setDrafts] = useState<Record<string, Partial<StoreRow>>>({});
  const load = useCallback(async () => {
    setLoading(true);
    const [storeResult, financialResult] = await Promise.all([
      client.rpc('admin_list_stores'),
      client.from('store_financial_summary').select('*'),
    ]);
    if (storeResult.error) notify(storeResult.error.message);
    if (financialResult.error) notify(financialResult.error.message);
    const nextStores = (storeResult.data ?? []) as StoreRow[];
    const nextFinance = Object.fromEntries((financialResult.data ?? []).map((row) => [row.store_id, row as FinancialRow]));
    setStores(nextStores);
    setFinancials(nextFinance);
    setDrafts(Object.fromEntries(nextStores.map((store) => [store.id, { ...store }])));
    setLoading(false);
  }, [client, notify]);
  useEffect(() => { void load(); }, [load]);
  const visible = useMemo(() => stores.filter((store) => `${store.name} ${store.city}`.toLowerCase().includes(search.toLowerCase())), [stores, search]);

  async function toggleApproval(store: StoreRow) {
    setSavingId(store.id);
    const { error } = await client.rpc('admin_set_store_approval', { p_store_id: store.id, p_is_approved: !store.is_approved });
    if (error) notify(error.message);
    else { notify(!store.is_approved ? 'دوکان پەسەندکرا؛ ڕۆڵی خاوەنەکە نوێ کرایەوە.' : 'دوکان ڕاگیرا.'); await load(); }
    setSavingId('');
  }

  async function saveSettings(store: StoreRow) {
    const draft = drafts[store.id] ?? store;
    setSavingId(store.id);
    const { error } = await client.rpc('admin_update_store_financials', {
      p_store_id: store.id,
      p_commission_type: draft.commission_type ?? store.commission_type,
      p_commission_value: Number(draft.commission_value ?? store.commission_value),
      p_delivery_mode: draft.delivery_mode ?? store.delivery_mode,
      p_delivery_fee_iqd: Number(draft.delivery_fee_iqd ?? store.delivery_fee_iqd),
    });
    if (error) notify(error.message);
    else { notify('ڕێژەی کۆمسیۆن و گەیاندن نوێ کرانەوە.'); await load(); }
    setSavingId('');
  }
  function setDraft(id: string, field: keyof StoreRow, value: string | number) {
    setDrafts((previous) => ({ ...previous, [id]: { ...previous[id], [field]: value } }));
  }

  return <div className="space-y-5">
    <div className="flex flex-wrap items-end justify-between gap-3"><div><h2 className="text-2xl font-extrabold">دوکان و کۆمسیۆن</h2><p className="mt-1 text-sm text-taupe">پەسەندکردن، ڕێژەی جێگیر یان سەدی، و شێوازی گەیاندن</p></div><div className="flex gap-2"><div className="clay-inset flex items-center gap-2 px-3"><Search size={16} className="text-taupe" /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="گەڕان بە ناوی دوکان..." className="w-44 bg-transparent py-2.5 text-sm outline-none" /></div><button onClick={() => void load()} className="clay-card p-3 text-taupe" title="نوێکردنەوە"><RefreshCw size={17} className={loading ? 'animate-spin' : ''} /></button></div></div>
    {loading && stores.length === 0 ? <LoadingCard label="دوکانەکان دەهێنرێن..." /> : visible.length === 0 ? <EmptyCard title="دوکانێک نەدۆزرایەوە" /> : <div className="grid gap-4 xl:grid-cols-2">{visible.map((store) => {
      const draft = drafts[store.id] ?? store;
      const finance = financials[store.id];
      return <article key={store.id} className="clay-card p-5">
        <div className="flex flex-wrap items-start justify-between gap-3"><div className="flex items-center gap-3"><span className="clay-icon h-12 w-12"><Store size={21} /></span><div><h3 className="font-extrabold">{store.name}</h3><p className="text-xs text-taupe">{store.city || 'شار دیاری نەکراوە'} · {store.is_open ? 'کراوە' : 'داخراو'}</p></div></div><StatusPill approved={store.is_approved} /></div>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <label className="text-xs font-bold text-taupe">جۆری کۆمسیۆن<select value={draft.commission_type} onChange={(event) => setDraft(store.id, 'commission_type', event.target.value)} className="clay-inset mt-1.5 w-full px-3 py-2.5 text-sm text-espresso"><option value="percentage">ڕێژە ٪</option><option value="fixed_iqd">بڕی جێگیر د.ع</option></select></label>
          <label className="text-xs font-bold text-taupe">نرخ / بڕ<input min="0" max={draft.commission_type === 'percentage' ? 100 : undefined} step={draft.commission_type === 'percentage' ? '0.01' : '1'} type="number" value={draft.commission_value} onChange={(event) => setDraft(store.id, 'commission_value', Number(event.target.value))} className="clay-inset mt-1.5 w-full px-3 py-2.5 text-sm text-espresso" /></label>
          <label className="text-xs font-bold text-taupe">گەیاندن<select value={draft.delivery_mode} onChange={(event) => setDraft(store.id, 'delivery_mode', event.target.value)} className="clay-inset mt-1.5 w-full px-3 py-2.5 text-sm text-espresso"><option value="platform_driver">شۆفێری ئەپ</option><option value="store_self">گەیاندنی دوکان</option></select></label>
          <label className="text-xs font-bold text-taupe">کرێی گەیاندن · د.ع<input min="0" step="250" type="number" value={draft.delivery_fee_iqd} onChange={(event) => setDraft(store.id, 'delivery_fee_iqd', Number(event.target.value))} className="clay-inset mt-1.5 w-full px-3 py-2.5 text-sm text-espresso" /></label>
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-2xl bg-peach/70 px-3 py-2.5 text-xs"><span className="text-taupe">باڵانسی کۆمسیۆنی نەدراو</span><b className="text-orange-deep">{formatIqd(finance?.current_balance_due_iqd)}</b><span className="mr-auto text-taupe">{finance?.total_delivered_orders ?? 0} داواکاری گەیەندراو</span></div>
        <div className="mt-4 flex flex-wrap gap-2"><button disabled={savingId === store.id} onClick={() => void toggleApproval(store)} className={`rounded-full px-4 py-2.5 text-xs font-extrabold ${store.is_approved ? 'border border-red-200 bg-red-50 text-red-700' : 'clay-orange'}`}>{savingId === store.id ? 'چاوەڕوان...' : store.is_approved ? 'ڕاگرتنی دوکان' : 'پەسەندکردنی دوکان'}</button><button disabled={savingId === store.id} onClick={() => void saveSettings(store)} className="rounded-full border border-[#e9dacc] bg-white px-4 py-2.5 text-xs font-extrabold text-espresso hover:bg-peach">پاشەکەوتی ڕێکخستن</button></div>
      </article>;
    })}</div>}
  </div>;
}

function OrdersPanel({ client, notify }: { client: SupabaseClient; notify: (message: string) => void }) {
  const [orders, setOrders] = useState<Record<string, any>[]>([]);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('all');
  const load = useCallback(async () => {
    const { data, error } = await client.from('orders').select('id,order_number,status,subtotal_iqd,delivery_fee_iqd,total_iqd,commission_amount_iqd,created_at,store:stores!orders_store_id_fkey(name),buyer:profiles!orders_buyer_id_fkey(full_name)').order('created_at', { ascending: false }).limit(150);
    if (error) notify(error.message);
    else setOrders((data ?? []) as Record<string, any>[]);
    setLoading(false);
  }, [client, notify]);
  useEffect(() => {
    void load();
    const channel = client.channel('admin-live-orders').on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, () => void load()).subscribe();
    return () => { void client.removeChannel(channel); };
  }, [client, load]);
  const visible = orders.filter((order) => {
    const matchesStatus = status === 'all' || order.status === status;
    const matchesQuery = `${order.order_number} ${order.store?.name ?? ''} ${order.buyer?.full_name ?? ''}`.toLowerCase().includes(query.toLowerCase());
    return matchesStatus && matchesQuery;
  });
  return <div className="space-y-5">
    <div className="flex flex-wrap items-end justify-between gap-3"><div><h2 className="text-2xl font-extrabold">چاودێری داواکاری</h2><p className="mt-1 text-sm text-taupe">تا ١٥٠ داواکاریی دواوە · نوێکردنەوەی Realtime</p></div><div className="flex gap-2"><div className="clay-inset flex items-center gap-2 px-3"><Search size={16} className="text-taupe" /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="ژمارە، دوکان، کڕیار..." className="w-44 bg-transparent py-2.5 text-sm outline-none" /></div><button onClick={() => void load()} className="clay-card p-3 text-taupe"><RefreshCw size={17} /></button></div></div>
    <div className="flex flex-wrap gap-2">{[['all', 'هەموو'], ['pending', 'چاوەڕوان'], ['preparing', 'ئامادەکردن'], ['on_the_way', 'لە ڕێگا'], ['delivered', 'گەیەندرا']].map(([key, label]) => <button key={key} onClick={() => setStatus(key)} className={`rounded-full px-4 py-2 text-xs font-bold ${status === key ? 'clay-orange' : 'clay-card text-taupe'}`}>{label}</button>)}</div>
    {loading && orders.length === 0 ? <LoadingCard label="داواکارییەکان دەهێنرێن..." /> : visible.length === 0 ? <EmptyCard title="هیچ داواکارییەک نییە" /> : <div className="clay-card overflow-hidden"><div className="overflow-x-auto"><table className="w-full min-w-[850px] text-right text-sm"><thead className="bg-peach/70 text-xs text-taupe"><tr><th className="px-4 py-3">ژمارە</th><th className="px-4 py-3">دوکان</th><th className="px-4 py-3">کڕیار</th><th className="px-4 py-3">دۆخ</th><th className="px-4 py-3">کۆی داواکاری</th><th className="px-4 py-3">کۆمسیۆن</th><th className="px-4 py-3">کات</th></tr></thead><tbody className="divide-y divide-[#efe6dc]">{visible.map((order) => <tr key={order.id} className="hover:bg-white/60"><td className="px-4 py-3 font-extrabold">#{order.order_number}</td><td className="px-4 py-3">{order.store?.name ?? '—'}</td><td className="px-4 py-3">{order.buyer?.full_name || 'کڕیار'}</td><td className="px-4 py-3"><StatusPill status={order.status} /></td><td className="px-4 py-3 font-bold">{formatIqd(order.total_iqd)}</td><td className="px-4 py-3 font-bold text-orange-deep">{formatIqd(order.commission_amount_iqd)}</td><td className="px-4 py-3 text-xs text-taupe">{new Date(order.created_at).toLocaleString('ckb-IQ')}</td></tr>)}</tbody></table></div></div>}
  </div>;
}

function SettlementsPanel({ client, notify }: { client: SupabaseClient; notify: (message: string) => void }) {
  const [financials, setFinancials] = useState<FinancialRow[]>([]);
  const [history, setHistory] = useState<Record<string, any>[]>([]);
  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [directions, setDirections] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [savingId, setSavingId] = useState('');
  const load = useCallback(async () => {
    setLoading(true);
    const [summaryResult, historyResult] = await Promise.all([
      client.from('store_financial_summary').select('*').order('current_balance_due_iqd', { ascending: false }),
      client.from('settlements').select('id,store_id,amount_iqd,direction,note,created_at,store:stores!settlements_store_id_fkey(name)').order('created_at', { ascending: false }).limit(100),
    ]);
    if (summaryResult.error) notify(summaryResult.error.message);
    if (historyResult.error) notify(historyResult.error.message);
    setFinancials((summaryResult.data ?? []) as FinancialRow[]);
    setHistory((historyResult.data ?? []) as Record<string, any>[]);
    setLoading(false);
  }, [client, notify]);
  useEffect(() => { void load(); }, [load]);

  async function record(row: FinancialRow) {
    const amount = Number(amounts[row.store_id]);
    if (!Number.isInteger(amount) || amount <= 0) { notify('بڕێکی دروستی دینار بنووسە.'); return; }
    setSavingId(row.store_id);
    const { error } = await client.rpc('record_settlement', {
      p_store_id: row.store_id,
      p_amount_iqd: amount,
      p_direction: directions[row.store_id] ?? 'store_paid_platform',
      p_note: 'پاکتاوی نەختینەیی',
    });
    if (error) notify(error.message);
    else { notify('پاکتاو بە سەرکەوتوویی تۆمار کرا.'); setAmounts((previous) => ({ ...previous, [row.store_id]: '' })); await load(); }
    setSavingId('');
  }

  return <div className="space-y-6">
    <div className="flex flex-wrap items-end justify-between gap-3"><div><h2 className="text-2xl font-extrabold">پاکتاوکردنی حیسابات</h2><p className="mt-1 text-sm text-taupe">پارەی کۆمسیۆن لەسەر داواکارییە گەیەندراوەکان هەژمار دەکرێت.</p></div><button onClick={() => void load()} className="clay-card flex items-center gap-2 px-4 py-2.5 text-sm font-bold text-taupe"><RefreshCw size={16} className={loading ? 'animate-spin' : ''} />نوێکردنەوە</button></div>
    {loading && financials.length === 0 ? <LoadingCard label="باڵانسەکان دەهێنرێن..." /> : financials.length === 0 ? <EmptyCard title="هیچ دوکانێک نییە" /> : <div className="grid gap-4 xl:grid-cols-2">{financials.map((row) => <article key={row.store_id} className="clay-card p-5">
      <div className="flex items-center gap-3"><span className="clay-icon h-11 w-11"><Wallet size={20} /></span><div className="min-w-0"><h3 className="truncate font-extrabold">{row.store_name}</h3><p className="text-xs text-taupe">{row.total_delivered_orders} داواکاریی گەیەندراو · فرۆش {formatIqd(row.gross_sales_iqd)}</p></div><div className="mr-auto text-left"><p className="text-[10px] text-taupe">باڵانسی ماوە</p><p className="font-extrabold text-orange-deep">{formatIqd(row.current_balance_due_iqd)}</p></div></div>
      <div className="mt-4 grid gap-2 sm:grid-cols-[1fr_1.2fr_auto]">
        <select value={directions[row.store_id] ?? 'store_paid_platform'} onChange={(event) => setDirections((previous) => ({ ...previous, [row.store_id]: event.target.value }))} className="clay-inset px-3 py-2.5 text-xs"><option value="store_paid_platform">دوکان پارەی کۆمسیۆنیدا</option><option value="platform_paid_store">پلاتفۆرم پارەی داوە</option></select>
        <input type="number" min="1" step="1000" value={amounts[row.store_id] ?? ''} onChange={(event) => setAmounts((previous) => ({ ...previous, [row.store_id]: event.target.value }))} placeholder="بڕ بە دینار" className="clay-inset px-3 py-2.5 text-sm outline-none" />
        <button disabled={savingId === row.store_id} onClick={() => void record(row)} className="clay-orange flex items-center justify-center gap-2 px-4 py-2.5 text-xs font-extrabold">{savingId === row.store_id ? <RefreshCw size={15} className="animate-spin" /> : <Check size={15} />}تۆمارکردن</button>
      </div>
    </article>)}</div>}
    <section className="clay-card overflow-hidden"><div className="flex items-center justify-between px-5 py-4"><div><h3 className="font-extrabold">مێژووی پاکتاو</h3><p className="text-xs text-taupe">١٠٠ مامەڵەی دواوە</p></div><span className="grid h-10 w-10 place-items-center rounded-2xl bg-green-100 text-green-700"><ArrowUpRight size={19} /></span></div>
      {history.length === 0 ? <p className="px-5 pb-5 text-sm text-taupe">هێشتا مامەڵەیەک تۆمار نەکراوە.</p> : <div className="overflow-x-auto"><table className="w-full min-w-[650px] text-right text-sm"><thead className="bg-peach/70 text-xs text-taupe"><tr><th className="px-5 py-3">دوکان</th><th className="px-5 py-3">ئاراستە</th><th className="px-5 py-3">بڕ</th><th className="px-5 py-3">تێبینی</th><th className="px-5 py-3">کات</th></tr></thead><tbody className="divide-y divide-[#efe6dc]">{history.map((item) => <tr key={item.id}><td className="px-5 py-3 font-bold">{item.store?.name ?? 'دوکان'}</td><td className="px-5 py-3"><span className="inline-flex items-center gap-1 text-xs">{item.direction === 'store_paid_platform' ? <><ArrowDownLeft size={14} className="text-green" />دوکانیدا</> : <><ArrowUpRight size={14} className="text-purple-600" />پلاتفۆرمیدا</>}</span></td><td className="px-5 py-3 font-extrabold">{formatIqd(item.amount_iqd)}</td><td className="px-5 py-3 text-xs text-taupe">{item.note || '—'}</td><td className="px-5 py-3 text-xs text-taupe">{new Date(item.created_at).toLocaleString('ckb-IQ')}</td></tr>)}</tbody></table></div>}
    </section>
  </div>;
}

function LoadingCard({ label }: { label: string }) { return <div className="clay-card flex items-center justify-center gap-3 p-10 text-sm text-taupe"><RefreshCw size={18} className="animate-spin text-orange" />{label}</div>; }
function EmptyCard({ title }: { title: string }) { return <div className="clay-card flex flex-col items-center p-10 text-center"><span className="mb-3 grid h-14 w-14 place-items-center rounded-2xl bg-peach text-orange-deep"><CircleAlert size={24} /></span><p className="font-bold">{title}</p></div>; }

export default App;
