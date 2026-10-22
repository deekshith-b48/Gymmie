# Releasing the Android app

## One-time setup

1. **Application id.** `app.gymmie.android` (set in `android/app/build.gradle.kts` and the Kotlin package). It cannot change after the first
   Play upload. If you want your own domain-based id, change it now: build.gradle.kts (namespace, applicationId), the folder
   `android/app/src/main/kotlin/app/gymmie/android` and the `package` lines in it, and `Reminders.ACTION`.
2. **Upload key.**
   ```bash
   sh tool/make-upload-keystore.sh      # creates android/upload-keystore.jks and android/key.properties
   ```
   (or by hand: `keytool -genkeypair -v -keystore android/upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`)
   Keep the file and its passwords in a password manager (losing the upload key is recoverable through Play support; losing the app signing
   key is not, so enable Play App Signing). Create `android/key.properties` (git-ignored):
   ```
   storeFile=upload-keystore.jks      # relative to android/
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
   A release build without it fails on purpose.
3. **Your website.** Privacy policy, terms, refund policy, help and an account-deletion page at one domain. Drafts are in `docs/legal/`.
   Build with `--dart-define=SITE_URL=https://your-domain` so the app links to them.
4. **Firebase (optional).** Push is not wired; skip it for v1.

## Which key signs a release

A release build is signed with the **upload key** named in `android/key.properties` (git-ignored; created by `tool/make-upload-keystore.sh`; in CI written
from the secrets `UPLOAD_KEYSTORE_B64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`). Without it the build **fails** ("android/key.properties is missing"):
the debug key is only used when you pass `-PallowDebugSigning=true` for a local test build, which must never be uploaded. Both behaviours were checked by hand for 2.0.2 (a build with no key
exits 1; a build with a throw-away key signed with that key, not the debug key). Check any APK or AAB before you upload it:

```bash
$ANDROID_HOME/build-tools/<version>/apksigner verify --print-certs app-release.apk     # the DN must be your upload key, never "Android Debug"
```

Google Play re-signs with the app signing key it holds (turn on Play App Signing); you only guard the upload key. Never commit, paste or email the `.jks` or its passwords.

## Every release

Production builds have no manual server selection, hidden developer unlock, or developer routes. They ignore saved server overrides
from earlier test builds. Deploy the backend first and supply its final HTTPS address with `API_BASE_URL`; Gradle rejects release builds
without it, including local releases signed with a debug key. Normal debug builds retain emulator/server tools.

CI uses Flutter 3.47.7 and fails tagged releases if signing material or valid HTTPS API/site URLs are missing. Set optional `SENTRY_DSN`
for crash reporting; CI supplies the exact GitHub source revision through `OPENGYM_SOURCE_URL`. Ensure that source URL is accessible
to recipients; a private repository link alone does not provide source access.

```bash
# bump `version:` in pubspec.yaml (name+build, the build number must rise each upload) and "version" in backend/package.json; update CHANGELOG.md
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=API_BASE_URL=https://api.your-domain --dart-define=SITE_URL=https://your-domain
# then: apksigner verify --print-certs build/app/outputs/flutter-apk/*.apk (APK builds) / jarsigner -verify -certs the .aab
```

Upload `build/app/outputs/bundle/release/app-release.aab` and keep `build/symbols` (needed to read crash stack traces).
Tagging `vX.Y.Z` does the same in CI (`.github/workflows/ci.yml`; set the repository secrets listed there).

## Play Console checklist

- Data safety: phone number, name, email, health information (PAR-Q forms), photos, crash logs (only if you set a Sentry DSN). Data is encrypted in transit; users can request deletion (in app and on the web page).
- Health apps declaration and content rating; target audience 18+ (gym operators) with members of any age handled by the gym.
- Privacy policy URL, account deletion URL (`/delete-account`), support email.
- Store listing: use the brand in `assets/brand/`. Screenshots from the real app; no screenshots of other products.
- Testing: a closed-testing track first. New personal developer accounts are currently required to run a closed test with a minimum number of testers for a minimum number of days before production access; check the current numbers in Play Console.
- Source code: this app is AGPL. Keep the public repository up to date with what you ship (the in-app notices point to it).

## Before the first public build

- [ ] `grep -ri dgymbook .` finds only the accepted legacy ID-card scheme (`attendance.js`, `scan_screen.dart`) and its tests.
- [ ] `docs/legal` drafts reviewed by a lawyer, published, and `SITE_URL` set.
- [ ] Exercise pictures: leave `EXERCISE_MEDIA_LICENSED` unset unless you hold a licence.
- [ ] Release APK installed on a real phone: sign in as an owner and as a member, pay a test order in Razorpay test mode (against the staging server, see docs/DEPLOY.md "Staging first").
- [ ] Merged manifest checked (`aapt dump permissions`): only internet, network state, camera, notifications, boot, vibrate and wake lock. No contacts, advertising-ID or push permissions.
