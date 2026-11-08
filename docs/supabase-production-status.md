# Supabase production integration

Duo Wallet uses the existing Supabase project `<PROJECT_REF>`. Its existing Auth account was preserved. The former UI-only status is superseded by this backend integration report.

## Authentication and data protection

Production requires a configured HTTPS Supabase endpoint and publishable client key. Unconfigured builds fail closed; demo data requires explicit `DUO_DEMO_MODE`. Verified email authentication gates financial screens. Signup and password recovery require at least 8 characters, with no mandatory character classes. Sign-in only requires a nonempty password; it does not apply the current signup policy. Supabase performs salted bcrypt password hashing on the server; the application never stores passwords. Email confirmation, secure password changes and email-change confirmation are enabled. Sessions and PKCE verifiers use device secure storage. Financial cache files use AES-GCM with fresh nonces and a per-user encryption key held in secure storage. Android backup is disabled.

Database RLS enforces household membership, private records, two-member households and participant-specific settlement confirmations. Membership and transaction identities cannot be changed by clients. Transaction shares are validated and saved atomically. Activity records are produced by server triggers. Scheduler functions are not callable by ordinary clients. Backups use a private Storage bucket with user-prefixed access policies. Sync preserves unacknowledged changes, retries failed writes and isolates users across session changes.

## Verification completed

Final Flutter suite: 66 passed, one real-service opt-in test skipped in the default run (that test passed separately against the live project). Static analysis passed.

- 20 SQL privacy checks passed on both the migrated hosted-schema replica and a fresh local database.
- Live Auth/API/Storage verification passed 29 checks, including email confirmation enforcement, weak-password rejection, household/private-data isolation, private backup round-trip, forged activity rejection, and different bcrypt hashes for equal test passwords.
- Actual Flutter Supabase SDK integration passed against local and hosted services using disposable users. Existing users were preserved and test data removed.
- Authentication UI tests pass in English and Hungarian at 320 px width, 200% text, with the keyboard open. A missing navigation overlay was corrected.
- Partner transaction edits, settlement confirmation and recurring updates pass through the actual hosted SDK adapter; immutable identities and invalid share rollback remain enforced.
- Backend unit checks cover encryption authentication, nonce variation, user/project separation, durable pending writes, stale-session guards and fail-closed configuration.
- The final Android debug APK compiled using secure-storage 11.2.0; packaged files were scanned and the privileged service-role key was absent. Physical-device keystore, email-link and reset-link interaction still require device verification.

## Email delivery: Gmail SMTP configured

On November 8, a requested confirmation resend returned HTTP 200. A read-only account check found that the reported account was already confirmed and had previously signed in; its confirmation timestamp was empty. A resend response alone does not establish that an email was sent. Direct SMTP probing disconnected and hosted log queries were unavailable, so current end-to-end inbox delivery still needs confirmation. The app now explains the existing-account sign-in/reset path and distinguishes common Auth errors. A disposable confirmed account successfully signed in using eight lowercase letters; seven-character signup was rejected and the test account removed without sending email.

### Previous release verification

The owner selected Gmail instead of Resend because no sender domain is available. Live settings were read back from Supabase: `smtp.gmail.com`, port `465`, SMTP username and sender `<SMTP_SENDER_EMAIL>`, sender display name `Duo Wallet`. An SMTP credential is configured; its value was not printed or committed. Email confirmation remains enabled and minimum password length is now 8 with no forced character classes (verified against the hosted configuration).

Both confirmation resend and password-reset requests returned HTTP 200 using a temporary `<DISPOSABLE_TEST_EMAIL>` test identity. The temporary Auth account was removed afterward. The owner confirmed receipt of both test emails. SMTP delivery is verified; real-account mobile callback interaction remains to be checked. Links in these disposable-account messages are not intended for use after cleanup.

The intended application users remain `<USER_ONE_EMAIL>` and `<USER_TWO_EMAIL>`. The SMTP sender is separate from application login identities and does not need to match the GitHub or Supabase owner address.

## Remaining release checks

Test real-account verification and password-reset callbacks on Android. Inbox delivery of both message types is confirmed by the owner. Leaked-password screening was not enabled; do not describe it as active. Existing authorized security-definer household RPCs remain intentional. No paid plan upgrade or physical-device installation was performed. A signed Android beta is documented in [Android release](android-release.md).

Build with `flutter build apk --debug --dart-define-from-file=config/production.json` from `app/`. The ignored production config contains only the public URL and publishable key. Service-role credentials are for verification tooling only and must never enter an app build.
