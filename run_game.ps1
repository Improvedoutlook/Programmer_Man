# Programmer_Man - Game Launcher
Set-Location "c:\Programmer_Man\tile-based-raylib-game"

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Programmer_Man - 2D Platformer" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Building game..." -ForegroundColor Yellow

# Clean and build
Remove-Item "zig-out\bin\programmer_man.exe" -Force -ErrorAction SilentlyContinue
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
