@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem === НАСТРОЙКА ===
rem Укажи путь к своему godot.exe. Примеры:
rem set GODOT_PATH=C:\Program Files\Godot 4\Godot_v4.4.1-stable_win64.exe
rem set GODOT_PATH=D:\Games\Godot\Godot.exe
rem Если Godot добавлен в PATH, можно просто: set GODOT_PATH=godot
set GODOT_PATH=godot

set PROJECT_DIR=%USERPROFILE%\gamedev\fantasy-settlement-mmo
set REPO_URL=https://github.com/xace1825/godot-mmo-rpi.git
set SERVER_IP=192.168.0.102
set SERVER_PORT=7777

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
"%GODOT_PATH%" --path "%PROJECT_DIR%" --scene main.tscn --server-ip %SERVER_IP% --server-port %SERVER_PORT%

pause
