# Keep Gson TypeToken generic signatures (required by flutter_local_notifications).
# R8 strips generic type info from TypeToken subclasses, causing
# "Missing type parameter" crashes during notification deserialization.
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Keep flutter_local_notifications model classes used by Gson serialization
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
