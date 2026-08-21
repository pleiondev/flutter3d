// The Android side of the gamepad package.
//
// Deliberately small. Everything that could be decided wrongly — which axis a
// trigger is on, whether a d-pad is a hat — is decided in Dart, where a test can
// reach it; this project forwards raw events and an inventory of what the device
// says it has. See `lib/src/android_mapping.dart`.
//
// Shaped after `flutter create -t plugin` on the pinned SDK rather than written
// from memory, and the difference is not cosmetic: **the Kotlin plugin is not
// applied here.** Flutter 3.47 supplies Kotlin to plugins itself and warns at
// build time about plugins that apply it again, saying that a future release
// will fail outright. Only the classpath is declared, exactly as the template
// does it.
group = "dev.flutter3d.gamepad"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.flutter3d.gamepad"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        // Flutter's own floor, not this plugin's: everything read here —
        // `InputManager`, `InputDevice`, generic motion events — has been in
        // Android since long before it.
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
