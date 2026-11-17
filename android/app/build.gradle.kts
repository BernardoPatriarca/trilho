import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Assinatura de release: lida de android/key.properties (fora do git).
// Sem esse arquivo, o build usa a chave de TESTE versionada
// (app/trilho-teste.keystore), que não é segredo. Ver LEIAME-RELEASE.md.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.bernardopatriarca.trilho"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications usa APIs java.time: exige desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bernardopatriarca.trilho"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Vem do pubspec.yaml (version: 1.0.0+1).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keyProperties.isNotEmpty()) {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            } else {
                logger.warn("android/key.properties não encontrado: assinando com a chave de TESTE.")
                storeFile = file("trilho-teste.keystore")
                storePassword = "trilho-teste"
                keyAlias = "trilho-teste"
                keyPassword = "trilho-teste"
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
