import java.util.Properties
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val signingPropertiesFile =
    providers.environmentVariable("SHOT_STANCE_SPRAWL_SIGNING_PROPERTIES").orNull
        ?.takeIf { it.isNotBlank() }
        ?.let(::file)
        ?: File(System.getProperty("user.home"), ".gradle/shot_stance_sprawl_upload.properties")

val signingProperties = Properties()
if (signingPropertiesFile.isFile) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

fun signingValue(propertyName: String, environmentName: String): String? =
    providers.environmentVariable(environmentName).orNull
        ?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val uploadStoreFile = signingValue("storeFile", "SHOT_STANCE_SPRAWL_KEYSTORE_PATH")?.let(::file)
val uploadStorePassword = signingValue("storePassword", "SHOT_STANCE_SPRAWL_STORE_PASSWORD")
val uploadKeyAlias = signingValue("keyAlias", "SHOT_STANCE_SPRAWL_KEY_ALIAS")
val uploadKeyPassword = signingValue("keyPassword", "SHOT_STANCE_SPRAWL_KEY_PASSWORD")
val uploadSigningConfigured =
    uploadStoreFile?.isFile == true &&
        uploadStorePassword != null &&
        uploadKeyAlias != null &&
        uploadKeyPassword != null

val releaseSigningError =
    """
    Android release signing is not configured.
    Create ${signingPropertiesFile.absolutePath} from android/signing.properties.example,
    or provide the SHOT_STANCE_SPRAWL_* signing environment variables.
    See docs/android_release_signing.md.
    """.trimIndent()

if (
    !uploadSigningConfigured &&
        gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
) {
    throw GradleException(releaseSigningError)
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

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
        }
        create("prod") {
            dimension = "environment"
        }
    }

    signingConfigs {
        if (uploadSigningConfigured) {
            create("upload") {
                storeFile = requireNotNull(uploadStoreFile)
                storePassword = requireNotNull(uploadStorePassword)
                keyAlias = requireNotNull(uploadKeyAlias)
                keyPassword = requireNotNull(uploadKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            if (uploadSigningConfigured) {
                signingConfig = signingConfigs.getByName("upload")
            }
        }
    }
}

if (!uploadSigningConfigured) {
    tasks.configureEach {
        if (name.contains("release", ignoreCase = true)) {
            doFirst {
                throw GradleException(releaseSigningError)
            }
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

val firebaseProjectsByFlavor = mapOf(
    "dev" to "snap-and-go-dev",
    "prod" to "snap-and-go-prod",
)

firebaseProjectsByFlavor.forEach { (flavor, expectedProjectId) ->
    val flavorTitle = flavor.replaceFirstChar(Char::uppercaseChar)
    val serviceFile = file("src/$flavor/google-services.json")
    val verifyTask = tasks.register("verify${flavorTitle}FirebaseConfiguration") {
        group = "verification"
        description = "Checks that the $flavor Firebase service file targets $expectedProjectId."

        doLast {
            if (!serviceFile.isFile) {
                throw GradleException(
                    "Missing ${serviceFile.relativeTo(projectDir)}. " +
                        "The $flavor flavor must package Firebase project $expectedProjectId.",
                )
            }

            val serviceConfig = JsonSlurper().parse(serviceFile) as? Map<*, *>
            val projectInfo = serviceConfig?.get("project_info") as? Map<*, *>
            val actualProjectId = projectInfo?.get("project_id") as? String
            if (actualProjectId != expectedProjectId) {
                throw GradleException(
                    "Firebase configuration mismatch in ${serviceFile.relativeTo(projectDir)}: " +
                        "expected project $expectedProjectId, found ${actualProjectId ?: "no project_id"}.",
                )
            }
        }
    }

    tasks.matching {
        it.name.startsWith("process$flavorTitle") &&
            it.name.endsWith("GoogleServices")
    }.configureEach {
        dependsOn(verifyTask)
    }
}
