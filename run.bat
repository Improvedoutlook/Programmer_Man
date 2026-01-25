@echo off
echo Closing any running instances...
taskkill /F /IM programmer_man.exe 2>nul
timeout /t 1 /nobreak >nul
echo Building game...
cd /d "%~dp0"
zig build
if errorlevel 1 (
    echo Build failed!
    pause
    exit /b 1
)
echo.
echo Starting game...
zig-out\bin\programmer_man.exe
