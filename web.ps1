# Quick web build script - compiles to WebAssembly and serves it in the browser.
# Usage:
#   .\web.ps1            # build + serve in the browser (default)
#   .\web.ps1 -BuildOnly # just produce zig-out\htmlout\ without serving

param([switch]$BuildOnly)

$ErrorActionPreference = "Stop"

# Path to the Emscripten compiler. Override by setting $env:EMSDK_EMSCRIPTEN if
# you installed emsdk somewhere other than the default location below.
$emscripten = if ($env:EMSDK_EMSCRIPTEN) { $env:EMSDK_EMSCRIPTEN } else { "C:\Users\HP\emsdk\upstream\emscripten" }

if (-not (Test-Path $emscripten)) {
    Write-Host "Emscripten not found at: $emscripten" -ForegroundColor Red
    Write-Host "Install it (see README 'Web / Browser Build') or set `$env:EMSDK_EMSCRIPTEN to its path." -ForegroundColor Yellow
    exit 1
}

if ($BuildOnly) {
    Write-Host "Building WebAssembly (no server)..." -ForegroundColor Cyan
} else {
    Write-Host "Building WebAssembly + serving in browser..." -ForegroundColor Cyan
}
Write-Host ""

# Build the arg list explicitly so it stays a real array. The build+serve step
# is "run-web"; appending it only when serving keeps splatting (@zigArgs) safe.
$zigArgs = @("build", "-Dtarget=wasm32-emscripten", "-Doptimize=ReleaseFast", "--sysroot", $emscripten)
if (-not $BuildOnly) { $zigArgs += "run-web" }

& zig @zigArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

if ($BuildOnly) {
    Write-Host ""
    Write-Host "Done. Output is in zig-out\htmlout\ (serve it over HTTP, not file://)." -ForegroundColor Green
}
