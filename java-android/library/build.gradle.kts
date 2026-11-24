plugins {
  id("com.android.library")
}

// optikpi_inapp Java Android — see ../README.md and ../CHANGELOG.md

android {
  namespace = "com.optikpi.inapp"
  compileSdk = 35

  defaultConfig {
    minSdk = 24
    consumerProguardFiles("consumer-rules.pro")
    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
  }

  compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  testOptions {
    unitTests.isIncludeAndroidResources = true
  }
}

dependencies {
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
  implementation("androidx.appcompat:appcompat:1.7.0")
  implementation("androidx.activity:activity:1.9.3")
  implementation("com.squareup.okhttp3:okhttp:4.12.0")

  testImplementation("junit:junit:4.13.2")
  testImplementation("org.robolectric:robolectric:4.14.1")
}