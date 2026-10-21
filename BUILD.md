# NGMusic - Build Instructions

## Prerequisites

All dependencies are installed locally in the project directory on F: drive to avoid filling C: drive.

### Directory Structure
```
F:\stuff\opencode\ngmusic\
├── .android-sdk\       # Android SDK (portable)
├── .cache\             # Build caches
│   ├── gradle\         # Gradle cache (~3GB)
│   └── pub-cache\      # Dart/Flutter packages cache (~500MB)
├── .flutter\           # Flutter SDK (portable, ~1GB)
└── flutter.bat         # Wrapper script
```

## Building the APK

### Option 1: Using flutter.bat wrapper
```cmd
cd F:\stuff\opencode\ngmusic
flutter.bat pub get
flutter.bat build apk --debug
```

The wrapper automatically sets:
- `GRADLE_USER_HOME` → `.cache\gradle`
- `PUB_CACHE` → `.cache\pub-cache`
- `ANDROID_HOME` → `.android-sdk`

### Option 2: Manual environment setup
```powershell
cd F:\stuff\opencode\ngmusic
. .\setup-env.ps1
flutter pub get
flutter build apk --debug
```

## Output

Debug APK will be located at:
```
F:\stuff\opencode\ngmusic\build\app\outputs\flutter-apk\app-debug.apk
```

## Troubleshooting

### Flutter not found
Extract Flutter SDK to `.flutter\flutter\` directory.

### Android SDK not found
Run:
```cmd
.android-sdk\cmdline-tools\latest\bin\sdkmanager.bat "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```

### Gradle issues
Clear Gradle cache:
```cmd
rmdir /s /q .cache\gradle\caches
```

### Out of disk space
All caches are on F: drive. To move them back to C::
1. Stop all builds
2. Copy `.cache\gradle` → `C:\Users\user\.gradle`
3. Copy `.cache\pub-cache` → `C:\Users\user\AppData\Local\Pub\Cache`
