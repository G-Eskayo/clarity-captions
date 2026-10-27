plugins { id("com.android.application") }

android {
    namespace = "com.gileskayo.eval.mlkit"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.gileskayo.eval.mlkit"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1"
    }
    // Debuggable only so `adb shell run-as` can write the test sets into the app's private files dir; translation
    // itself runs in ML Kit's native code.
    buildTypes { release { isMinifyEnabled = false; isDebuggable = true; signingConfig = signingConfigs.getByName("debug") } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}

dependencies {
    // Keep in step with the version recorded in docs/perf/translation-comparison.md
    implementation("com.google.mlkit:translate:17.0.3")
}
