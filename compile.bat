@echo off
setlocal enabledelayedexpansion

echo Building LuaGame...
echo.

call "C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" "C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x86
if errorlevel 1 (
    echo [ERROR] Failed to setup VS environment
    exit /b 1
)

echo.
echo Compiling...
echo.

cd /d E:\repos\cocos\LuaGame\frameworks\runtime-src\proj.win32
msbuild HelloLua.sln /p:Configuration=Release /p:Platform=Win32 /p:PlatformToolset=v141 /p:WindowsTargetPlatformVersion=8.1 /m

if errorlevel 1 (
    echo.
    echo [ERROR] Build failed!
    exit /b 1
) else (
    echo.
    echo [SUCCESS] Build completed!
    echo Output: E:\repos\cocos\LuaGame\frameworks\runtime-src\proj.win32\Release.win32\
)

endlocal
