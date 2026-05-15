# Vosk Android
-keep class org.vosk.** { *; }
-keep class com.alphacephei.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Model and Recognizer classes
-keep class org.kaldi.** { *; }

# Prevent stripping of Gson/JSON classes
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }

# AMap SDK (高德地图) - prevent JNI / obfuscation issues
-keep class com.amap.api.** { *; }
-keep class com.autonavi.** { *; }
-keep class com.amap.api.maps.** { *; }
-keep class com.amap.api.location.** { *; }
-keep class com.amap.api.navi.** { *; }
-keep class com.amap.api.services.** { *; }
