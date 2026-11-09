import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties and the keystore stay out of git (android/.gitignore).
val keystoreFile = rootProject.file("key.properties")
val keystore = Properties().apply {
    if (keystoreFile.exists()) keystoreFile.inputStream().use { load(it) }
}

android {
    namespace = "com.olympusmont.ledgiproof"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.olympusmont.ledgiproof"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreFile.exists()) {
            create("release") {
                keyAlias = keystore.getProperty("keyAlias")
                keyPassword = keystore.getProperty("keyPassword")
                storeFile = file(keystore.getProperty("storeFile"))
                storePassword = keystore.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties the release is unsigned, never debug-signed.
            signingConfig = signingConfigs.findByName("release")
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
