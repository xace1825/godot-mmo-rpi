@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set PROJECT_DIR=%USERPROFILE%\gamedev\fantasy-settlement-mmo
set REPO_URL=https://github.com/xace1825/godot-mmo-rpi.git
set SERVER_IP=192.168.0.102
set SERVER_PORT=7777

rem === Автопоиск Godot ===
set GODOT_PATH=

rem Сначала ищем в папке, где лежит этот bat-файл
set SCRIPT_DIR=%~dp0
for %%f in ("%SCRIPT_DIR%\Godot*.exe") do (
    if "!GODOT_PATH!"=="" (
        set GODOT_PATH=%%~ff
    )
)

rem Если не нашли рядом, ищем в Program Files
if "!GODOT_PATH!"=="" (
    for /r "C:\Program Files" %%f in (Godot*.exe) do (
        if "!GODOT_PATH!"=="" (
            set GODOT_PATH=%%~ff
        )
    )
)

rem Ищем в Program Files (x86)
if "!GODOT_PATH!"=="" (
    for /r "C:\Program Files (x86)" %%f in (Godot*.exe) do (
        if "!GODOT_PATH!"=="" (
            set GODOT_PATH=%%~ff
        )
    )
)

rem Пробуем PATH
if "!GODOT_PATH!"=="" (
    where godot >nul 2>nul
    if !errorlevel! == 0 (
        set GODOT_PATH=godot
    )
)

if "!GODOT_PATH!"=="" (
    echo Godot не найден.
    echo Положи этот bat-файл в папку с Godot_v4.4.1-stable_win64.exe
    echo или укажи путь вручную в файле run_client.bat
    pause
    exit /b 1
)

echo Найден Godot: !GODOT_PATH!

rem === Проверка Git ===
where git >nul 2>nul
if %errorlevel% neq 0 (
    echo Git не найден. Скачай и установи Git: https://git-scm.com/download/win
    pause
    exit /b 1
)

rem === Скачивание/обновление проекта ===
if not exist "%PROJECT_DIR%" (
    echo Проект не найден. Клонирую с GitHub...
    git clone "%REPO_URL%" "%PROJECT_DIR%"
    if %errorlevel% neq 0 (
        echo Ошибка клонирования.
        pause
        exit /b 1
    )
) else (
    echo Проект найден. Обновляю с GitHub...
    pushd "%PROJECT_DIR%"
    git pull
    if %errorlevel% neq 0 (
        echo Ошибка обновления. Возможно, есть локальные изменения.
        pause
        exit /b 1
    )
    popd
)

rem === Запуск клиента ===
echo Запуск игры. Подключение к серверу %SERVER_IP%:%SERVER_PORT%
"!GODOT_PATH!" --path "%PROJECT_DIR%" --scene main.tscn --server-ip %SERVER_IP% --server-port %SERVER_PORT%

pause
