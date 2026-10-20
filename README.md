# Duo Wallet

Offline-first, strictly private Android finance app for two people (English & Hungarian, HUF / EUR / RON), backed by a free-tier Supabase Postgres project and installed via sideloaded APK.

---

## Privacy Architecture

Every record is classified by an immutable Postgres trigger into either **Private** (`visibility = 'private'`) or **Shared** (`visibility = 'shared'`):

| Record | Visibility | Notes |
|---|---|---|
| **Individual** expense | 🔒 Private | Never synced to your partner's phone |
| **Together** expense | 👥 Shared | Any split (`0%–100%`). If paid from a personal account, partner sees `"Sam's personal account"`, never the account name or balance |
| Common-account expense | 👥 Shared | Always forced to `scope = 'together'` |
| Personal account / income / valuation / budget / goal | 🔒 Private | Filtered at Postgres Row Level Security (RLS) |
| Common account & contributions (`personal -> common`) | 👥 Shared | Shows contributor and amount, never the source personal account |
| Settle-up proposal & confirmation | 👥 Shared | Both partners must confirm before balance changes; optional own-account balance adjustment (`settlement_postings`) stays private |

- **No in-place scope mutation:** switching an expense between `Individual` and `Together` soft-deletes the old row (`deleted_at`) and inserts a brand-new UUID row so private history never leaks.
- **No foreign key leak:** local `transactions.account_id` has no FK constraint to local `accounts`, allowing shared expenses paid from a partner's unreadable personal account to sync cleanly.

---

## 1. Supabase Setup & Migrations

1. Create a free Supabase project at [supabase.com](https://supabase.com).
2. Link and apply migrations + seed data using the Supabase CLI:
   ```bash
   supabase link --project-ref <YOUR_PROJECT_REF>
   supabase db push
   supabase db execute --file supabase/seed.sql
   ```
3. Deploy the daily ECB exchange-rate Edge Function (`frankfurter.app`):
   ```bash
   supabase functions deploy fetch-fx-rates
   ```
4. Run the pgTAP privacy & integrity test suite:
   ```bash
   supabase test db
   ```

---

## 2. Release Keystore Generation & Backup (Critical for Sideloading)

Android requires every sideloaded APK update (including updates via the in-app updater) to be signed with the **exact same keystore**. Generate it once and back it up securely (e.g. password manager):

```bash
keytool -genkey -v \
  -keystore app/android/app/release-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias duowallet
```

Create `app/android/key.properties` (git-ignored):

```properties
storePassword=<YOUR_STORE_PASSWORD>
keyPassword=<YOUR_KEY_PASSWORD>
keyAlias=duowallet
storeFile=release-keystore.jks
```

---

## 3. Build & Sideload the APK

From `app/`:

```bash
flutter pub get
flutter analyze
flutter test

flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<PROJECT_REF>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<YOUR_SUPABASE_ANON_KEY> \
  --dart-define=RELEASE_MANIFEST_URL=https://<PROJECT_REF>.supabase.co/storage/v1/object/public/releases/latest.json
```

Install `app/build/app/outputs/flutter-apk/app-release.apk` on both phones and allow **Install unknown apps** for Duo Wallet so future in-app OTA updates install seamlessly.

---

## 4. GitHub Actions CI & Keep-Alive

Configure the following repository secrets in GitHub (`Settings -> Secrets and variables -> Actions`):

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RELEASE_KEYSTORE_BASE64` (`base64 -w0 app/android/app/release-keystore.jks`)
- `KEYSTORE_PASSWORD`
- `KEY_PASSWORD`
- `KEY_ALIAS`

Workflows included:
- `.github/workflows/ci.yml` — runs `flutter analyze` and `flutter test` on every push/PR, and builds + uploads the signed APK and `latest.json` on `v*` tags.
- `.github/workflows/keepalive.yml` — pings Supabase REST every 3 days (`0 6 */3 * *`) so the free tier never pauses due to 7 days of inactivity.
