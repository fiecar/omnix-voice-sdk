plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

group = "com.omnix.voice"
version = "0.1.0"

android {
    namespace = "com.omnix.voice"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndk.get()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        consumerProguardFiles("consumer-rules.pro")

        externalNativeBuild {
            cmake {
                // OpenSSL resolved in cpp/CMakeLists.txt from
                // build/openssl-android/<ANDROID_ABI> (SDK-066 artifact).
                // Only build the shared Omnix library (skip baresip_exe / tests).
                targets("omnixvoice")
                arguments(
                    "-DANDROID_STL=c++_static",
                    "-DSTATIC=ON",
                )
                cFlags("-fvisibility=hidden")
                cppFlags("-fvisibility=hidden")
            }
        }

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    // Library modules must not set application targetSdk (host app owns it).
    lint {
        targetSdk = libs.versions.lintTargetSdk.get().toInt()
    }
    testOptions {
        targetSdk = libs.versions.lintTargetSdk.get().toInt()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
            version = "3.22.1+"
        }
    }

    packaging {
        jniLibs {
            keepDebugSymbols += setOf("**/libomnixvoice.so")
        }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // No third-party JVM deps for the shipped AAR (native CMake + Kotlin stdlib).
    testImplementation("junit:junit:4.13.2")
}
