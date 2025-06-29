plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "25.2.9519653"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17  // Change to 17
        targetCompatibility = JavaVersion.VERSION_17  // Change to 17
    }

    kotlinOptions {
        jvmTarget = "17"  // Change from JavaVersion.VERSION_17.toString() to "17"
    }

    defaultConfig {
        applicationId = "com.example.example"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        resources {
            pickFirsts += listOf("**/libllama.so", "**/libc++_shared.so")
        }
        jniLibs {
            pickFirsts += listOf("**/libllama.so", "**/libc++_shared.so")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
