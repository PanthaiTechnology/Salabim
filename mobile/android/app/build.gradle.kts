import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Credenciais da keystore de release — lidas de key.properties (fora do
// git, ver .gitignore e STORE_PUBLISHING.md secao 6). Sem esse arquivo
// (ex: build de outra máquina/CI sem o segredo), cai pra assinatura debug
// automaticamente, pra não quebrar `flutter build` local de quem não tem
// a keystore.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.salabim.salabim"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.salabim.salabim"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Assina com a chave de release de verdade quando key.properties
            // existe (ver STORE_PUBLISHING.md secao 6); cai pra debug só
            // como rede de segurança pra não quebrar build de quem não tem
            // o segredo (nunca deve acontecer numa build publicada de fato).
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
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

// SDK do ACRCloud (branch de teste — ponte nativa, ver ARCHITECTURE.md
// §4.3/4.4). Não é uma dependência Maven/JitPack — vem como .jar (baixado
// de github.com/acrcloud/ACRCloudUniversalSDK/libs) em app/libs/, mais as
// bibliotecas nativas (.so) por ABI em app/src/main/jniLibs/<abi>/
// (convenção padrão do Gradle, pega automático, sem config extra aqui).
dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
}
