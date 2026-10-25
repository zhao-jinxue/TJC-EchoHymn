import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ==== 签名配置（F-1）====
// key.properties 与 keystore/ 均已 gitignore；缺失时**回退 debug 签名**，
// 保证新机 / CI 仍可构建（不会因为没密钥而失败）。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
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
            // F-1：有正式密钥就用它，否则回退 debug（新机/CI 可构建）
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
