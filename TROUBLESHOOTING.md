# Troubleshooting

## Java/Gradle Compatibility Issue

**Problem:**
```
Unsupported class file major version 69
```

**Root Cause:**
- Java 25 (class file version 69) is too new for Gradle 8.x
- Gradle 9.x is too new for Flutter's Groovy scripts
- Need: Java 21 LTS + Gradle 8.10.2

**Solution:**
1. Portable Java 21 LTS installed in `.java/jdk-21.0.5+11/`
2. `flutter.bat` sets `JAVA_HOME` to portable Java
3. Gradle updated to 8.10.2 in `android/gradle/wrapper/gradle-wrapper.properties`

**Compatibility Matrix:**
- Java 21 LTS ✅ Gradle 8.10.2 ✅ Flutter 3.24.5
- Java 25 ❌ Gradle 8.x (unsupported)
- Java 25 ❌ Gradle 9.x ❌ Flutter (Groovy incompatibility)

## Build Commands

Always use `flutter.bat` wrapper instead of direct flutter commands:

```batch
# Install dependencies
.\flutter.bat pub get

# Build debug APK
.\flutter.bat build apk --debug

# Build release APK
.\flutter.bat build apk --release

# Run on device
.\flutter.bat run
```

## Cache Locations

All caches are on F: drive to save C: space:
- Gradle: `.cache/gradle/`
- Pub: `.cache/pub-cache/`
- Android SDK: `.android-sdk/`
- Java: `.java/jdk-21.0.5+11/`

## Clean Build

If build fails, try clean:
```batch
.\flutter.bat clean
cd android
.\gradlew.bat clean
cd ..
.\flutter.bat build apk --debug
```

## Flutter Doctor

Check Flutter setup:
```batch
.\flutter.bat doctor -v
```
