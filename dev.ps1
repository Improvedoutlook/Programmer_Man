# Quick dev rebuild script - kills process, rebuilds, and runs
# Usage: .\dev.ps1

$ErrorActionPreference = "Stop"

# Kill any running game process
Write-Host "[1/3] Killing existing processes..." -ForegroundColor Cyan
Get-Process -Name "programmer_man" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

# Force remove the exe to ensure no file locks
$exePath = "zig-out\bin\programmer_man.exe"
if (Test-Path $exePath) {
    Remove-Item $exePath -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
}

# Build
Write-Host "[2/3] Building..." -ForegroundColor Cyan
zig build 2>&1 | Out-String | Write-Host

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

# Run
Write-Host "[3/3] Running game..." -ForegroundColor Green
Write-Host ""
zig build run
