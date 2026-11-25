# Yousf Local Marketplace

A Sorani Kurdish, RTL local marketplace and COD ordering starter for buyers, stores/restaurants, optional drivers, and administrators. The repository is organized as a small monorepo:

- `supabase/` — PostgreSQL schema, RLS, order/commission/settlement RPCs, category seeds, and an optional FCM Edge Function.
- `flutter_app/` — one Flutter/Dart app for Android and iOS: buyer discovery/cart/checkout, live order tracking/chat, seller dashboard, driver view, profile, image upload, and the warm 3D claymorphism component kit.
- `admin_web/` — React + Vite + Tailwind Sorani RTL admin panel for approvals, commission/delivery settings, live order monitoring, and cash settlements.

## 1. Create and configure Supabase

1. Create a Supabase project on the Free plan. Keep the **service-role key private**; it is never used by Flutter or the browser admin panel.
2. Open **SQL Editor** and run these files, in this order, from the repository root:
   1. `supabase/schema.sql`
   2. `supabase/functions.sql`
   3. `supabase/rls.sql`
   4. `supabase/seed.sql`
3. The schema creates the tables, indexes, Realtime publication entries for `orders` and `messages`, and the `store_financial_summary` view. `functions.sql` installs the auth profile trigger and trusted RPCs. `rls.sql` enables table policies, creates the public `marketplace-images` Storage bucket, and scopes image uploads to each user's own folder.
4. In **Authentication → Providers**, enable Email and Google if Google sign-in is wanted. Email/password is the default and does not use paid SMS OTP. Set the Supabase Auth redirect allow-list to include `io.supabase.marketplace://login-callback/` for the mobile OAuth callback, plus the deployed admin-panel URL.

### Create the first administrator

Create the first user using the app's Email/Password signup or **Authentication → Users**. The auth trigger creates a `profiles` row with role `buyer`. Then, in SQL Editor, promote that account by email:

```sql
update public.profiles p
set role = 'admin', is_active = true
where p.id = (
  select u.id from auth.users u
  where lower(u.email) = lower('admin@example.com')
);

select id, full_name, role, is_active
from public.profiles
where role = 'admin';
```

Replace the example email with the account you created. The browser admin checks this database role at sign-in, and its privileged actions call admin-only RPCs. RLS remains the actual authorization boundary. When a store is approved, `admin_set_store_approval` promotes its owner from `buyer` to `seller`.

To enable an optional driver, create their account first, then set the role from the SQL Editor (never expose a client-side role picker):

```sql
update public.profiles p
set role = 'driver'
where p.id = (select u.id from auth.users u where lower(u.email) = lower('driver@example.com'));
```

A store owner/admin assigns active drivers to accepted/preparing orders from the seller dashboard. Drivers only see orders assigned to their profile.

### Optional FCM push notifications

FCM token storage in `profiles.fcm_token` is wired in Flutter. The optional Edge Function sends a push on new orders, status changes, and driver assignment; in-app order/chat updates use Supabase Realtime without FCM.

1. Create a Firebase project, add the Android/iOS app IDs, and install Firebase's native configuration files locally (they are git-ignored). Grant the Firebase service account the Firebase Cloud Messaging API permission.
2. Install the Supabase CLI, link this project, and deploy the function. Configure secrets in the Supabase dashboard or CLI; never commit a service-account JSON or service-role key:

   ```sh
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase secrets set SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=YOUR_PRIVATE_SERVICE_ROLE_KEY
   supabase secrets set WEBHOOK_SECRET=YOUR_LONG_RANDOM_WEBHOOK_SECRET
   supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"project_id":"...","client_email":"...","private_key":"-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----\\n"}'
   supabase functions deploy send-order-notification
   ```
3. In Supabase **Database → Webhooks**, create a webhook for `public.orders` on `INSERT` and `UPDATE`, targeting `https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-order-notification`. Add the header `x-webhook-secret` with the same `WEBHOOK_SECRET`. `supabase/config.toml` disables platform JWT verification for this webhook endpoint; the shared secret is checked by the function.
4. Add the Firebase native config to your local Flutter platform folders and rebuild. If Firebase is not configured, sign-in and in-app Realtime continue working; token registration is skipped safely.

### Image storage

The default Flutter image provider is Supabase Storage. The SQL setup creates a public image bucket with a 120 KiB file limit and write/delete policies scoped to each authenticated user's folder. The Flutter uploader resizes to a maximum 1080 px width, starts at quality 70, and progressively compresses/resizes until the file is below 120 KiB.

To use Cloudinary instead, create an **unsigned upload preset** with a 120 KiB upload limit and allowed image formats. Set `IMAGE_PROVIDER` to `cloudinary` and provide `CLOUDINARY_CLOUD_NAME` and `CLOUDINARY_UPLOAD_PRESET` as Flutter `--dart-define` values. Unsigned presets are public configuration; restrict the preset's formats, size, and folder in Cloudinary.

## 2. Run the Flutter app

Install Flutter 3.24+ / Dart 3+, Android SDK for Android builds, and Xcode for iOS builds. The application source is under `flutter_app/lib`. If this checkout does not yet have generated native platform shells, generate them once with Flutter (this does not replace the Dart app source):

```sh
cd flutter_app
flutter create --platforms=android,ios --org com.yousif .
```

Copy `flutter_app/.env.example` to `flutter_app/.env.json`, replace the Supabase URL and anon key, and keep `.env.json` out of Git. The example is JSON specifically for Flutter's `--dart-define-from-file` option.

```sh
cd flutter_app
flutter pub get
flutter analyze
flutter run --dart-define-from-file=.env.json
```

For a signed Android release APK:

```sh
cd flutter_app
flutter build apk --release --dart-define-from-file=.env.json
# build/app/outputs/flutter-apk/app-release.apk
```

For iOS, configure the generated Runner bundle ID, Apple signing, Firebase files if used, and the OAuth URL scheme, then run `flutter build ipa --release --dart-define-from-file=.env.json`. Because Flutter's generated native shells are SDK-version-specific, add the following plugin permissions/callbacks to the generated files before building:

- Android `android/app/src/main/AndroidManifest.xml`: include `INTERNET`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, and `POST_NOTIFICATIONS` permissions under `<manifest>`. Add a `VIEW`/`DEFAULT`/`BROWSABLE` intent filter to `MainActivity` with `<data android:scheme="io.supabase.marketplace" android:host="login-callback" />`. Set Android `minSdk` to at least 23 when Firebase is enabled.
- iOS `ios/Runner/Info.plist`: add `NSLocationWhenInUseUsageDescription` and a `CFBundleURLTypes` URL scheme of `io.supabase.marketplace` for Supabase OAuth. Use Firebase's `GoogleService-Info.plist` only if push is enabled.

The map uses free OpenStreetMap tiles. Google Maps is opened as an external directions link; no paid Maps SDK is included.

## 3. Run and deploy the admin panel

```sh
cd admin_web
cp .env.example .env
# Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in .env
npm install
npm run dev
```

Production build:

```sh
cd admin_web
npm run build
# Static output: admin_web/dist
```

**Cloudflare Pages (free tier):** create a Pages project from this repository, set the root directory to `admin_web`, build command to `npm run build`, and output directory to `dist`. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as build environment variables. The included `public/_redirects` supports client-side routes.

**Vercel (free tier):** import the repository, set the project root to `admin_web`, framework preset to Vite, build command to `npm run build`, and output directory to `dist`. Add the same two Supabase environment variables. `vercel.json` rewrites app routes to `index.html`.

Only the Supabase **anon** key belongs in Flutter/browser configuration. Supabase RLS and RPC authorization protect data; do not add a service-role key to either client.

## Financial and access rules

- Flutter sends only product IDs and quantities to `quote_order` for the checkout preview and to `create_order` for placement. The database locks and reads authoritative product/store data; the client never computes or submits order subtotal, total, commission, or unit-price amounts. `create_order` inserts the order and financial snapshots atomically.
- Direct client inserts/updates to `orders`, order items, order totals/snapshots, approvals, commissions, and settlements are not granted. Database triggers also protect order and line-item price snapshots and make settlement rows append-only; state changes and ledger inserts use server-side `SECURITY DEFINER` RPCs.
- Store commission configuration is not granted for direct table reads; owners and admins retrieve it through authorized RPCs, while the admin dashboard's store listing is admin-only.
- The buyer phone snapshot is not selectable by client roles. The secure `get_order_buyer_phone` RPC exposes it to the buyer/admin and to the store/assigned driver only after acceptance.
- `store_financial_summary` counts delivered orders only. Settlement rows are append-only from clients and can be written by admins only through `record_settlement`.
- Supabase Free, Cloudinary Free, Firebase/FCM, Cloudflare Pages, and Vercel quotas and terms can change; monitor each provider's current limits.

## Verification

Verification performed in the build sandbox:

- `cd admin_web && npm install && npm run build` — passed TypeScript checking and Vite production build.
- `pglast.parse_sql` — parsed all four SQL files (`schema.sql`, `functions.sql`, `rls.sql`, and `seed.sql`). This does not apply them to a live Supabase database.
- Deno 2.9.6 type-check — passed for `supabase/functions/send-order-notification/index.ts` against Supabase JS 2.49.4.
- Python tree-sitter — parsed every Dart file under `flutter_app/lib` without syntax errors. This is syntax-only, not Dart static analysis.

Flutter/Dart and the Android SDK are not present in this build sandbox, so `flutter pub get`, `flutter analyze`, and the release APK build could not be run here. Run those in an environment with Flutter 3.24+ and Android SDK installed; also test the SQL/RLS against a Supabase project before deployment.
