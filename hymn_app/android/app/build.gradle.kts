plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.echohymn.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.echohymn.app"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 四个发布变体（与 --dart-define=AUDIO_VARIANT=<id> 一一对应）
    // full / piano / vocal / lite —— applicationId 互异，可同时安装
    flavorDimensions += "audio"
    productFlavors {
        create("full") {
            dimension = "audio"
        }
        create("piano") {
            dimension = "audio"
            applicationIdSuffix = ".piano"
        }
        create("vocal") {
            dimension = "audio"
            applicationIdSuffix = ".vocal"
        }
        create("lite") {
            dimension = "audio"
            applicationIdSuffix = ".lite"
        }
    }

    buildTypes {
        release {
            // TODO: 阶段 F 换成正式 keystore（当前沿用 debug 签名，便于 flutter run --release）
            signingConfig = signingConfigs.getByName("debug")
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
