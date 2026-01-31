# Programmer_Man - Game Launcher
Set-Location "c:\Programmer_Man\tile-based-raylib-game"

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Programmer_Man - 2D Platformer" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Kill any existing game process to prevent AccessDenied errors during build
$existingProcess = Get-Process -Name "programmer_man" -ErrorAction SilentlyContinue
if ($existingProcess) {
    Write-Host "Stopping existing game process..." -ForegroundColor Yellow
    Stop-Process -Name "programmer_man" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800  # Increased wait time for Windows to release file handles
}

# Additional safety: try to remove the exe if it exists (will fail if still locked)
$exePath = "zig-out\bin\programmer_man.exe"
if (Test-Path $exePath) {
    try {
        Remove-Item $exePath -Force -ErrorAction Stop
        Write-Host "Cleaned previous build" -ForegroundColor Gray
    } catch {
        Write-Host "WARNING: Could not remove old exe (still locked). Waiting..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1000
        try {
            Remove-Item $exePath -Force -ErrorAction Stop
        } catch {
            Write-Host "ERROR: Game process is still running or exe is locked!" -ForegroundColor Red
            Write-Host "Please close all game windows and try again." -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

Write-Host "Building game..." -ForegroundColor Yellow
$buildOutput = zig build 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    Write-Host $buildOutput
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Build successful!" -ForegroundColor Green
Write-Host ""
Write-Host "Controls:" -ForegroundColor Cyan
Write-Host "  Move: A/D or Arrow Keys" -ForegroundColor White
Write-Host "  Jump: Space/W/Up Arrow" -ForegroundColor White
Write-Host "  Pause: P or Escape" -ForegroundColor White
Write-Host "  Restart: R (after game over)" -ForegroundColor White
Write-Host ""
Write-Host "Starting game... (Look for the game window!)" -ForegroundColor Yellow
Write-Host ""

# Run the game
if (Test-Path "zig-out\bin\programmer_man.exe") {
    & ".\zig-out\bin\programmer_man.exe"
    $exitCode = $LASTEXITCODE
    Write-Host ""
    Write-Host "Game exited with code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })
} else {
    Write-Host "ERROR: Game executable not found!" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
