# Android v1.0.0-beta.4

Light-only UI redesign: white page and content surfaces, cobalt actions, navy text and restrained corner radii. Routine cards are replaced by unboxed sections and list rows. Home focuses on spending, settlement, accounts and recent transactions, with inline Add/Transfer actions that do not obscure balances. Dark-mode settings are removed.

Background polling is silent. A remote database notification no longer schedules a new network sync unless there are queued local edits. Errors and pending changes remain visible, with manual sync in Settings.

- Flutter analysis: no issues.
- Tests: 68 passed, one opt-in live-backend integration test skipped.
- All 16 routes checked across five language, width and text-scale combinations; empty/extreme records, keyboard sheets and dark-system/light-app behavior checked.
- Screenshots and researched design decisions: [light redesign](ui-ux/light-redesign.md).
- Release APK signature verified with the existing certificate; version code 4, application ID `com.duowallet.app`.
- APK SHA-256: `6f089c3b72d54915e2317dea9ef7ce1e970670d892639ec50cf7b03165bf545b`.
- No physical-device or TalkBack validation. No production data or Auth settings changed for this release.

# Android v1.0.0-beta.3

Simplifies signup and password recovery to one password entry, at least 8 characters, without forced character classes. Sign-in no longer applies signup strength rules. English and Hungarian guidance distinguishes rate limits, unconfirmed email, invalid credentials, server failures and connection timeouts. Signup success explains how existing users can sign in or reset their password.

- Hosted password settings read back after updating: minimum 8, no forced character classes; email verification remains enabled.
- Live disposable-user check: 8 lowercase letters accepted for login; 7-character signup rejected; test account removed without sending email.
- Focused Auth UI and security tests: 11 passed. Flutter analysis: no issues.
- Signed release APK built with existing production configuration. Physical-device install and inbox delivery remain unverified.
- Version code 3; application ID `com.duowallet.app`; signing certificate unchanged from beta.1 and beta.2.
- APK SHA-256: `b7c69d7547e23cd0f6412a548533c3af5ee81d06329d4c269b431c1aae6aafe1`.

# Android v1.0.0-beta.2

Replaces the Flutter launcher logo with original Duo Wallet artwork across Android launcher densities and adaptive icon masks. Version code 2, application ID `com.duowallet.app`, Android 8.0 and newer.

- Release APK built successfully with the existing production configuration.
- APK signature verified; certificate SHA-256 matches beta.1: `461e7e571415bb4e25d21c05ea062937a41a6f8721ae056b4340f64ac872c72c`.
- APK SHA-256: `6945c8246eccd1334b8816a04318f0fa32daf8430b6e26bf6cb4d45d14459d99`.
- Package metadata confirms version `1.0.0-beta.2` (2) and the adaptive launcher resource.
- Physical-device installation and launcher appearance have not been checked.
- Install over the signed beta.1 to retain app data. Existing beta limits below still apply.

# Android v1.0.0-beta.1

First signed beta APK for Android 8.0 (API 26) and newer. Version code 1, application ID `com.duowallet.app`. Install from the repository's GitHub Releases page. Allow installation from the browser or file manager used to open the download.

## Release checks

- Flutter analysis: no issues.
- Flutter tests: 66 passed; one real-service opt-in test skipped in the default suite and passed separately against the hosted backend.
- Hosted Auth/database/private Storage checks: 29 passed. Confirmation and password-reset emails were received by the owner.
- Release APK signature verified with Android `apksigner`; dedicated RSA 3072-bit release certificate, not a debug key.
- Certificate SHA-256: `461e7e571415bb4e25d21c05ea062937a41a6f8721ae056b4340f64ac872c72c`.
- APK SHA-256: `ef9b8e2fed0e0aca1e884dcdd318a654f60a3fb6dcd6774a44cea848463132a1`.
- Staged source and existing Git history scanned for deployment credentials and live identifiers before publication.
- APK scan confirmed administrator key, signing password and keystore files are absent. The public Supabase URL and publishable client key are necessarily compiled into the working client.

## Credential custody

The production configuration and release keystore remain local and ignored by Git. Signing material is stored outside the checkout under the owner's local application-data directory with restricted permissions. Back up the signing directory securely: future APK updates require that same key. No backend, SMTP or signing credentials were uploaded as GitHub repository secrets. GitHub Actions only runs analysis and tests; release binaries are built locally.

## Beta limits

A physical Android device was not connected during release preparation. Verify email confirmation and password-reset callbacks on the same phone that requested them, then verify sign-out/restart and two-phone synchronization before relying on the app as your only financial record. The custom URL callback has a manifest handler and configured redirect, but real-device operation is not yet certified.

Automatic APK updates and biometric app locking are not implemented. Download subsequent releases manually. A previous debug APK uses a different signing certificate and cannot be updated in place by this release; export any local-only data before removing a debug installation. Free-tier backend availability remains subject to Supabase pausing and email-provider limits.
