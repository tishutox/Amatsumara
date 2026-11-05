# The JNI bridge (flutter_llama_bridge.cpp) looks up these classes and constructors by name; R8 in the app must keep
# them (a release build otherwise crashes with NoSuchMethodError in nativeGetModelInfo / nativeGenerate).
-keep class net.nativemind.flutter_llama.FlutterLlamaPlugin { native <methods>; }
-keep class net.nativemind.flutter_llama.FlutterLlamaPlugin$GenerationResult { *; }
-keep class net.nativemind.flutter_llama.FlutterLlamaPlugin$ModelInfo { *; }
-keepclasseswithmembernames,includedescriptorclasses class net.nativemind.flutter_llama.** { native <methods>; }
