// ML Kit translation harness for #159: a tool app for the Android emulator, never part of Seal Speak.
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "MLKitEval"
include(":app")
