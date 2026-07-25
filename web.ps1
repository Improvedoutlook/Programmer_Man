# Quick web build script - compiles to WebAssembly and serves it in the browser.
# Usage:
#   .\web.ps1            # build + serve in the browser  <- use this one
#   .\web.ps1 -BuildOnly # just produce zig-out\htmlout\ without serving
#   .\web.ps1 -Optimized # slow build, matches the live site (rarely needed)
#
# NEITHER OF THESE DEPLOYS ANYTHING. Deploys happen when you push to
# develop-main: .github/workflows/deploy-pages.yml rebuilds the game on GitHub's
# machines and publishes it. This script only builds on your PC, for you.
#
# The speed knob: Emscripten's optimization level, 0 (don't optimize, build
# fast) through 3 (optimize hard, build slow). Almost all of a web build's wall
# time is that one step, so this script uses -O1 and a rebuild takes ~8s instead
# of ~19s. The tradeoff is a ~2x bigger .wasm that runs somewhat slower.
#
# The GitHub build always uses -O3, because -Dweb-fast defaults to false in
# build.zig and the workflow never passes it. So the live site is unaffected by
# anything here, and there is nothing you need to remember before pushing.
#
# -Optimized just builds with -O3 locally, so you can try the exact thing the
# live site will serve without waiting for a deploy. Worth it if you're checking
# frame rate, or if the deployed game misbehaves in a way your local build
# doesn't (this project has hit web-only memory bugs before - see build.zig).
# Otherwise ignore it.

param([switch]$BuildOnly, [switch]$Optimized)

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
if ($Optimized) {
    Write-Host "Optimized (-O3), matching the live site. Takes ~10s longer." -ForegroundColor Yellow
}
Write-Host ""

# Build the arg list explicitly so it stays a real array. The build+serve step
# is "run-web"; appending it only when serving keeps splatting (@zigArgs) safe.
$zigArgs = @("build", "-Dtarget=wasm32-emscripten", "-Doptimize=ReleaseFast", "--sysroot", $emscripten)
if (-not $Optimized) { $zigArgs += "-Dweb-fast=true" }
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
