@echo off
setlocal EnableDelayedExpansion

REM ---- JERCPTL: PTL rule module (JERCPLD.PTL.dll) ----
REM Only MSVC is required: the module embeds PTL/*.json and exports a plain C ABI,
REM so it does not link LeviLamina or any BDS symbol.

set "VCVARS="
if exist "D:\VS\BuildTools\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=D:\VS\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not defined VCVARS (
  for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
  if defined VSPATH if exist "!VSPATH!\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=!VSPATH!\VC\Auxiliary\Build\vcvars64.bat"
)
if not defined VCVARS (
  echo [JERCPTL] vcvars64.bat not found
  exit /b 1
)
call "%VCVARS%" >nul
if errorlevel 1 exit /b 1

if not exist "%~dp0build" mkdir "%~dp0build"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gen-ptl-header.ps1"
if errorlevel 1 exit /b 1

cl /nologo /std:c++20 /EHa /MD /LD /utf-8 /O2 /DNDEBUG /DNOMINMAX ^
  /I"%~dp0src" /I"%~dp0build\generated" ^
  "%~dp0src\JERCPLD.PTL.cpp" ^
  /Fe:"%~dp0build\JERCPLD.PTL.dll"
if errorlevel 1 exit /b 1
echo BUILD OK: %~dp0build\JERCPLD.PTL.dll
