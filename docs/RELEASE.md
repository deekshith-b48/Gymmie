# Releasing the Android app

## One-time setup

1. **Application id.** `app.gymmie.android` (set in `android/app/build.gradle.kts` and the Kotlin package). It cannot change after the first
   Play upload. If you want your own domain-based id, change it now: build.gradle.kts (namespace, applicationId), the folder
   `android/app/src/main/kotlin/app/gymmie/android` and the `package` lines in it, and `Reminders.ACTION`.
2. **Upload key.**
   ```bash
   keytool -genkeypair -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
   Keep the file and its passwords in a password manager (losing the upload key is recoverable through Play support; losing the app signing
   key is not, so enable Play App Signing). Create `android/key.properties` (git-ignored):
   ```
   storeFile=../upload-keystore.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
   A release build without it fails on purpose.
3. **Your website.** Privacy policy, terms, refund policy, help and an account-deletion page at one domain. Drafts are in `docs/legal/`.
   Build with `--dart-define=SITE_URL=https://your-domain` so the app links to them.
4. **Firebase (optional).** Push is not wired; skip it for v1.

## Every release

```bash
# bump `version:` in pubspec.yaml (name+build, the build number must rise each upload)
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=API_BASE_URL=https://api.your-domain --dart-define=SITE_URL=https://your-domain
```

Upload `build/app/outputs/bundle/release/app-release.aab` and keep `build/symbols` (needed to read crash stack traces).
Tagging `vX.Y.Z` does the same in CI (`.github/workflows/ci.yml`; set the repository secrets listed there).

## Play Console checklist

- Data safety: phone number, name, email, health information (PAR-Q forms), photos, contacts (read, for picking a member), crash logs (only if you set a Sentry DSN). Data is encrypted in transit; users can request deletion (in app and on the web page).
- Health apps declaration and content rating; target audience 18+ (gym operators) with members of any age handled by the gym.
- Privacy policy URL, account deletion URL (`/delete-account`), support email.
- Store listing: use the brand in `assets/brand/`. Screenshots from the real app; no screenshots of other products.
- Testing: a closed-testing track first. New personal developer accounts are currently required to run a closed test with a minimum number of testers for a minimum number of days before production access; check the current numbers in Play Console.
- Source code: this app is AGPL. Keep the public repository up to date with what you ship (the in-app notices point to it).

## Before the first public build

- [ ] `grep -ri dgymbook .` finds only the accepted legacy ID-card scheme (`attendance.js`, `scan_screen.dart`) and its tests.
- [ ] `docs/legal` drafts reviewed by a lawyer, published, and `SITE_URL` set.
- [ ] Exercise pictures: leave `EXERCISE_MEDIA_LICENSED` unset unless you hold a licence.
- [ ] Release APK installed on a real phone: sign in as an owner and as a member, pay a test order in Razorpay test mode.
