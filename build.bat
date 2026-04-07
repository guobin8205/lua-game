@echo off
echo Building LuaGame with VS2017 toolset (v141)...
call "C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x86
if errorlevel 1 (
    echo Failed to setup VS environment
    exit /b 1
)
cd /d E:\repos\cocos\LuaGame\frameworks\runtime-src\proj.win32
msbuild HelloLua.sln /p:Configuration=Release /p:Platform=Win32 /p:PlatformToolset=v141 /p:WindowsTargetPlatformVersion=8.1 /m
if errorlevel 1 (
    echo Build failed!
    exit /b 1
) else (
    echo Build succeeded!
    echo Output: E:\repos\cocos\LuaGame\frameworks\runtime-src\proj.win32\Release.win32\
)
pause
