import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: provide android/key.properties (gitignored) with storeFile, storePassword, keyAlias, keyPassword.
// A release build WITHOUT it fails, so a debug-signed build can never be published by accident. For a local smoke test
// of a release build only, pass -PallowDebugSigning=true.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "app.gymmie.android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.gymmie.android"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // versionName / versionCode (1.9.4 / 1178) come from pubspec.yaml: version: 1.9.4+1178
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Resolved when the build runs (below): a release build without a key fails, a debug build never needs one.
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// A release build must never be signed with the debug key by accident. This runs only when a release task is in the build,
// so debug builds and tests are unaffected.
gradle.taskGraph.whenReady {
    val releaseBuild = allTasks.any { t ->
        t.project == project && (t.name.startsWith("assemble") || t.name.startsWith("bundle") || t.name.startsWith("package")) && t.name.contains("Release")
    }
    if (releaseBuild && !hasReleaseKey) {
        if (project.hasProperty("allowDebugSigning")) {
            logger.warn("WARNING: signing the release build with the DEBUG key (local testing only, never publish it).")
        } else {
            throw GradleException("android/key.properties is missing: create the upload keystore (docs/RELEASE.md) or pass -PallowDebugSigning=true for a local test build.")
        }
    }
}
