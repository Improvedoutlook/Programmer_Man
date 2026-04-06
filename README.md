# Programmer_Man

A simple 2D platformer written in **Zig** using **raylib**.

## Overview

Programmer_Man is a retro-style platformer where you play as a programmer navigating the dangerous world inside a computer motherboard. Jump on bugs to squash them and earn points!

## Features

- **Classic platformer mechanics**: Run, jump, and stomp enemies
- **Hardware-themed visuals**: PCB traces, chips, capacitors, and more
- **Bug enemies**: Patrol-type enemies that can be defeated by jumping on them
- **Scoring system**: +100 points per bug stomped
- **Lives system**: 3 lives with respawn on death

## Controls

| Action | Keys |
|--------|------|
| Move Left | `A` or `←` (Left Arrow) |
| Move Right | `D` or `→` (Right Arrow) |
| Jump | `Space`, `W`, or `↑` (Up Arrow) |
| Pause | `P` or `Escape` |
| Restart (after game over) | `R` |

## Gameplay Mechanics

### Movement
- **Run Speed**: 200 pixels/second
- **Gravity**: 1200 pixels/second²
- **Jump Impulse**: 450 pixels/second
- **Air Control**: 60% of ground acceleration
- **Variable Jump**: Release jump early for shorter jumps

### Combat
- Jump on bugs from above to stomp them
- Stomping gives you a small bounce (60% of jump height)
- Side or bottom collision with bugs = death
- Brief invincibility after respawning

## Building

### Prerequisites

1. **Zig**: Version 0.13.0 or later from [ziglang.org](https://ziglang.org/download/)

### Build Steps

```bash
cd tile-based-raylib-game
zig build
zig build run
```

## Current Status

✅ **Playable & Integrated**: Core gameplay systems are implemented and playable. Raylib rendering is integrated — tilemap, background, player sprite, and procedural enemy/tile rendering all work.  
✅ **Audio**: SFX and music playback are supported and asset files are included under `assets/audio/` and `assets/music/`.  
✅ **Levels**: Three levels are provided as JSON (`assets/data/level1.json`, `assets/data/level2.json`, `assets/data/level3.json`) with a hardcoded fallback builder.

### What's Implemented

- ✅ Player physics & movement (run, jump, coyote time, jump buffering, variable jump)
- ✅ Enemy AI (walker patrols and jumper behavior)
- ✅ Tile-based AABB collision and collision resolution
- ✅ Stomp mechanic, bounce, and scoring (+100 per stomp)
- ✅ Lives, health, respawn, and invincibility frames
- ✅ HUD (score, lives, health/status, game over UI)
- ✅ Level loading from JSON with a fallback builder
- ✅ Hazards (falling sparks) and environmental interactions
- ✅ Camera with render-to-texture scaling and window resizing support
- ✅ Graphics rendering (procedural tiles/enemies; player sprite support)
- ✅ Audio playback (SFX and music streaming)
- ✅ Parallax background and decorative elements
- ✅ Game states (playing, paused, game over, victory/level-complete)
- ✅ Input handling (keyboard mappings, pause, restart, enter to advance)

## Getting Graphics Working

### Option 1: Use raylib-zig Bindings (Recommended)

```bash
# Requires raylib-zig, a pure Zig wrapper for raylib
# Will provide pre-built binaries for Windows
```

### Option 2: Build raylib from Source (MinGW)

```bash
# 1. Download raylib source
git clone https://github.com/raysan5/raylib.git
cd raylib/src

# 2. Build with MinGW (compatible with Zig)
make PLATFORM=PLATFORM_DESKTOP CC=gcc

# 3. Copy the raylib/src/libraylib.a to your project
cp libraylib.a ../../../tile-based-raylib-game/raylib/lib/
```

### Option 3: Alternative Graphics Libraries

The game logic is completely independent of graphics. You can swap in:
- **SDL2**: Mature, cross-platform
- **mach-core**: Modern Zig game engine
- **Pixel Perfect**: Lightweight Zig graphics
- **GLFW + OpenGL**: Direct rendering

## Project Structure

```
tile-based-raylib-game/
├── build.zig           # Zig build configuration
├── build.zig.zon       # Package manifest
├── src/
│   ├── main.zig        # Entry point, game loop
│   ├── game.zig        # Game state management
│   ├── config.zig      # Game constants
│   ├── player.zig      # Player physics & rendering
│   ├── enemy.zig       # Bug enemy AI
│   ├── tilemap.zig     # Level tiles & collision
│   ├── hazards.zig     # Environmental hazards (sparks)
│   ├── audio.zig       # Music + SFX playback
│   ├── background.zig  # Parallax/background effects
│   └── test_window.zig # Small test harness
├── assets/
│   ├── data/
│   │   ├── level1.json
│   │   ├── level2.json
│   │   ├── level3.json
│   │   └── tileset.json
│   ├── audio/
│   │   ├── jump.wav
│   │   ├── pounce.wav
│   │   └── stomp.wav
│   ├── music/
│   │   ├── lost_in_hyperspace.mp3
│   │   ├── danger_streets.mp3
│   │   └── lone_fighter.mp3
│   └── Sprites/
│       └── player.png
└── docs/
    └── PRD.md          # Product Requirements
```

## Technical Details

### Tile System
- Tile size: 16x16 pixels
- Player size: 24x36 pixels (configured in `src/config.zig`)
- Screen: 800x600 pixels (50x37 tiles)

### Physics
- Fixed timestep at 60 FPS
- AABB collision detection
- Tile-based level collision

### Tile Types
- **Solid**: Basic platform tiles (PCB green)
- **Chip**: IC chip decorative platforms
- **Capacitor**: Capacitor decorative platforms
- **Trace**: Non-solid PCB decoration

## Phase 1 MVP Checklist

- [x] Player movement (run, jump)
- [x] Platform collisions
- [x] Basic physics (gravity, max fall speed, variable jump)
- [x] Enemy (bug) movement and patrol AI
- [x] Stomp-to-defeat mechanic with bounce
- [x] One playable level with hardware theme (JSON levels + fallback builder)
- [x] Basic rendering (procedural tiles & shapes; player sprite present)
- [x] Scoring system (+100 per stomp)
- [x] Lives and respawn system
- [x] Game over / Victory states
- [x] Pause functionality
- [x] Graphics rendering (raylib integration complete)
- [x] Audio playback (SFX and music)

## Future Enhancements (Post Phase 1)

- [ ] Expand sprite coverage and animations (enemies, tiles, VFX)
- [ ] More levels with progressive difficulty (beyond the included 3)
- [ ] Power-ups (speedboost, shield, etc.)
- [ ] Save/load system
- [ ] High score tracking and leaderboards
- [ ] Polish art, animations, and audio mix

## Code Statistics

- **~2.9k lines** of pure Zig game code
- **Zero external dependencies** (except graphics library)
- **Full physics simulation** with proper collision
- **Complete game loop** with state management
- **AI system** for enemy behavior
- **Modular design** for easy extension

## License

This project is licensed under the MIT License.

## Notes

Graphics and audio are integrated; this repository contains a playable MVP focusing on core gameplay. Next work: art/animation polish, level design, balancing, and additional features listed above.