import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// flutter build の --dart-define を gradle から読む。
// Flutter は「KEY=VALUE」全体をBase64化したものをカンマ区切りで渡す。
fun dartDefines(): Map<String, String> {
    val raw = project.findProperty("dart-defines") as? String ?: return emptyMap()
    if (raw.isEmpty()) return emptyMap()
    return raw.split(",").mapNotNull { entry ->
        try {
            val decoded = String(Base64.getDecoder().decode(entry), Charsets.UTF_8)
            val idx = decoded.indexOf('=')
            if (idx <= 0) {
                null
            } else {
                decoded.substring(0, idx) to decoded.substring(idx + 1)
            }
        } catch (_: Exception) {
            null
        }
    }.toMap()
}

android {
    namespace = "com.tsuritomo.tsuritomo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tsuritomo.tsuritomo"
        manifestPlaceholders["MAPS_API_KEY"] =
            dartDefines()["GOOGLE_MAPS_API_KEY"] ?: ""
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

    signingConfigs {
        create("release") {
            // プロトタイプ用にリポジトリ同梱のキーストアで署名する
            // （ベータ配布のため署名情報を公開している。ストア配布の前には
            //  専用のキーストアへsecretに格納して差し替えること）
            storeFile = file("tsuritomo-upload.keystore")
            storePassword = "tsuritomo2026"
            keyAlias = "tsuritomo"
            keyPassword = "tsuritomo2026"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
