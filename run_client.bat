@echo off
chcp 1251 >nul
setlocal enabledelayedexpansion

set PROJECT_DIR=C:\Users\hermes\gamedev\fantasy-settlement-mmo
set REPO_URL=https://github.com/xace1825/godot-mmo-rpi.git
set SERVER_IP=192.168.0.102
set SERVER_PORT=7777

echo [DEBUG] Starting...
echo [DEBUG] Folder: %~dp0

set GODOT_PATH=
for %%f in ("%~dp0Godot*.exe") do (
    if not defined GODOT_PATH (
        set "GODOT_PATH=%%~ff"
    )
)

echo [DEBUG] Godot: !GODOT_PATH!

if not defined GODOT_PATH (
    echo [ERROR] Godot not found. Put bat near Godot_v4.4.1-stable_win64.exe
    pause
    exit /b 1
)

where git >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Git not found. Download from https://git-scm.com/download/win
    pause
    exit /b 1
)
echo [DEBUG] Git OK

rem === Disable Git Credential Manager ===
git config --global credential.helper ""

rem === If folder exists but is not a git repo, remove it ===
if exist "%PROJECT_DIR%" (
    if not exist "%PROJECT_DIR%\.git" (
        echo [INFO] Old project folder found without git. Removing...
        rmdir /s /q "%PROJECT_DIR%"
        if exist "%PROJECT_DIR%" (
            echo [ERROR] Cannot remove old project folder. Try running as administrator.
            pause
            exit /b 1
        )
    )
)

rem === Clone or pull ===
if not exist "%PROJECT_DIR%" (
    echo [INFO] Cloning project...
    git clone "%REPO_URL%" "%PROJECT_DIR%"
    if %errorlevel% neq 0 (
        echo [ERROR] Clone failed
        pause
        exit /b 1
    )
) else (
    echo [INFO] Updating project...
    pushd "%PROJECT_DIR%"
    git pull
    if %errorlevel% neq 0 (
        echo [ERROR] Pull failed
        pause
        exit /b 1
    )
    popd
)

rem === Import Godot resources ===
echo [INFO] Importing Godot resources...
"!GODOT_PATH!" --path "%PROJECT_DIR%" --headless --import
if %errorlevel% neq 0 (
    echo [ERROR] Godot import failed
    pause
    exit /b 1
)

rem === Launch ===
echo [INFO] Launching game...
"!GODOT_PATH!" --path "%PROJECT_DIR%" --server-ip %SERVER_IP% --server-port %SERVER_PORT%

if %errorlevel% neq 0 (
    echo [ERROR] Godot exited with code %errorlevel%
)

pause
