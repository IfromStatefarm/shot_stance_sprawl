plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.snapandgo.shadowwrestling"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
        // Use listOf to ensure correct typing in the Gradle Kotlin DSL
        freeCompilerArgs = listOf("-opt-in=androidx.media3.common.util.UnstableApi")
    }

    defaultConfig {
        applicationId = "com.snapandgo.shadowwrestling"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Jetpack Media3 for Native Hardware-Accelerated Video Editing
    implementation("androidx.media3:media3-transformer:1.10.1")
    implementation("androidx.media3:media3-effect:1.10.1")
    implementation("androidx.media3:media3-common:1.10.1")
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
    
    // Required by Media3 for ImmutableList and other collections used in MainActivity.kt
    implementation("com.google.guava:guava:32.1.3-android")

    // Required to resolve the @OptIn annotation in MainActivity.kt
    implementation("androidx.annotation:annotation-experimental:1.4.1")
}

flutter {
    source = "../.."
}
