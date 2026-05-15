plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.agent.my_agent_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.agent.my_agent_app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val jniDir = layout.projectDirectory.dir("src/main/jni").asFile.path
        val opencvDir = project.findProperty("opencvMobileDir") as? String
            ?: "$jniDir/opencv-mobile-2.4.13.7-android"
        val ncnnDir = project.findProperty("ncnnSdkDir") as? String
            ?: "$jniDir/ncnn-20260113-android-vulkan"

        externalNativeBuild {
            cmake {
                arguments("-DOPENCV_MOBILE_DIR=$opencvDir", "-DNCNN_SDK_DIR=$ncnnDir")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/jni/CMakeLists.txt")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

configurations.all {
    exclude(group = "org.apache.logging.log4j", module = "log4j-api")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.amap.api:navi-3dmap-cm:9.8.4_3dmap9.8.3")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("com.alphacephei:vosk-android:0.3.47")
    // OCR: using standalone PaddleOCR+ncnn (no ML Kit needed)
    implementation("org.apache.poi:poi:5.2.5") { exclude(group = "org.apache.logging.log4j", module = "log4j-api") }
    implementation("org.apache.poi:poi-scratchpad:5.2.5")
    // POI transitive deps (explicit for reliability in poor network environments)
    implementation("org.apache.commons:commons-collections4:4.4")
    implementation("org.apache.commons:commons-compress:1.26.2")
    implementation("commons-codec:commons-codec:1.17.1")
    implementation("commons-io:commons-io:2.17.0")
}

flutter {
    source = "../.."
}

// Remove x86_64 from build — real Android devices don't use it
afterEvaluate {
    android {
        defaultConfig {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
            }
        }
    }
}
