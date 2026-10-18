// The Android side of the pointer lock.
//
// Shaped after `flutter create -t plugin` on the pinned SDK, as pad_input's is:
// the Kotlin plugin is not applied here, because Flutter 3.47 supplies Kotlin to
// plugins itself and warns about plugins that apply it again. Only the classpath
// is declared, exactly as the template does it.
group = "dev.flutter3d.flutter3d_pointer_lock"
version = "0.5.0"

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
    namespace = "dev.flutter3d.flutter3d_pointer_lock"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // Flutter's own floor. Pointer capture arrived in API 26, and below it
        // the plugin answers "unsupported" instead of raising the floor of every
        // application that depends on it.
        minSdk = 24
    }

    testOptions {
        unitTests {
            all {
                it.useJUnitPlatform()
                it.outputs.upToDateWhen { false }
                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
