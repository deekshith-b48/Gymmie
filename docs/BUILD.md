# Build, run and test (Gymmie)

All commands run from the project root. `source tool/env.sh` first (it puts the arm64 Flutter, JDK 21 and
the Android SDK on `PATH` and sets `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true`).

## One-time machine setup (what was installed here)

| Tool | Version | Location |
|---|---|---|
| Flutter (stable, **arm64** archive) | 3.47.7 / Dart 3.13.5 | `~/development/flutter` |
| JDK (Temurin) | 21.0.12 | `~/development/jdk-21` |
| Android SDK | platforms 34/35/36, build-tools 35/36, platform-tools, emulator, CMake 3.22.1, NDK 28.2 | `~/development/android-sdk` |

> ⚠️ Use the **arm64** Flutter archive on Apple-silicon Macs. An x86_64 SDK runs under Rosetta and every
> `xcrun` call made by native-asset hooks (`objective_c`) and by `flutter assemble` fails with
> *"missing compatible architecture (have 'arm64,arm64e', need 'x86_64')"*. After switching SDKs run
> `./android/gradlew --stop` so no stale Gradle daemon keeps the old architecture.
>
> Xcode itself is **not** required for Android builds.

## Backend (development)

```bash
cd backend
npm test                 # 38 tests, in-memory DB, real HTTP
node src/seed.js --reset # demo gym "Iron Temple Fitness"
node src/server.js       # http://0.0.0.0:8787  (Android emulator reaches it at http://10.0.2.2:8787)
```

Demo logins (development only; the fixed OTP `123456` is refused in production mode):
owner `+919000000001`, manager `+919000000002`, trainer `+919000000003`, staff `+919000000004`.

## App

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <device>                       # debug build talks to http://10.0.2.2:8787 by default
flutter build apk --debug
flutter build apk --release --dart-define=API_BASE_URL=https://your-backend.example.com
```

### `--dart-define` options

| Define | Purpose | Default |
|---|---|---|
| `API_BASE_URL` | Backend root (https required in release) | debug: `http://10.0.2.2:8787`; release: none → the app opens *Backend URL* setup |
| `SENTRY_DSN` | Enables Sentry crash reporting (release builds only) | off |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET` | Enables Firebase (FCM push token registration, Analytics) | off |

No keys, DSNs or Firebase config are compiled into the repository. The values that exist inside the
original APK (Sentry DSN, PostHog key, Firebase client config) were deliberately **not** copied.

### Release signing

Create `android/key.properties` (git-ignored) with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
Without it a release build is signed with the **debug** key and Gradle prints a warning; never distribute that.

## Emulator used for verification

```bash
sdkmanager "system-images;android-35;google_apis;arm64-v8a" "emulator"
avdmanager create avd -n dgymbook_api35 -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_7
emulator -avd dgymbook_api35 -no-window -gpu swiftshader_indirect &
```
