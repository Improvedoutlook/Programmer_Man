# Product Requirements Document (PRD)

## Project Title: Programmer_Man — 2D Platformer

### Overview
**Programmer_Man** is a simple 2D platformer written in **Zig** using the **raylib** library. The game features a hardware-themed environment where the player navigates inside a computer motherboard, jumping between platforms and stomping bug enemies.

**Phase 1 Goal**: Produce a playable prototype (MVP) where Programmer_Man can run, jump between platforms, and jump on/squash moving bug enemies in a single level with placeholder 8/16-bit style graphics and a hardware-themed background.

### Goals

**Primary**: Implement core platforming gameplay: run, jump, platform collisions, enemy stomp-to-defeat mechanic.

**Secondary**: Provide simple art placeholders, one playable level, and clear technical guidance for Zig implementation and build.

### Scope (Phase 1 / MVP)

**Included**:
- Player movement (run, jump)
- Platform collisions
- Basic physics (gravity, air control)
- Enemy (bug) movement and stomp defeat
- One level layout
- Placeholder pixel art (rendered shapes)
- Hardware-themed background
- Scoring for bugs
- Build/run instructions for Windows

**Excluded**:
- Multiple levels
- Power-ups
- Save systems
- Complex enemy AI
- Polish audio
- Online features

### Game Features

1. **Tile Size**: 16x16 pixels
2. **Player Dimensions**: 14x16 pixels (14 wide, 16 tall)
3. **Respawn Mechanic**: Player respawns at level start upon death, with brief invincibility

### Gameplay Mechanics

#### Player Controls
| Action | Keys |
|--------|------|
| Move Left | `A` or `←` |
| Move Right | `D` or `→` |
| Jump | `Space`, `W`, or `↑` |

#### Movement Parameters
| Parameter | Value |
|-----------|-------|
| Run Speed | 200 px/s |
| Gravity | 1200 px/s² |
| Jump Impulse | 450 px/s |
| Max Fall Speed | 900 px/s |
| Air Control | 60% of ground acceleration |
| Bounce Factor | 60% of jump impulse |

#### Jump / Stomp Rules
- Enemy is defeated if player collides from above while falling (vertical velocity > 0)
- On stomp: enemy plays defeat animation, removed; player receives small bounce
- Side/bottom collision with enemy: player dies and respawns

#### Scoring & Feedback
- +100 points per bug stomp
- HUD displays score and lives
- Game over screen when all lives lost
- Victory screen when all bugs defeated

### Enemies (Bugs)

**Visual**: Simple rendered bug shape (placeholder)

**Behavior**:
- Walk horizontally at constant speed (56 px/s)
- Turn around at platform edges or obstacles
- Deterministic patrol pattern

**Spawn**: Placed in level data; no respawn after defeated

### Level & World Design

**Single Level**: Short level demonstrating platforming, gaps, vertical sections, multiple bugs

**Theme**: Interior of computer — motherboard traces, chips, capacitors as platforms

**Tile Types**:
- Solid (PCB substrate green)
- Chip (IC chip appearance)
- Capacitor (cylinder shape)
- Trace (decorative, non-solid)

### Technical Specifications

- **Programming Language**: Zig
- **Game Library**: raylib (via raylib-zig bindings)
- **Physics**: Tile-based collision + AABB for entities
- **Target**: Windows (primary)

### File Structure

```
tile-based-raylib-game/
├── build.zig           # Zig build configuration
├── build.zig.zon       # Package dependencies
├── src/
│   ├── main.zig        # Entry point
│   ├── game.zig        # Game state management
│   ├── config.zig      # Constants
│   ├── player.zig      # Player module
│   ├── enemy.zig       # Bug enemy module
│   └── tilemap.zig     # Level and collision
├── assets/
│   └── data/
│       └── level1.json # Level data
└── docs/
    └── PRD.md          # This document
```

### Development Milestones

1. ✅ Project setup with Zig and raylib
2. ✅ Player controller with physics
3. ✅ Tilemap and collision system
4. ✅ Enemy AI and stomp mechanic
5. ✅ Level design and game states
6. ✅ Build documentation

### Acceptance Criteria

- [x] **Playable Controls**: Player can move left/right and jump responsively
- [x] **Platform Collisions**: Player collides correctly with platforms
- [x] **Enemy Stomp**: Player can jump on bugs and defeat them; scoring increments
- [x] **Enemy Movement**: Bugs patrol and turn at edges/obstacles
- [x] **Single Level**: One designed level with hardware-styled background
- [x] **Build & Run**: Project builds on Windows with documented steps
- [x] **Placeholder Art**: Sprites are readable and distinct

### Future Enhancements (Post Phase 1)

- Sprite-based graphics
- Sound effects and music
- Multiple levels
- Power-ups
- Animated sprites
- Parallax scrolling
- Save system