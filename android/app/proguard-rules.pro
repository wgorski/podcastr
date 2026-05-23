# NewPipe Extractor / YouTube stream resolution rules.
#
# These libraries (Rhino, jsoup, nanojson) reference optional JDK / third-
# party classes that aren't present on Android. The references are dead
# code at runtime, but R8 won't ship the app until they're acknowledged.
# We also keep the extraction-stack classes themselves because NewPipe's
# parsers and Rhino's JS evaluator rely on reflection internally.

# --- transitive optional references R8 can't resolve ---
# jsoup ships an alternate regex backend (re2j) that's not bundled.
-dontwarn com.google.re2j.**
# Rhino uses java.beans for object introspection in JsonToJavaConverters.
-dontwarn java.beans.**
-dontwarn org.mozilla.javascript.**

# --- keep rules: reflection-heavy libraries ---
# Rhino evaluates YouTube's player JavaScript to derive stream signatures.
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.** { *; }

# jsoup parses YouTube's HTML.
-keep class org.jsoup.** { *; }
-dontwarn org.jsoup.**

# NewPipe Extractor itself — public API and its parser implementations
# (some are loaded reflectively or referenced through generic interfaces).
-keep class org.schabi.newpipe.extractor.** { *; }
-keep interface org.schabi.newpipe.extractor.** { *; }

# nanojson — NewPipe's JSON parser.
-keep class com.grack.nanojson.** { *; }
