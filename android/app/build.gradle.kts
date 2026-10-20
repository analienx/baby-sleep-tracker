plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.analienx.baby_sleep_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.analienx.baby_sleep_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Separate, repeatably signed Spark staging app. The preview package and
    // its locally entered records are never replaced by these QA builds.
    val littleRestStagingBuild = System.getenv("LITTLE_REST_STAGING_BUILD") == "1"
    signingConfigs {
        if (littleRestStagingBuild) {
            create("littleRestStaging") {
                storeFile = file(System.getenv("LITTLE_REST_STAGING_KEYSTORE_PATH")
                    ?: error("Missing staging keystore path"))
                storePassword = System.getenv("LITTLE_REST_STAGING_KEYSTORE_PASSWORD")
                    ?: error("Missing staging keystore password")
                keyAlias = "little-rest-staging"
                keyPassword = storePassword
                storeType = "pkcs12"
            }
        }
    }

    buildTypes {
        getByName("debug") {
            if (littleRestStagingBuild) {
                applicationIdSuffix = ".staging"
                signingConfig = signingConfigs.getByName("littleRestStaging")
            }
        }
        release {
            // Deliberately unsigned until the F4 release/signing review gate.
            // Never publish an APK signed with the staging/debug identity.
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
