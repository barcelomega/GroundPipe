$ErrorActionPreference = "Stop"

# Build native library for Android using NDK CMake
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CppDir = Join-Path $ScriptDir "app\src\main\cpp"
$JniLibsDir = Join-Path $ScriptDir "app\src\main\jniLibs"

# Find CMake
$CmakeBin = $null
if ($env:ANDROID_SDK_ROOT) {
    $CmakeBin = Join-Path $env:ANDROID_SDK_ROOT "cmake\3.22.1\bin\cmake.exe"
    if (-not (Test-Path $CmakeBin)) {
        $CmakeBin = Get-ChildItem -Path (Join-Path $env:ANDROID_SDK_ROOT "cmake") -Recurse -Filter "cmake.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not $CmakeBin -or -not (Test-Path $CmakeBin)) {
    $CmakeBin = (Get-Command cmake -ErrorAction SilentlyContinue).Source
}

if (-not $CmakeBin) {
    Write-Error "CMake not found. Install CMake or set ANDROID_SDK_ROOT."
    exit 1
}

Write-Host "Using CMake: $CmakeBin"

# Find NDK
$NdkRoot = $null
if ($env:ANDROID_NDK_ROOT) {
    $NdkRoot = $env:ANDROID_NDK_ROOT
} elseif ($env:ANDROID_SDK_ROOT) {
    $NdkRoot = Join-Path $env:ANDROID_SDK_ROOT "ndk\28.0.12674087"
    if (-not (Test-Path $NdkRoot)) {
        $NdkRoot = Get-ChildItem -Path (Join-Path $env:ANDROID_SDK_ROOT "ndk") -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not $NdkRoot -or -not (Test-Path $NdkRoot)) {
    Write-Error "Android NDK not found. Set ANDROID_NDK_ROOT or ANDROID_SDK_ROOT."
    exit 1
}

Write-Host "Using NDK: $NdkRoot"

$Toolchain = Join-Path $NdkRoot "build\cmake\android.toolchain.cmake"
if (-not (Test-Path $Toolchain)) {
    Write-Error "NDK toolchain not found at $Toolchain"
    exit 1
}

$MakeProgram = Join-Path $NdkRoot "prebuilt\windows-x86_64\bin\make.exe"
if (-not (Test-Path $MakeProgram)) {
    Write-Warning "NDK make not found, using system make"
    $MakeProgram = "make"
}

# Build for each ABI
$Abis = @("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
foreach ($Abi in $Abis) {
    Write-Host "Building for $Abi..."
    $BuildDir = Join-Path $CppDir "build-$Abi"
    if (Test-Path $BuildDir) {
        Remove-Item -Recurse -Force $BuildDir
    }
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    
    & $CmakeBin `
        -G "Unix Makefiles" `
        -DCMAKE_TOOLCHAIN_FILE="$Toolchain" `
        -DCMAKE_MAKE_PROGRAM="$MakeProgram" `
        -DANDROID_ABI="$Abi" `
        -DANDROID_PLATFORM=android-24 `
        -DANDROID_STL=c++_shared `
        -B "$BuildDir" `
        -S "$CppDir"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "CMake configure failed for $Abi"
        exit 1
    }
    
    & $CmakeBin --build "$BuildDir"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "CMake build failed for $Abi"
        exit 1
    }
    
    # Copy to jniLibs
    $AbiDir = Join-Path $JniLibsDir $Abi
    New-Item -ItemType Directory -Force -Path $AbiDir | Out-Null
    Copy-Item (Join-Path $BuildDir "libgroundpipe_native.so") $AbiDir
    Write-Host "Built $Abi" -ForegroundColor Green
}

Write-Host "Native library build complete for all architectures" -ForegroundColor Green
