# Preserve the generated TOML parser's metadata used by the ANTLR runtime.
-keep class org.tomlj.internal.** { *; }
-keep class com.tiernest.app.engine.NativeVpn { *; }
# Retain useful crash locations; versioned mapping files are saved by the build.
-keepattributes SourceFile,LineNumberTable
