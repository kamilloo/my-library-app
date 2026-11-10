import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Environment variables take precedence; never log their values.
val releaseSigning = mapOf(
    "storeFile" to "MY_LIBRARY_STORE_FILE",
    "storePassword" to "MY_LIBRARY_STORE_PASSWORD",
    "keyAlias" to "MY_LIBRARY_KEY_ALIAS",
    "keyPassword" to "MY_LIBRARY_KEY_PASSWORD",
).mapValues { (property, environment) ->
    providers.environmentVariable(environment).orNull
        ?: keystoreProperties.getProperty(property)
}

val validateReleaseCredentials = tasks.register("validateReleaseCredentials") {
    doLast {
        val missing = releaseSigning.filterValues { it.isNullOrBlank() }.keys
        check(missing.isEmpty()) {
            "Release signing credentials are missing: ${missing.joinToString()}. " +
                "Provide android/key.properties or MY_LIBRARY_* signing variables. " +
                "See docs/android_release.md. Debug signing is never used for release."
        }
        check(file(releaseSigning.getValue("storeFile")!!).isFile) {
            "Release keystore is unavailable. Check storeFile; see docs/android_release.md."
        }
    }
}

// Fail before release work even when AGP omits validateSigningRelease for an
// incomplete signing config. Debug builds never depend on release credentials.
tasks.configureEach {
    if (name == "preReleaseBuild") {
        dependsOn(validateReleaseCredentials)
    }
}

android {
    namespace = "com.kamilloo.mylibrary"
    compileSdk {
        version = release(37) { minorApiLevel = 0 }
    }
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.kamilloo.mylibrary"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = releaseSigning["keyAlias"]
            keyPassword = releaseSigning["keyPassword"]
            storeFile = releaseSigning["storeFile"]?.takeIf { it.isNotBlank() }?.let { file(it) }
            storePassword = releaseSigning["storePassword"]
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}