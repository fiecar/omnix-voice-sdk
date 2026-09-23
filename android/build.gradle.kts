import com.android.build.gradle.tasks.BundleAar

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

group = "com.omnix.voice"
version = "0.1.0"

// SDK-036: ship THIRD_PARTY_NOTICES.md inside the AAR (assets/), sourced from repo root.
val noticesAssetDir = layout.buildDirectory.dir("generated/omnixNoticesAssets")
val prepareThirdPartyNotices = tasks.register<Copy>("prepareThirdPartyNotices") {
    description = "Copy repo-root THIRD_PARTY_NOTICES.md into Android assets for AAR packaging"
    from(rootProject.file("../THIRD_PARTY_NOTICES.md"))
    into(noticesAssetDir)
    rename { "THIRD_PARTY_NOTICES.md" }
}

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

    sourceSets {
        getByName("main") {
            assets.srcDir(noticesAssetDir)
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(prepareThirdPartyNotices)
}

// SDK-036: release AAR must be named OmnixVoiceSDK-x.y.z.aar (not *-release.aar).
tasks.withType<BundleAar>().configureEach {
    if (name == "bundleReleaseAar") {
        archiveFileName.set("OmnixVoiceSDK-${project.version}.aar")
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // No third-party JVM deps for the shipped AAR (native CMake + Kotlin stdlib).
    testImplementation("junit:junit:4.13.2")
}
