import java.util.Properties

plugins {
    id("com.android.application")
    // No explicit kotlin-android: on AGP 9 with android.builtInKotlin=false the Flutter Gradle
    // Plugin applies KGP itself (declared `apply false` in settings.gradle.kts), as Flutter's
    // own app template does. Applying it here triggers Flutter's "migrate to Built-in Kotlin"
    // warning.
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---- Release signing (audit D2) ------------------------------------------------------------
// android/key.properties is untracked (it holds the keystore passwords) and must define
//   storeFile=<upload keystore .jks: absolute path, or relative to android/app/>
//   storePassword=...  keyAlias=...  keyPassword=...
// Release builds are only ever signed with that one existing upload key. There is deliberately
// NO fallback to debug signing: Android rejects an update whose signature differs from the
// installed app's, so a debug-signed "release" APK could never update a real install.
// When the keystore isn't usable, verifyReleaseSigning stops release builds up front with an
// actionable message instead of AGP's opaque signing error at packaging time. Debug and profile
// builds don't use this config and are unaffected.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val releaseStoreFilePath: String? = keystoreProperties.getProperty("storeFile")?.trim()?.ifEmpty { null }
val releaseStoreFile: File? = releaseStoreFilePath?.let { file(it) }

// Why release signing can't work on this machine, or null when it can. Never mentions passwords.
val releaseSigningProblem: String? = run {
    val missingKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    val hostOs = System.getProperty("os.name")
    // "C:\...", "C:/..." or "C:..." (.properties parsing eats single backslashes), or any backslash.
    val isWindowsStylePath = releaseStoreFilePath
        ?.let { it.contains('\\') || Regex("^[A-Za-z]:").containsMatchIn(it) } == true
    when {
        !keystorePropertiesFile.isFile ->
            "${keystorePropertiesFile.path} does not exist."
        missingKeys.isNotEmpty() ->
            "android/key.properties does not set ${missingKeys.joinToString()}."
        releaseStoreFile?.isFile == true -> null
        isWindowsStylePath && !hostOs.startsWith("Windows", ignoreCase = true) ->
            "storeFile in android/key.properties is a Windows path (read as " +
                "\"$releaseStoreFilePath\"), but this build runs on $hostOs."
        else ->
            "keystore not found: storeFile=$releaseStoreFilePath resolves to ${releaseStoreFile?.path}."
    }
}

val releaseSigningError: String? = releaseSigningProblem?.let { problem ->
    """
    |Release signing is not set up on this machine: $problem
    |
    |Release builds must be signed with the existing ProtoLog upload keystore
    |(protolog-release-key.jks, which is not in git). There is no debug-key fallback on purpose:
    |Android only installs an update signed with the same key as the installed app, so never
    |generate a new keystore either.
    |
    |To fix:
    |  1. Copy the .jks onto this machine, outside the repo, and keep it and key.properties
    |     private (e.g. chmod 600).
    |  2. In android/key.properties set storeFile to the keystore's path on this machine
    |     (absolute, or relative to android/app/; use forward slashes, since .properties
    |     files treat a backslash as an escape), plus storePassword, keyAlias and keyPassword.
    |See docs/HANDOFF.md, "Release builds".
    """.trimMargin()
}

val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    group = "verification"
    description = "Fails release builds early when the upload keystore is not usable (audit D2)."
    // Capture a plain String so the action doesn't reference the build script object.
    val error = releaseSigningError
    doLast {
        if (error != null) throw GradleException(error)
    }
}

// Run the check before the first tasks of every release build (flutter build apk / appbundle,
// flutter run --release): AGP's preReleaseBuild, the Flutter plugin's Dart AOT compile (which
// doesn't depend on preReleaseBuild and would otherwise burn ~20 s first), and AGP's own
// validateSigningRelease, which must not get to fail first with its opaque message.
val releaseEntryTasks = setOf("preReleaseBuild", "compileFlutterBuildRelease", "validateSigningRelease")
tasks.named { it in releaseEntryTasks }.configureEach {
    dependsOn(verifyReleaseSigning)
}

android {
    namespace = "com.zak.protolog_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zak.protolog_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = releaseStoreFile
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // Always the upload key, never debug: see "Release signing" above.
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
