@echo off
echo ================================================================
echo       SMART LAUNDRY POS - ALL-IN-ONE INSTALLER BUILDER
echo ================================================================
echo.

echo [1/3] Compiling Python Backend (main.py -> main.exe)...
python -m pip install nuitka zstandard >nul 2>&1
python -m nuitka --standalone --onefile --show-progress main.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Gagal mengompilasi Python backend!
    pause
    exit /b %ERRORLEVEL%
)
echo.

echo [2/3] Building Flutter Desktop Windows (Release Mode)...
cd "LaundryApps(Upgrade)"
call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Gagal me-build Flutter Windows!
    cd ..
    pause
    exit /b %ERRORLEVEL%
)
cd ..
echo.

echo [3/3] Compiling Installer using Inno Setup...
set "INNO_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if not exist "%INNO_PATH%" (
    set "INNO_PATH=C:\Program Files\Inno Setup 6\ISCC.exe"
)

if exist "%INNO_PATH%" (
    "%INNO_PATH%" installer_setup.iss
    echo.
    echo ================================================================
    echo   SUKSES! File Installer siap di folder: installer_output\
    echo ================================================================
) else (
    echo [INFO] Inno Setup Compiler (ISCC.exe) belum terpasang di lokasi default.
    echo Silakan install Inno Setup dari https://jrsoftware.org/isdl.php
    echo Lalu buka file 'installer_setup.iss' dengan Inno Setup dan klik Compile!
)

pause
