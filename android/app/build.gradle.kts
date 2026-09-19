plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.tiernest.app"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.tiernest.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 7
        versionName = "0.2.0-alpha07"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }
    buildFeatures { compose = true; buildConfig = true }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            // Keep alpha upgrades compatible with the already installed test APK.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/engineAssets"))
    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("generated/vpnJniLibs"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/vpnNotices"))
    packaging { resources.excludes += setOf("META-INF/INDEX.LIST", "META-INF/DEPENDENCIES") }
    lint { abortOnError = true }
}

// The same pinned, checksum-verified upstream executables used by the module.
val prepareEngine by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile)
    commandLine("bash", "scripts/prepare-android-engine.sh")
    inputs.files(fileTree("src/main/assets"), "../../scripts/prepare-android-engine.sh",
        "../../scripts/fetch-upstream.sh", "../../scripts/build-home-probe.sh", "../../native/home-probe.c",
        "../../LICENSE", "../../THIRD_PARTY_NOTICES.md")
    outputs.dir(layout.buildDirectory.dir("generated/engineAssets"))
}
tasks.named("preBuild") { dependsOn(prepareEngine) }

val prepareVpn by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile)
    commandLine("bash", "scripts/build-vpn-native.sh")
    inputs.files(fileTree("../../native/vpn") { exclude("target/**") }, "../../scripts/build-vpn-native.sh", "../../scripts/prepare-vpn-notices.py")
    outputs.dir(layout.buildDirectory.dir("generated/vpnJniLibs"))
    outputs.dir(layout.buildDirectory.dir("generated/vpnNotices"))
}
tasks.named("preBuild") { dependsOn(prepareVpn) }

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.09.00")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.tomlj:tomlj:1.1.1")
    implementation("top.yukonga.miuix.kmp:miuix:0.6.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}
