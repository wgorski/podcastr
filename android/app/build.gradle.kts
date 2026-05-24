plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wgorski.podcastr"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications: ships APIs that need
        // desugaring on minSdk < 26.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wgorski.podcastr"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 is run by the Flutter Gradle plugin even when minify is off
            // here, and it trips on optional transitive references inside
            // NewPipe Extractor's dependencies (Rhino / jsoup / re2j).
            // The rules in proguard-rules.pro silence those warnings and
            // keep the reflection-heavy classes the extractor needs.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Name the produced APK podcastr-<versionName>.apk so the artifact in
    // build/app/outputs/flutter-apk/ always reflects the pubspec version.
    // The Flutter Gradle plugin chains a doLast on assemble<Variant> that
    // copies the APK into flutter-apk/ with a hard-coded `app-<buildType>.apk`
    // name; we override outputFileName for the gradle output and append a
    // second doLast that renames the Flutter copy to match.
    applicationVariants.all {
        val variant = this
        val variantVersion = versionName
        val buildTypeName = variant.buildType.name
        outputs.all {
            (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl)
                .outputFileName = "podcastr-$variantVersion.apk"
        }
        // Flutter's CLI does a post-build existence check on `app-<buildType>.apk`
        // (see flutter_tools/lib/src/android/gradle.dart#_apkFilesFor), so we
        // leave that file in place and emit `podcastr-<versionName>.apk` next
        // to it for distribution.
        val capitalized = variant.name.replaceFirstChar { it.uppercase() }
        tasks.matching { it.name == "assemble$capitalized" }.configureEach {
            doLast {
                val flutterApkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
                val src = flutterApkDir.resolve("app-$buildTypeName.apk")
                val dst = flutterApkDir.resolve("podcastr-$variantVersion.apk")
                if (src.exists()) {
                    src.copyTo(dst, overwrite = true)
                }
            }
        }
    }
}

dependencies {
    // NewPipe Extractor — the YouTube extraction core used by NewPipe (F-Droid).
    // Closest practical equivalent to yt-dlp on Android.
    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.26.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // WorkManager: backs the foreground-service download worker so audio
    // downloads survive app kill and OS-driven process death.
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    // repeatOnLifecycle: keeps the WorkInfo Flow collector tied to the
    // activity's lifecycle so we don't leak observers across configuration
    // changes.
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
