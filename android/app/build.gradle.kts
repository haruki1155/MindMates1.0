import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties()
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}
val developmentApplicationId = "com.example.mind_mates"
val stagingApplicationId = "com.example.mind_mates.staging"
val productionApplicationId = "ph.edu.ucu.mindmates"
val firebaseAppIds = mapOf(
    "Development" to "1:1004916101316:android:e4c840c1c3070222c73991",
    "Staging" to "1:978195258114:android:36354078e3d99999f5801b",
    "Production" to "1:842251480963:android:4c05d169dbacf125eb50b6",
)
val applicationIds = mapOf(
    "Development" to developmentApplicationId,
    "Staging" to stagingApplicationId,
    "Production" to productionApplicationId,
)

// Every variant must use the Firebase registration for its exact package.
tasks.configureEach {
    val flavor = listOf("Development", "Staging", "Production")
        .firstOrNull { name.startsWith("process$it") && name.endsWith("GoogleServices") }
    if (flavor != null) {
        doFirst {
            val configuration = file("src/${flavor.lowercase()}/google-services.json")
            val applicationId = applicationIds.getValue(flavor)
            val firebaseAppId = firebaseAppIds.getValue(flavor)
            if (!configuration.isFile ||
                !configuration.readText().contains("\"package_name\": \"$applicationId\"") ||
                !configuration.readText().contains("\"mobilesdk_app_id\": \"$firebaseAppId\"")) {
                throw GradleException(
                    "android/app/src/${flavor.lowercase()}/google-services.json must match $applicationId and $firebaseAppId.",
                )
            }
        }
    }
}
val requiredSigningKeys = listOf("keyAlias", "storeFile", "storePassword", "keyPassword")
val missingSigningKeys = requiredSigningKeys.filter { signingProperties.getProperty(it).isNullOrBlank() }
val configuredStoreFile = signingProperties.getProperty("storeFile")
val releaseConfigurationError = when {
    missingSigningKeys.isNotEmpty() ->
        "Release builds require android/key.properties with keyAlias, storeFile, storePassword, and keyPassword."
    configuredStoreFile == null || !rootProject.file(configuredStoreFile).isFile ->
        "Release signing keystore not found at android/${configuredStoreFile ?: "<missing storeFile>"}."
    else -> null
}

tasks.configureEach {
    if (name.contains("Staging") && name.endsWith("Release")) {
        doFirst {
            throw GradleException("Staging is debug-only. Build assembleStagingDebug instead.")
        }
    }
    if (name == "preProductionReleaseBuild" || name == "assembleProductionRelease" || name == "bundleProductionRelease") {
        doFirst {
            if (releaseConfigurationError != null) {
                throw GradleException(releaseConfigurationError)
            }
        }
    }
}

android {
    namespace = productionApplicationId
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = productionApplicationId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            applicationId = developmentApplicationId
        }
        create("staging") {
            dimension = "environment"
            applicationId = stagingApplicationId
        }
        create("production") {
            dimension = "environment"
            applicationId = productionApplicationId
        }
    }

    buildTypes {
        release {
            if (releaseConfigurationError == null) {
                signingConfig = signingConfigs.create("release") {
                    keyAlias = signingProperties.getProperty("keyAlias")
                    storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                    storePassword = signingProperties.getProperty("storePassword")
                    keyPassword = signingProperties.getProperty("keyPassword")
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

flutter {
    source = "../.."
}
