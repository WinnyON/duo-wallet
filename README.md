# Duo Wallet

Android finance app for two people, with English and Hungarian interfaces, shared and private expenses, accounts, budgets, goals, recurring transactions and settlements. Uses Supabase Auth, Postgres row-level security and private backup storage.

## First Android release

Download the APK from [GitHub Releases](https://github.com/WinnyON/duo-wallet/releases). The first version is a beta for Android 8.0 and newer. Open the downloaded APK and permit installation from your browser or file manager when Android asks. Future APKs must be signed with the same release key to update the installed app.

Create an account with your email and a password of at least 8 characters (no required symbols or capitals), verify the email on the same phone, then create a household or join with your partner's invite code. Both partners use separate accounts. Shared expenses sync; personal records stay protected by database access policies. Confirmation and reset emails are configured by the backend operator.

Automated UI, privacy, authentication and storage checks pass. Physical-device verification and reset-link handling still need final validation. There is no automatic in-app updater or biometric app lock in this version. Install later versions from Releases.

## Local development

Use Flutter 3.47.7 and Java 17. From `app/`:

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=DUO_DEMO_MODE=true
```

Demo mode is explicit and isolated from production. A normal build with missing cloud configuration fails closed.

## Production configuration

Copy `app/config/production.example.json` to the ignored `app/config/production.json` and supply your own Supabase URL and publishable client key. Configure verified-email authentication, an 8-character password minimum with no forced character classes, and custom SMTP in your own Supabase project. Never use a service-role key in an application build.

```sh
cd app
flutter build apk --release --dart-define-from-file=config/production.json
```

Release signing requires an ignored `app/android/key.properties` file with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Generate a dedicated Android release keystore and back it up securely outside the repository. Release builds cannot fall back to debug signing.

The repository contains no deployment URL, real API key, SMTP password or signing key. A production APK necessarily includes its public Supabase URL and publishable client key; server-side Auth and RLS enforce access. Administrator and SMTP credentials must never be packaged.

## Database and backend verification

Timestamped migrations in `supabase/migrations/` reproduce the schema and security policies. Historical canonical SQL is retained in `supabase/reference/` for reference, not for replay alongside the migrations. Use Supabase CLI to link your own project, review the pending migrations, and apply them. Do not seed production with demo data.

Run `supabase test db` against a local stack. Real API/storage checks are available in `scripts/verify_supabase.py`; they read credentials from a private JSON file and create/remove disposable test identities. Hosted checks require explicit `--allow-live`. The SDK integration test is opt-in with `SUPABASE_TEST_STATUS_FILE` pointing to an ignored/private Supabase status file.

## GitHub Actions

Pushes, pull requests and version tags run static analysis and tests. Signed release APKs are built locally and uploaded to GitHub Releases. Deployment configuration, SMTP credentials and signing material stay outside GitHub; no repository secrets are required.

There is no scheduled production keep-alive job. Free-tier Supabase availability and pausing must be monitored by the backend operator.

## Reports

- [Detailed UI/UX audit](docs/ui-ux-audit.md)
- [Implementation plan](docs/ui-ux-implementation-plan.md)
- [UI verification](docs/ui-ux-implementation-status.md)
- [Backend verification and remaining checks](docs/supabase-production-status.md)
