# Product Requirements Document (PRD)

## Feature: Level 4 — "Silicon Ascent" (Vertical Climb with Moving Platforms)

### Project: Programmer_Man

---

## 1. Overview

Level 4 is a new, fourth playable stage that extends the existing level progression.
Two structural changes precede it:

1. **Level 3 stops being the end of the game.** Today, completing Level 3 shows the
   final "You beat the game!" screen. After this feature, Level 3 shows the *same*
   "Level Complete — Press Enter to continue" victory screen that Levels 1 and 2 show,
   and advances the player into Level 4. **Level 4 becomes the new final level.**

2. **Level 4 introduces vertical level design and moving platforms.** Unlike Levels 1–3,
   which scroll horizontally, Level 4 scrolls **upward** — the player climbs from the
   bottom of a tall level to a terminal at the top, as if scaling a mountain made of
   computer hardware. **Moving platforms** are introduced as a new traversal mechanic and
   primary source of challenge.

Level 4 reuses the existing data-driven framework (`assets/data/levelN.json` parsed by
`tilemap.zig`), the existing bug/stomp/terminal/scoring systems, and the existing camera.
It adds: a taller world, a new background theme, a moving-platform subsystem, and a new
music track (`transmission.mp3`).

---

## 2. Goals

- **Seamless progression**: Level 3 → Level 4 → final victory, using the existing victory
  screen flow with no special-casing visible to the player.
- **Vertical traversal**: The camera follows the player upward; the level is taller than it
  is wide and is "climbed" rather than "run across."
- **Moving platforms**: Solid platforms that travel along a fixed path (horizontal or
  vertical) and carry the player when ridden. This is the headline new mechanic.
- **Biggest level yet**: Level 4 has the largest total tile count of any level.
- **Distinct but consistent theme**: Still recognizably "inside a computer" with hardware
  components, but visually differentiated from the motherboard / cooling-bay / core-chamber
  themes of Levels 1–3.
- **Enemy variety preserved**: Bugs still patrol (walker) and jump (jumper), but **bugs are
  never placed on moving platforms** — only on static ground and static platforms.

---

## 3. Assets

| Asset | Path | Notes |
|-------|------|-------|
| Level data | `assets/data/level4.json` | New file, authored in Phase 5. |
| Music | [transmission.mp3](file:///C:/Programmer_Man/tile-based-raylib-game/assets/music/transmission.mp3) | Already present in `assets/music/`. Streamed via the existing `ChiptunePlayer.switchTrack`. |
| Player sprite | `assets/sprites/player.png` | Reused, no change. |

> **Note on the JSON `music` field:** The `"music"` string in the level JSON (e.g.
> `"music": "transmission"`) is currently **informational only** — the actual track is
> chosen by a hardcoded `switch` in `Game.loadLevel`. Phase 6 wires the real playback. Keep
> the JSON field for documentation/consistency with Levels 1–3.

---

## 4. Current-State Reference (read before implementing)

These are the exact integration points in the existing code. Line numbers are approximate.

- **`src/game.zig`**
  - `const MAX_LEVELS: u8 = 3;` (~line 96) — total level count; gates final victory.
  - `Game.loadLevel(self, level: u8)` (~line 169) — `switch (level)` chooses background
    theme, JSON file, and music; the `else` arm currently catches index 3.
  - `updatePlaying` (~line 363) — order of updates: `player.update` → `bugs.update` →
    `sparks.update` → `camera.follow` → collision checks → terminal/victory check.
  - `game_complete = (self.current_level >= Self.MAX_LEVELS - 1);` (~line 435) — decides
    final-victory vs. continue.
  - `updateVictory` (~line 461) — `if (game_complete)` shows final + restart; `else` shows
    "Press Enter to continue" and calls `loadLevel(current_level + 1)`.
  - `render` (~line 487) — world-space block (inside `camera.begin/end`) renders background,
    tilemap, terminal, sparks, bugs, player. **Moving platforms must be rendered here.**
- **`src/config.zig`**
  - `MAX_LEVEL_HEIGHT: i32 = TILES_Y;` (= 37, ~line 66) — **hard cap on level height.**
  - `MAX_LEVEL_WIDTH: i32 = 200;` — width cap (Level 4 stays within this).
  - `TILE_SIZE = 16`, `GAME_WIDTH = 800`, `GAME_HEIGHT = 600`.
- **`src/tilemap.zig`**
  - `BackgroundTheme` enum (~line 17): `motherboard`, `cooling_bay`, `core_chamber`.
  - `renderBackground` switch (~line 193) dispatches per theme.
  - JSON schema structs (`JsonLevelSchema`, etc., ~line 559) and `loadLevelFromJson`
    (~line 636). `parseFromSlice` uses `.ignore_unknown_fields = true`, so new JSON keys are
    safely ignored until the schema is extended.
  - `LevelData` (~line 615) — the struct returned to `game.zig`.
- **`src/player.zig`**
  - `Player.respawn` (~line 98) — **hardcodes `config.SPAWN_TILE_X/Y`** instead of the
    level's spawn. Must be fixed (Phase 1).
  - `moveAndCollide` (~line 187) — tile-only AABB collision; sets `on_ground`.
  - Falling off the level bottom (`y > level_pixel_height + 50`) = death (~line 181).
- **`src/audio.zig`**
  - `ChiptunePlayer.switchTrack(path: [:0]const u8)` (~line 162) — stops/unloads/loads/plays.

---

## 5. Implementation Phases

Each phase is independently buildable and testable. Implement in order; later phases depend
on earlier ones. After every phase, the project must compile (`zig build`) and run.

---

### Phase 0 — Progression: make Level 3 advance instead of ending the game

**Objective:** Completing Level 3 shows the standard "continue" victory screen and loads
Level 4. Level 4 becomes the final level.

**Files:** `src/game.zig`

**Changes:**

1. Bump the level count:
   ```zig
   const MAX_LEVELS: u8 = 4; // Level 1=idx0, Level 2=idx1, Level 3=idx2, Level 4=idx3
   ```
   This alone reroutes Level 3 (index 2) through the `else` branch of `updateVictory`
   (continue), because `game_complete = current_level >= MAX_LEVELS - 1` is now only true at
   index 3.

2. Add an explicit `case 3` to the `switch (level)` in `loadLevel` for the background theme:
   ```zig
   self.tilemap.setBackgroundTheme(switch (level) {
       0 => .motherboard,
       1 => .cooling_bay,
       2 => .core_chamber,
       3 => .silicon_ascent, // added in Phase 2
       else => .motherboard,
   });
   ```

3. Add the Level 4 data-loading arm in the `switch (level)` body (mirror the `case 2` arm),
   pointing at `assets/data/level4.json`:
   ```zig
   3 => {
       if (tilemap_builder.loadLevelFromJson(&self.tilemap, "assets/data/level4.json")) |level_data| {
           self.applyLevelData(level_data, &spawn_x, &spawn_y);
       } else |_| {
           tilemap_builder.createLevel1(&self.tilemap);
           self.spawnBugsLevel1();
           self.spawnSparksLevel1();
           self.terminal_pos = .{ .x = 6, .y = 28 };
       }
   },
   ```

4. Music switch arm (full wiring in Phase 6, but add the case now):
   ```zig
   3 => music.switchTrack("assets/music/transmission.mp3"),
   ```

**Acceptance:**
- Finishing Level 3 shows "PR Submitted — Level 3 Complete!" with "Press Enter to continue".
- Pressing the continue key loads Level 4 (will be a placeholder/fallback level until
  Phase 5 authors `level4.json`).
- Finishing Level 4 shows the final "You beat the game!" screen.
- Score and lives carry across the 3 → 4 transition (existing behavior in `loadLevel`).

> **Note:** `silicon_ascent` is referenced here but defined in Phase 2. Implement Phase 2's
> enum variant first, or temporarily map `3 => .motherboard` and switch it after Phase 2.

---

### Phase 1 — Engine: support tall (vertical) levels + fix respawn

**Objective:** Allow levels taller than one screen and make respawn return the player to the
*level's* spawn point (required for a tall, bottom-spawn level).

**Files:** `src/config.zig`, `src/player.zig`, `src/game.zig`

**Changes:**

1. **Raise the height cap** in `config.zig`:
   ```zig
   // Was: pub const MAX_LEVEL_HEIGHT: i32 = TILES_Y; // 37
   pub const MAX_LEVEL_HEIGHT: i32 = 160; // tiles (2560 px) — supports tall vertical levels
   ```
   - Memory impact: `Tilemap.tiles` is `[MAX_LEVEL_HEIGHT][MAX_LEVEL_WIDTH]TileType`
     (1 byte each) → `160 × 200 = 32,000` bytes (~31 KB), up from ~7.4 KB. Acceptable, but
     confirm the `Game`/`Tilemap` value isn't copied on a hot path. If stack size becomes a
     concern, no action needed unless `zig build` reports a stack-overflow in debug.

2. **Camera:** no change required. `Camera.follow` already clamps vertically using
   `level_pixel_h`. Verify that with a tall level the camera scrolls up as the player climbs
   and stops cleanly at the top/bottom edges.

3. **Fix respawn to honor the level spawn point.** Add spawn fields to `Player` and use them
   in `respawn` instead of `config.SPAWN_TILE_X/Y`:
   ```zig
   pub const Player = struct {
       // ... existing fields ...
       spawn_tile_x: i32 = config.SPAWN_TILE_X,
       spawn_tile_y: i32 = config.SPAWN_TILE_Y,
       // ...
   };
   ```
   In `respawn`, replace the hardcoded constants:
   ```zig
   self.x = @as(f32, @floatFromInt(self.spawn_tile_x * config.TILE_SIZE)) + config.PLAYER_WIDTH / 2;
   self.y = @as(f32, @floatFromInt(self.spawn_tile_y * config.TILE_SIZE));
   ```
   In `game.zig` `loadLevel`, after computing `spawn_x`/`spawn_y` and re-initializing the
   player, set the new fields so respawns are correct for every level:
   ```zig
   self.player.spawn_tile_x = spawn_x;
   self.player.spawn_tile_y = spawn_y;
   ```

**Acceptance:**
- A level with `height > 37` loads without clamping/overflow.
- The camera follows the player up a tall level and clamps at top and bottom.
- Dying mid-climb (losing a life with lives remaining) respawns the player at the level's
  defined spawn (bottom of the climb), **not** at tile (3, 35).
- Levels 1–3 are unaffected (their spawns are unchanged).

---

### Phase 2 — Background: new "Silicon Ascent" theme

**Objective:** A new background theme that reads as "inside a computer" but is visually
distinct from Levels 1–3 and reinforces verticality (a climb up a tower/mountain of hardware).

**Files:** `src/tilemap.zig`

**Design direction:** Lean on **vertical** motifs to sell the climb — tall heatsink fins /
aluminum cooling towers receding into the distance, vertical RAM sticks stacked upward,
rising vertical data buses (reuse `drawDataBus` rotated conceptually, or vertical light
strips), and a cool steel/blue or violet palette that differs from the existing three. Reuse
existing primitive helpers (`drawCircuitMesh`, `drawCoolingFan`, `drawBoardModule`,
`drawDataBus`, `drawLightStrip`, `drawProcessorSocket`) so the look stays cohesive.

**Changes:**

1. Add the enum variant:
   ```zig
   pub const BackgroundTheme = enum {
       motherboard,
       cooling_bay,
       core_chamber,
       silicon_ascent, // Level 4 — vertical hardware climb
   };
   ```

2. Add a dispatch arm in `renderBackground`:
   ```zig
   .silicon_ascent => self.renderSiliconAscentBackground(lw, lh),
   ```

3. Implement `renderSiliconAscentBackground(self, lw, lh)` following the structure of the
   existing theme renderers. Suggested elements:
   - Distinct base fill (e.g., cool steel-blue `{ r=12, g=18, b=30 }` or a vertical gradient
     feel via stacked rectangles).
   - `drawCircuitMesh` with different spacing/colors than the other themes.
   - A repeating **vertical** loop over the level height (`while (y < lh)`) drawing tall
     heatsink-fin columns and vertical RAM-stick modules, so the parallax of the climb is felt
     as the camera rises.
   - Animated accents using `self.background_time` (consistent with other themes).

**Acceptance:**
- Level 4 renders with a clearly different look from Levels 1–3 while remaining hardware-themed.
- No regression to the other three themes.
- Background animates (fans/pulses) and fills the full tall level height.

---

### Phase 3 — Moving platforms: data + subsystem + movement/rendering (no collision yet)

**Objective:** Introduce a moving-platform entity that can be authored in level JSON, updated
each frame (ping-pong along a path), and rendered. Collision/carry comes in Phase 4.

**Files:** new `src/platform.zig`; `src/tilemap.zig` (JSON schema + `LevelData`);
`src/game.zig` (own, reset, spawn, update, render); `build.zig` only if modules must be
registered (raylib-zig style usually imports directly — verify).

**3a. JSON schema.** Add an optional `moving_platforms` array to the level format. Example:
```json
"moving_platforms": [
  { "x": 10, "y": 120, "width": 4, "tile_type": "solid", "axis": "horizontal", "distance": 8,  "speed": 2.0, "phase": 0.0 },
  { "x": 22, "y": 96,  "width": 3, "tile_type": "chip",  "axis": "vertical",   "distance": 10, "speed": 1.5, "phase": 0.5 }
]
```
Field semantics:
| Field | Meaning |
|-------|---------|
| `x`, `y` | Tile coords of the platform's **start** position (top-left). |
| `width` | Platform width in tiles (height is 1 tile). |
| `tile_type` | Visual style string (`solid`/`chip`/`capacitor`), reuse `jsonTileType`. |
| `axis` | `"horizontal"` or `"vertical"` travel direction. |
| `distance` | Travel range in tiles (platform ping-pongs between start and start+distance along `axis`). |
| `speed` | Travel speed in **tiles/second**. |
| `phase` | 0.0–1.0 starting offset along the path (lets platforms desync). |

In `tilemap.zig`, add the parse struct and extend `JsonLevelSchema` (keep it optional with a
default so Levels 1–3 JSON still parse):
```zig
const JsonMovingPlatform = struct {
    x: i32,
    y: i32,
    width: i32,
    tile_type: []const u8 = "solid",
    axis: []const u8 = "horizontal",
    distance: i32,
    speed: f32 = 1.0,
    phase: f32 = 0.0,
};
// In JsonLevelSchema:
moving_platforms: []const JsonMovingPlatform = &.{},
```

**3b. `LevelData` extension** (`tilemap.zig`). Add a fixed-capacity array, mirroring the
bug/spark pattern:
```zig
pub const MAX_MOVING_PLATFORMS: usize = 16;

pub const MovingPlatformSpawn = struct {
    tile_x: i32,
    tile_y: i32,
    width_tiles: i32,
    tile_type: TileType,
    vertical: bool,     // false = horizontal
    distance_tiles: i32,
    speed_tiles: f32,
    phase: f32,
};

// In LevelData:
moving_platforms: [MAX_MOVING_PLATFORMS]MovingPlatformSpawn,
moving_platform_count: usize,
```
Populate it inside `loadLevelFromJson` by iterating `level.moving_platforms` (cap at
`MAX_MOVING_PLATFORMS`), translating `axis == "vertical"` to the `vertical` bool.

**3c. New module `src/platform.zig`.** A self-contained struct + manager, styled after
`enemy.zig`'s `BugManager` and `hazards.zig`'s `SparkManager`:
```zig
pub const MovingPlatform = struct {
    // All in pixels.
    x: f32,
    y: f32,
    width: f32,
    height: f32, // = TILE_SIZE
    tile_type: TileType,
    vertical: bool,
    min_pos: f32,   // along travel axis
    max_pos: f32,
    speed: f32,     // px/s
    dir: f32,       // +1 / -1
    dx: f32,        // delta moved this frame (for carrying the player)
    dy: f32,
    active: bool,

    pub fn update(self: *MovingPlatform, dt: f32) void {
        const prev_x = self.x;
        const prev_y = self.y;
        if (self.vertical) {
            self.y += self.speed * self.dir * dt;
            if (self.y < self.min_pos) { self.y = self.min_pos; self.dir = 1; }
            if (self.y > self.max_pos) { self.y = self.max_pos; self.dir = -1; }
        } else {
            self.x += self.speed * self.dir * dt;
            if (self.x < self.min_pos) { self.x = self.min_pos; self.dir = 1; }
            if (self.x > self.max_pos) { self.x = self.max_pos; self.dir = -1; }
        }
        self.dx = self.x - prev_x;
        self.dy = self.y - prev_y;
    }

    pub fn getRect(self: *const MovingPlatform) rl.Rectangle { /* AABB */ }
    pub fn render(self: *const MovingPlatform) void { /* draw a clearly-moving platform */ }
};

pub const MovingPlatformManager = struct {
    platforms: [MAX_MOVING_PLATFORMS]MovingPlatform,
    count: usize,
    pub fn init() MovingPlatformManager { ... }
    pub fn reset(self: *Self) void { self.count = 0; }
    pub fn spawn(self: *Self, spawn: MovingPlatformSpawn) void { ... } // tiles → pixels, apply phase
    pub fn update(self: *Self, dt: f32) void { ... }   // update all active
    pub fn render(self: *const Self) void { ... }
    // resolvePlayer added in Phase 4
};
```
- **Phase application:** offset the starting position by `phase * distance` along the axis,
  and set `dir` accordingly, so platforms don't all start in lockstep.
- **Rendering:** give moving platforms a distinct, readable look (e.g., the chosen
  `tile_type` fill plus an animated edge highlight or directional chevrons) so players can
  tell they move. Render per-tile across `width` for visual consistency with static tiles.

**3d. `game.zig` wiring:**
- Add field `moving_platforms: platform.MovingPlatformManager,` and init it in `Game.init`.
- In `loadLevel`, call `self.moving_platforms.reset();` near the other resets, and in
  `applyLevelData` spawn from `level_data.moving_platforms[0..moving_platform_count]`.
- In `updatePlaying`, call `self.moving_platforms.update(dt);` **before** `player.update`
  is fine for movement, but the carry pass (Phase 4) runs **after** `player.update`. For this
  phase, just call `update` (e.g., right after `self.sparks.update(dt)`), no collision.
- In `render` (world-space block, inside `camera.begin/end`), call
  `self.moving_platforms.render();` — draw it **after** the tilemap and before/after bugs as
  preferred (recommend after tilemap, before player).

**Acceptance:**
- `level4.json` (or a temporary test entry) with `moving_platforms` parses without error.
- Platforms appear and visibly oscillate along their configured axis/range/speed.
- Levels 1–3 JSON (no `moving_platforms` key) still load (default empty slice).
- Player does **not** yet interact with them (expected — collision is Phase 4).

---

### Phase 4 — Moving platforms: collision & carry

**Objective:** The player can stand on, ride, and be carried by moving platforms.

**Files:** `src/platform.zig` (resolve routine), `src/game.zig` (call it after `player.update`).

**Approach — top-ride one-way collision with carry** (sufficient for a climbing level;
side/ceiling collision is an optional extension below):

Add to `MovingPlatformManager`:
```zig
/// Resolve the player against all moving platforms after tile physics have run.
/// Lands the player on top of any platform they're falling onto and carries them
/// by that platform's per-frame delta.
pub fn resolvePlayer(self: *Self, player: *Player) void {
    var i: usize = 0;
    while (i < self.count) : (i += 1) {
        const p = &self.platforms[i];
        if (!p.active) continue;

        const pr = player.getRect();          // player AABB (top-left + size)
        const feet = pr.y + pr.height;        // player's bottom edge
        const plat = p.getRect();

        const horizontally_overlapping =
            pr.x < plat.x + plat.width and pr.x + pr.width > plat.x;

        // Landing/standing tolerance: feet within a small band of the platform top,
        // and the player is moving downward (or resting).
        const landing = horizontally_overlapping and
            player.vy >= 0 and
            feet >= plat.y - 6 and feet <= plat.y + 8;

        if (landing) {
            // Snap feet to platform top (player.y is feet position).
            player.y = plat.y;
            player.vy = 0;
            player.on_ground = true;
            // Carry: move with the platform this frame.
            player.x += p.dx;
            player.y += p.dy;
        }
    }
}
```
Notes / requirements:
- `player.y` is the **feet** position (center-bottom); `getRect` returns top-left
  (`y - PLAYER_HEIGHT`). Use these consistently — see `player.zig`.
- Call order in `updatePlaying`:
  1. `self.moving_platforms.update(dt);`
  2. `self.player.update(dt, &self.tilemap);` (tile physics)
  3. `self.moving_platforms.resolvePlayer(&self.player);` (land + carry)
  4. `self.camera.follow(...);`
- **Carry both axes:** horizontal platforms carry `dx`; vertical platforms moving up push the
  player up via the snap each frame (and `dy`), acting like an elevator. A vertical platform
  moving down lets gravity keep the player attached as long as feet stay in the landing band.
- After carrying, **re-clamp** the player to horizontal level bounds (the existing clamp lives
  in `player.moveAndCollide`; if carry can push past edges, add a clamp here too).
- Coyote time: `player.update` may set `on_ground = false` before this pass; setting it back
  to `true` here is correct. Leaving a platform should restore normal coyote behavior on the
  next frame automatically.

**Optional extension (side/ceiling blocking):** If a platform should also block the player
from the sides or below (e.g., a horizontal platform pushing the player into a wall), add AABB
push-out for the non-landing cases. Not required for the climb; implement only if playtesting
shows the player clipping through platform sides.

**Acceptance:**
- The player can land on a moving platform and is carried horizontally with it.
- A vertical platform lifts the player upward (elevator behavior) and lowers them.
- Jumping off a moving platform behaves normally (no stickiness, normal jump arc).
- The player does not fall through a platform they're standing on.
- Walking off the edge of a moving platform drops the player (no phantom floor).

---

### Phase 5 — Author `assets/data/level4.json` (the biggest level yet)

**Objective:** A tall, vertical, hardware-themed climb that is the largest level by total
tile count, using moving platforms as the central challenge, with bugs only on static geometry.

**Files:** `assets/data/level4.json`

**Required structure** (matches `JsonLevelSchema`; all listed top-level keys must be present):
```json
{
  "meta": {
    "tile_types": "solid, chip, capacitor, trace — see tilemap.zig TileType enum",
    "ai_types": "walker (default), jumper (intermittent jumping)",
    "moving_platforms": "axis horizontal|vertical, distance in tiles, speed in tiles/sec, phase 0..1"
  },
  "name": "Silicon Ascent",
  "description": "Level 4 - Climb the heatsink tower. Ride the buses up to the summit terminal.",
  "width": 60,
  "height": 150,
  "spawn":    { "x": 5,  "y": 148 },
  "terminal": { "x": 30, "y": 4 },
  "music": "transmission",
  "ground": { "y": 148, "segments": [ { "x1": 0, "x2": 60 } ] },
  "platforms": [ /* static platforms forming a climbable, switch-backing path upward */ ],
  "moving_platforms": [ /* the new mechanic — fill vertical gaps in the climb */ ],
  "decorations": [ /* trace lines for depth */ ],
  "bugs": [ /* walkers + jumpers ONLY on ground and static platforms */ ]
}
```

**Authoring requirements:**
- **Vertical orientation:** `height` substantially greater than `width`. Suggested ~150 tall
  × ~60 wide (must stay ≤ `MAX_LEVEL_HEIGHT` from Phase 1 and ≤ `MAX_LEVEL_WIDTH = 200`).
- **Biggest level yet:** total `width × usable area` should exceed Level 3 (120 × 37). At
  60 × 150 the world is far larger; ensure the *playable* path is correspondingly long.
- **Spawn at bottom, terminal at top:** `spawn.y` near the bottom row, `terminal.y` near the
  top (small y). The player climbs upward.
- **Climb design:** Use static platforms in a switch-back / zig-zag pattern so the player
  ascends. Insert **vertical gaps that can only be crossed via moving platforms** — both
  horizontal "ferries" (carry the player across a gap) and vertical "elevators" (lift the
  player up a tall section). Stagger `phase` so timing matters.
- **Bugs:** Place walkers and jumpers on the ground segment and on **static** platforms only.
  **Do not** place any bug on (or directly above the travel path of) a moving platform.
  Respect `MAX_SPAWN_ENTRIES = 32` and `MAX_BUGS = 32`.
- **Moving platforms:** Respect `MAX_MOVING_PLATFORMS = 16`. Keep widths ≥ 3 tiles so they're
  comfortably ridable. Avoid travel paths that would crush the player against static tiles.
- **Sparks (optional):** Static platforms may set `"sparks": true` for hazard variety, as in
  Level 3. Do not rely on sparks from moving platforms (the spark system reads static
  platform data).
- **Terminal reachability:** Verify the player can reach the terminal using the intended
  combination of jumps and moving platforms. All bugs must be defeatable (the terminal only
  activates once `all_bugs_defeated`).
- **Fall = death:** Falling off the bottom is death (existing behavior). Ensure the climb has
  fair recovery points; respawn returns the player to `spawn` (Phase 1 fix).

**Acceptance:**
- `level4.json` parses and loads via the `case 3` path (no fallback).
- The level is visibly the largest and is climbed vertically.
- Moving platforms are required to complete at least two sections.
- No bug is on a moving platform.
- The summit terminal is reachable and completes the level.

---

### Phase 6 — Audio: wire `transmission.mp3`

**Objective:** Level 4 plays `transmission.mp3` as its background track; it stops on
victory/game-over like other levels.

**Files:** `src/game.zig` (confirm Phase 0's music arm)

**Changes:** Ensure the `switch (level)` music block in `loadLevel` includes:
```zig
3 => music.switchTrack("assets/music/transmission.mp3"),
```
No new audio struct is needed — `ChiptunePlayer.switchTrack` already handles MP3 streaming,
looping (via `update`), and stop. Victory music (`snowball_game.mp3`) and game-over music
(`the_world_ stood_ still.mp3`) reuse the existing players unchanged.

**Acceptance:**
- Entering Level 4 stops Level 3's track and plays `transmission.mp3`, looping seamlessly.
- Dying or reaching the terminal stops `transmission.mp3` and plays game-over/victory music.
- Restarting from final victory (Level 4 complete) returns to Level 1 and restores its track.

---

### Phase 7 — Integration testing & polish

**Objective:** Validate the full feature end-to-end and tune difficulty.

**Checklist:**
- Full playthrough Level 1 → 2 → 3 → 4 → final victory; score/lives persist correctly.
- Level 3's victory screen reads "Level 3 Complete!" with the continue prompt (not final).
- Level 4's victory screen is the final "You beat the game!" with restart prompt.
- Camera scrolls up smoothly; no jitter when riding vertical platforms.
- Moving-platform carry feels solid (no clipping, no stickiness, no fall-through).
- Respawn after death mid-climb returns to the bottom spawn, not tile (3, 35).
- Window resize during Level 4 still letterboxes correctly (no regression).
- Controller and keyboard both navigate the continue/restart prompts.
- `zig build` is clean (no warnings introduced); `zig build run` works.

---

## 6. Files Changed / Added (summary)

| File | Change |
|------|--------|
| `src/config.zig` | Raise `MAX_LEVEL_HEIGHT` to support tall levels. |
| `src/game.zig` | `MAX_LEVELS = 4`; Level 4 load arm; theme + music cases; own/reset/update/render moving platforms; set player spawn fields; call `resolvePlayer`. |
| `src/player.zig` | Add `spawn_tile_x/y` fields; fix `respawn` to use them. |
| `src/tilemap.zig` | `silicon_ascent` theme + renderer; `moving_platforms` JSON schema; `MovingPlatformSpawn` + `LevelData` fields; parse moving platforms. |
| `src/platform.zig` | **New** — `MovingPlatform` + `MovingPlatformManager` (movement, render, `resolvePlayer`). |
| `assets/data/level4.json` | **New** — the Level 4 layout. |
| `build.zig` | Only if a new module must be registered (verify import style first). |

---

## 7. Out of Scope

- Crushing/hazard logic for platforms pinning the player against geometry (beyond the optional
  side-blocking note in Phase 4).
- Bugs riding or interacting with moving platforms.
- New enemy types, power-ups, or save systems.
- Parallax beyond what the existing background renderers provide.
- Difficulty/accessibility options.

---

## 8. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Tall level grows `Tilemap` struct memory / stack use. | 31 KB is modest; if debug stack overflow appears, confirm `Tilemap`/`Game` aren't copied by value on a hot path. |
| Moving-platform carry feels floaty or sticky. | Tight landing band (±6–8 px), `vy >= 0` gate, snap-to-top each frame; tune in Phase 7. |
| Player clips through platform sides. | Implement the optional side-blocking extension in Phase 4 if playtesting requires it. |
| Respawn regression for Levels 1–3. | New `spawn_tile_x/y` default to the old `config.SPAWN_TILE_X/Y`, and `loadLevel` sets them from JSON — behavior identical for existing levels. |
| `case 3` falls back to Level 1 if `level4.json` is missing/invalid. | Author and validate `level4.json` (Phase 5); the fallback prevents a crash during development. |
