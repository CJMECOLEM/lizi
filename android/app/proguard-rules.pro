# google_mlkit_text_recognition references every script's recognizer, but only the
# Chinese model is bundled (see build.gradle.kts), so R8 must ignore the others.
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
