# Yousf Local Marketplace

A Sorani Kurdish, RTL local marketplace and COD ordering app. The whole stack runs on this server — no hosted backend service is required.

## Layout

- `database/` — PostgreSQL schema, trusted RPCs, RLS, category seeds, and local auth/storage setup. Apply the files in order (`00_local_base.sql` → `05_local_users.sql`).
- `flutter_app/` — one Flutter/Dart app for Android and iOS: buyer discovery/cart/checkout, live order tracking/chat, seller dashboard, driver view, profile, image upload, and the claymorphism component kit.
- `admin_web/` — React + Vite + Tailwind Sorani RTL admin panel for approvals, commission/delivery settings, live order monitoring, and cash settlements.
- `deploy/yousf-marketplace/` (on the server) — local API gateway, PostgREST config, JWT secret, release automation.

## Local backend

- PostgreSQL 17 (database `marketplace`) holds all data, RLS policies, and `SECURITY DEFINER` RPCs. Financial snapshots and settlement rows are protected by triggers; clients never submit prices or totals.
- PostgREST exposes the database as `/rest/v1/*`.
- A small Node gateway serves `/auth/v1/*`, `/storage/v1/*`, and the admin panel from one origin. It signs HS256 JWTs whose `sub` claim drives `auth.uid()` in RLS.
- Image uploads are written to the local storage directory under the signed-in user's own folder; public reads are unrestricted for product images.
- Order/chat freshness uses lightweight polling instead of a hosted realtime service.

Apply the SQL on a fresh database:

```sh
for f in database/*.sql; do psql -v ON_ERROR_STOP=1 -d marketplace -f "$f"; done
```

## Demo accounts

| Email | Password | Role |
|---|---|---|
| `admin@yousf.local` | `admin123` | admin |
| `seller@yousf.local` | `seller123` | seller |
| `buyer@yousf.local` | `buyer123` | buyer |

Admin panel: `http://<server>:8081` — sign in with the admin account.

## Flutter app

Flutter 3.24+ / Dart 3+ and the Android SDK are required. The app reads `API_URL` at build time:

```sh
cd flutter_app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release \
  --dart-define=API_URL=http://100.112.174.17:8081 \
  --dart-define=IMAGE_PROVIDER=local
```

The generated native Android shell is patched by `.github/scripts/patch_flutter_android.py`. The APK is written to `flutter_app/build/app/outputs/flutter-apk/app-release.apk`.

## Admin panel

```sh
cd admin_web
npm install
npm run build
# Static output: admin_web/dist
```

The panel uses the origin it is served from as the API base URL, so no `VITE_` variables are needed.

## Releases

Every commit triggers a local release hook that rebuilds the APK and publishes a new versioned GitHub Release (`v1.0.0`, `v1.0.1`, …) with the APK attached. The GitHub Actions workflow mirrors the same behavior when Actions are enabled.

## Security notes

- Money is integer IQD and is computed server-side from authoritative product rows.
- Client roles are assigned in trusted SQL only; RLS is the real authorization boundary.
- RLS and least-privilege grants are applied to every table.
- Never commit credentials. The local JWT secret and API token live outside this repository with `0600` permissions.
