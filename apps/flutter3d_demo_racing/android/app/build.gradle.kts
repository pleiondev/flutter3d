import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// **A release key when the machine has one, and a build that works when it does
// not.** Signing keys cannot live in the repository, so the only place they can
// come from is somewhere outside it — a developer's `android/key.properties`,
// or a CI step that writes the same file out of a secret. What that leaves is
// the question of what happens on every machine that has neither: a fork, a
// clone somebody is reading, a contributor's first checkout. If the answer is a
// build failure, then the repository does not build, and "you need our private
// key to compile a demo" is not a thing anyone should have to discover.
//
// So the file is optional and its absence is not an error. Below, a release
// build with no key falls back to the debug one, which is what `flutter create`
// wired unconditionally and is fine for everything except distribution — an APK
// signed with the debug key installs and runs and cannot be uploaded anywhere,
// which is exactly the right set of permissions for a build nobody asked to
// publish.
//
// `key.properties`, `*.keystore` and `*.jks` are in android/.gitignore, and the
// day one of them is not is the day the key stops being a key.
val signing = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use(::load)
}

android {
    namespace = "dev.flutter3d.racing"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // One form across the four demos and the editor, on all four platforms:
        // dev.flutter3d.<genre>. They are separate applications that install
        // beside each other on the same phone, so the only thing that keeps
        // them apart is this string being different in each and the same
        // everywhere within one.
        applicationId = "dev.flutter3d.racing"
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
        // Declared only when there is something to declare. An empty config
        // registered anyway is worse than none: Gradle accepts it, the build
        // succeeds, and the APK comes out unsigned — which fails at `adb
        // install` on a phone, a long way from here.
        if (signing.getProperty("storeFile") != null) {
            create("release") {
                storeFile = rootProject.file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
