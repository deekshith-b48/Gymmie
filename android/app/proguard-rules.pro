# R8 rules. Flutter and the plugins ship their own consumer rules; these cover app code reached by name.
-keep class app.gymmie.android.** { *; }
-dontwarn com.google.android.play.core.**
