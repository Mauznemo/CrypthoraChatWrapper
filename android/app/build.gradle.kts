import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. `android/key.properties` is gitignored and only exists on machines that are
// allowed to cut releases (locally, and on CI where the workflow writes it from secrets).
// Without it the release build falls back to the debug key, so contributors can still run
// `flutter run --release` on a fresh clone.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
        Properties().apply {
            if (keystorePropertiesFile.exists()) {
                keystorePropertiesFile.inputStream().use { load(it) }
            }
        }

android {
    namespace = "dev.mauznemo.crypthora_chat_wrapper"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    defaultConfig {
        applicationId = "dev.mauznemo.crypthora_chat_wrapper"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // Both come from `version:` in pubspec.yaml. The release workflow overrides the version
        // code with `--build-number`, since the `+n` in pubspec is not kept up to date.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                    if (keystorePropertiesFile.exists()) signingConfigs.getByName("release")
                    else signingConfigs.getByName("debug")
        }
    }

    dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
}

flutter { source = "../.." }
