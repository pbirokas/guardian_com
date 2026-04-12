import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// ── Version aus Git ───────────────────────────────────────────────────────────
// versionCode  = Anzahl aller Git-Commits (steigt automatisch mit jedem Commit)
// versionName  = wird aus pubspec.yaml via Flutter übernommen
fun gitCommitCount(): Int {
    return try {
        val process = ProcessBuilder("git", "rev-list", "--count", "HEAD")
            .directory(rootProject.projectDir)
            .start()
        process.inputStream.bufferedReader().readText().trim().toInt()
    } catch (e: Exception) {
        1 // Fallback falls git nicht verfügbar (z.B. CI ohne git-History)
    }
}

// ── Keystore ──────────────────────────────────────────────────────────────────
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.guardianapp.guardian_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.guardianapp.guardian_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = gitCommitCount()
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

// ── Build-Output umbenennen ───────────────────────────────────────────────────
// app-release.aab → app-release-{versionCode}.aab
// app-release.apk → app-release-{versionCode}.apk
android.applicationVariants.configureEach {
    val variant = this
    val versionCode = variant.versionCode

    variant.outputs.configureEach {
        val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
        val original = output.outputFileName
        if (original.endsWith(".apk")) {
            output.outputFileName = original.replace(".apk", "-$versionCode.apk")
        }
    }
}

tasks.whenTaskAdded {
    if (name == "bundleRelease" || name == "bundleDebug") {
        doLast {
            val bundleType = name.removePrefix("bundle").lowercase()
            val bundleDir = layout.buildDirectory.dir("outputs/bundle/$bundleType").get().asFile
            val canonical = File(bundleDir, "app-$bundleType.aab")
            if (canonical.exists()) {
                val versionCode = android.defaultConfig.versionCode ?: 1
                canonical.renameTo(File(bundleDir, "app-$bundleType-$versionCode.aab"))
            }
        }
    }
}
