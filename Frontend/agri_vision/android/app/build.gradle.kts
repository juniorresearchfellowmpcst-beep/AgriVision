import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload-key signing for Google Play. The keystore and its passwords live in
// android/key.properties, which is git-ignored along with *.jks: neither may
// ever be committed. docs/PLAY_STORE.md says how to create them.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKey = keystorePropertiesFile.exists()

android {
    namespace = "com.mpcst.agrivision"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // The Play package name. PERMANENT once the first build is uploaded:
        // Play will never accept a different one for this listing. It used to
        // be com.example.agri_vision, which Play rejects outright.
        applicationId = "com.mpcst.agrivision"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // The upload key when key.properties exists. Without it a release
            // APK still builds with the debug key, so `flutter run --release`
            // works on a dev machine, but the Play bundle refuses to build
            // (below): Play rejects a debug-signed upload, and finding that out
            // after uploading is the slow way.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Refuse to produce a Play bundle signed with the debug key.
gradle.taskGraph.whenReady {
    val buildingBundle = allTasks.any { it.name == "bundleRelease" }
    if (buildingBundle && !hasReleaseKey) {
        throw GradleException(
            "No android/key.properties: a Play bundle must be signed with " +
                "your upload key, not the debug key. See docs/PLAY_STORE.md."
        )
    }
}

flutter {
    source = "../.."
}
