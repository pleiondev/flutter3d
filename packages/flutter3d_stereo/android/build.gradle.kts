// The Android side of the stereo package: one sensor, forwarded raw.
//
// Deliberately small, for the reason `pad_input`'s Android project is small.
// Everything that can be got wrong here — which frame the sensor is talking
// about, what the display's rotation does to it, how a three-value rotation
// vector becomes a quaternion — is decided in `lib/src/head_pose.dart`, where a
// unit test can reach it. This project reports the numbers the sensor gave and
// which way the screen is turned, and nothing else.
//
// Shaped after `flutter create -t plugin` on the pinned SDK: **the Kotlin
// plugin is not applied here.** Flutter 3.47 supplies Kotlin to plugins itself
// and warns about plugins that apply it again.
group = "dev.flutter3d.stereo"
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
    namespace = "dev.flutter3d.stereo"

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
        // `SensorManager`, the rotation vector, `DisplayManager` — has been in
        // Android since long before it.
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
