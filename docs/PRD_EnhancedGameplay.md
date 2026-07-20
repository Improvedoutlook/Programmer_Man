# Product Requirements Document (PRD)

## Feature: Enhanced Gameplay — "System Optimization" (Chaotic Lights, Server Room, Dual Objective)

### Project: Programmer_Man

---

## 1. Overview

Every level currently has a single objective: squash all bugs, then press Submit at the
terminal to submit the PR. This feature adds a second, parallel objective and a new
sub-scene, turning each level into a two-task loop:

1. **Chaotic background lights.** At the start of every level the system is "badly bugged":
   all animated lights on the background hardware — the LEDs on the **I/O**, **RAM**, and
   **GPU** board modules, the **CHIPSET**/CPU/GPU processor-socket cells, the light strips,
   the data-bus packets, and the RAM-stick LEDs — flicker **randomly with no pattern**.
   This is the visual signal that the system is misbehaving.

2. **The Server Room.** Near the **middle of each level** a door appears on a platform.
   Programmer Man can enter it into a small single-screen room containing a terminal.
   Interacting with that terminal runs an **"optimizing script"** (`optimize.sh`, shown as
   scrolling terminal output). When the script completes, the system is *optimized*: the
   background lights switch from random chaos to a **clean, ordered, sequential chase
   pattern** — the visible proof that PM fixed the system. Each level's Server Room looks
   slightly different (per-level palette and decor variant).

3. **Dual completion requirement.** To finish a level, PM must **both** squash all bugs
   **and** run the optimizing script — in either order. The PR-submission terminal only
   activates once both are done. The on-screen hint adapts:
   - All bugs squashed but system not yet optimized → *"Bugs squashed! Update the system
     in the Server Room before submitting your PR"*.
   - System optimized but bugs remain → *"System updated! Squash the remaining bugs"*.
   - Both done → *"All tasks complete! Submit your PR at the terminal"*.

This applies to **all four levels**. Score and lives behavior, level progression, victory
screens, music, and the web build are unchanged except where stated.

---

## 2. Goals

- **Readable system state**: a player can tell at a glance — from the background lights
  alone — whether the system is still bugged (chaos) or optimized (ordered chase).
- **A second beat per level**: the Server Room detour breaks up the run-and-stomp loop and
  reinforces the "programmer fixing a broken machine" fantasy.
- **Order-independent objectives**: bugs-then-script and script-then-bugs both work; the
  hint system always tells the player what's left.
- **Room variety**: four room variants that share one layout skeleton but read as four
  different rooms (palette + one signature decor element each).
- **Zero regression**: Levels still load from JSON with graceful fallback; native and
  emscripten builds both compile and play; existing victory/credits flow untouched.
- **Documentation-verified Zig**: every new API call is checked against the pinned-version
  docs listed in §3 before it is written (this project is intentionally held at
  Zig 0.13.0 — see `PRD_ZigRaylibUpdate.md` for why).

---

## 3. Documentation References (MANDATORY for all Zig code)

The toolchain is pinned: **Zig 0.13.0** (`build.zig.zon` → `minimum_zig_version = "0.13.0"`)
and **raylib-zig v5.5**. Do **not** use language features, std APIs, or build APIs from
newer Zig releases. Before writing any new call, verify it against:

| Resource | URL / location | Use for |
|----------|----------------|---------|
| Zig 0.13.0 Language Reference | https://ziglang.org/documentation/0.13.0/ | Syntax, casts (`@intFromFloat`, `@floatFromInt`, `@intCast`), optionals, enums, switch exhaustiveness |
| Zig 0.13.0 Std Library docs | https://ziglang.org/documentation/0.13.0/std/ | `std.json.parseFromSlice`, `std.fmt.bufPrintZ`, `std.math`, `std.mem` |
| raylib 5.5 cheatsheet | https://www.raylib.com/cheatsheet/cheatsheet.html | Function semantics (C names; raylib-zig exposes them camelCase: `DrawRectangle` → `rl.drawRectangle`) |
| raylib-zig v5.5 binding source | Local Zig package cache (find via `zig build --verbose` or search `%APPDATA%/../Local/zig/p/` for `raylib-zig`); upstream: https://github.com/Not-Nik/raylib-zig (tag matching `build.zig.zon`) | Exact Zig signatures/types (`rl.Color`, `rl.Rectangle`, error unions on `loadTexture`, etc.) |

**Working rules for the implementing agent:**

1. **Prefer precedent over docs**: if a raylib call already appears in `src/*.zig`
   (e.g., `rl.drawRectangle`, `rl.drawText`, `rl.drawCircle`, `rl.measureText`,
   `rl.drawTexturePro`), copy its usage pattern exactly. Only consult the cheatsheet +
   binding source for calls **not** yet used in the codebase.
2. **Match existing idioms**, even where newer Zig offers alternatives: this codebase uses
   `std.rand.DefaultPrng` (0.13 name), `catch null` optional-init for resources,
   fixed-capacity arrays + count (no allocators in gameplay code), and
   `std.json.parseFromSlice(..., .{ .ignore_unknown_fields = true })` for level data.
3. **No new dependencies, no allocator use in the render/update path.**
4. Every phase ends with `zig build` (native) compiling clean. Phase 6 also verifies the
   web target:
   `zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast --sysroot "C:\Users\HP\emsdk\upstream\emscripten" run-web`
5. When a compile error reveals an **exhaustive `switch` on `GameState`** elsewhere
   (e.g., `touch.render`), extend that switch deliberately — never add an `else` arm to
   silence it.

---

## 4. Current-State Reference (read before implementing)

Line numbers are approximate as of commit `c0e4993`.

- **`src/game.zig`**
  - `GameState` enum (~line 32): `opening, playing, paused, game_over, victory, credits`.
    A new `server_room` state is added here (Phase 3).
  - `Game` struct (~line 165): owns `tilemap`, `player`, `bugs`, `all_bugs_defeated`,
    `terminal_pos`, `player_texture`. New fields land here.
  - `loadLevel` (~line 285): resets per-level state; `applyLevelData` (~line 409) copies
    parsed JSON (bugs, sparks, moving platforms, terminal, spawn) into managers. The door
    is applied here (Phase 2).
  - `updatePlaying` (~line 564): input → platforms → player → bugs → sparks → camera →
    collisions. **Terminal gating** at ~line 617–650: currently
    `if (self.all_bugs_defeated) { ...overlap + submit_pressed → victory }`. Phase 4
    changes this to require the new flag too.
  - `update` state switch (~line 543) and `render` (~line 749): both get a `server_room`
    arm (Phase 3). `render` draws world inside `camera.begin/end`, then HUD, then
    `renderTerminalHint` when `all_bugs_defeated` (~line 833) — Phase 4 replaces that
    condition with the three-way hint.
  - `renderTerminal` (~line 959): screen turns green when `all_bugs_defeated` — Phase 4
    changes to *both* flags.
  - `renderTerminalHint` (~line 988): the pattern to copy for all new screen-space hints
    (measure text → centered dark box → text).
  - Debug precedent: F12 credits preview (~line 494) — the Phase 1 F11 debug toggle
    follows this pattern and is removed in Phase 4.
- **`src/tilemap.zig`**
  - `Tilemap` struct (~line 24): `background_theme`, `background_time`. The new
    `system_optimized: bool` field lives here so the renderers (which only see `*const
    Self`) can read it.
  - `renderBackground` dispatch (~line 196); theme renderers: `renderMotherboardBackground`
    (~208, draws **I/O**/**RAM** modules + **CHIPSET** sockets), `renderCoolingBayBackground`
    (~265, GPU modules + `drawLightStrip` + buses), `renderCoreChamberBackground` (~318,
    CPU/GPU sockets + energy beams), `renderSiliconAscentBackground` (~562, RAM sticks +
    fins + buses).
  - Light-drawing helpers to modify: `drawBoardModule` LED loop (~501–509),
    `drawProcessorSocket` cell-glow loop (~531–550), `drawLightStrip` (~553),
    `drawDataBus` packet glow (~407–423), `drawRamStick` (~666).
  - `hashFloat` (~line 443): existing deterministic pseudo-random helper — reuse it for
    the chaos flicker (no RNG state needed in `*const` render paths).
  - JSON schema: `JsonLevelSchema` (~line 737, uses defaulted fields so old JSON still
    parses), `LevelData` (~line 785), `loadLevelFromJson` (~line 808).
- **`src/controls.zig`**
  - `FrameInput` (~line 27): `move_x`, `jump_pressed/down`, `submit_pressed`,
    `pause_pressed`, `restart_pressed`. Door entry and terminal interaction reuse
    `submit_pressed` (on touch, a jump tap also sets `submit_pressed` — same behavior as
    the existing PR terminal, keep it).
  - `getActionPrompt(.submit, has_gamepad)` — use for all "Press X" hint strings.
- **`src/player.zig`**: `getRect()` returns the AABB used for terminal overlap — reuse for
  door overlap. `player.x/y` must NOT be touched by the Server Room (world position is
  preserved across the room visit).
- **`src/config.zig`**: screen/game dimensions, `HUD_COLOR`, `TILE_SIZE = 16`. New
  constants (walk speed in room, script timing, bonus score) go here.
- **Level JSONs** (`assets/data/level1..4.json`): dimensions 100×37, 110×37, 120×37,
  60×150. All parse through `loadLevelFromJson` with `.ignore_unknown_fields = true`, so
  the new `server_door` key can be added to the schema without breaking anything.

---

## 5. Implementation Phases

Each phase is independently buildable and testable. Implement in order. After every phase
the project must compile (`zig build`) and be fully playable start-to-finish.

---

### Phase 1 — System state + chaotic vs. ordered background lights

**Objective:** Introduce the `system_optimized` flag and make every animated light element
in all four background themes render **random chaos** when `false` and an **ordered
sequential chase** when `true`. Gameplay/completion rules unchanged in this phase.

**Files:** `src/tilemap.zig`, `src/game.zig`

**Docs to verify first:** none beyond §3 rules — this phase only uses raylib calls already
present (`drawRectangle`, `drawCircle`) and Zig builtins (`@sin`, `@mod`, `@floor`,
`@intFromFloat`) — confirm builtin cast rules in the 0.13.0 langref if unsure.

**Changes:**

1. **Flag on `Tilemap`** (renderers only receive `*const Tilemap`):
   ```zig
   pub const Tilemap = struct {
       // ... existing fields ...
       system_optimized: bool,
       // init() / initDefault() set it to false
   };
   ```
   `Tilemap.init` sets `.system_optimized = false`. Because `Game.loadLevel` rebuilds the
   tilemap via `Tilemap.initDefault()`, every level automatically starts un-optimized —
   no extra reset code needed (verify this).

2. **One shared signal helper** in `Tilemap` so every light element behaves consistently:
   ```zig
   /// Intensity 0..1 for light `index` of an element identified by `seed`.
   /// Un-optimized: time-quantized deterministic noise — each light flips
   /// independently every ~90 ms with no spatial or temporal pattern (chaos).
   /// Optimized: an ordered chase — lights march on one after another.
   fn lightSignal(self: *const Self, seed: i32, index: i32, speed: f32, phase: f32) f32 {
       if (!self.system_optimized) {
           const step: i32 = @intFromFloat(@floor(self.background_time / 0.09));
           return self.hashFloat(seed * 31 + index * 57 + step * 101);
       }
       const wave = @sin(self.background_time * speed - @as(f32, @floatFromInt(index)) * 0.9 + phase);
       return wave * 0.5 + 0.5;
   }
   ```
   Notes: reuses the existing `hashFloat`; needs no mutable state, so it stays callable
   from `*const` render paths. Tune the 0.09 s step and 0.9 index stride during Phase 6
   playtesting, but keep chaos flicker in the 60–120 ms range (faster reads as shimmer,
   slower reads as blinking).

3. **Apply it to every light element** (threshold ~`>= 0.5` for on/off elements, use the
   raw value for glow alphas). Pass a per-element `seed` derived from its screen position
   (e.g., `x * 13 + y * 7`) so no two elements flicker identically:
   - `drawBoardModule` LED loop (~501): replaces the `@sin(...) > 0.0` on/off test —
     covers the **I/O**, **RAM** (motherboard) and **GPU** (cooling bay) card LEDs.
   - `drawLightStrip` (~553): replaces the `@sin(...) > -0.1` test — cooling-bay strips.
   - `drawProcessorSocket` cell glow (~540): drives `glow_alpha` — covers **CHIPSET**,
     CPU, GPU sockets. In chaos mode also let each cell's alpha jump discretely
     (`70 + signal * 150`) instead of breathing smoothly.
   - `drawDataBus` (~414): drive each packet's `glow`/alpha from `lightSignal`; in chaos
     mode additionally offset each packet's x by a hash-based jitter of ±6 px so bus
     traffic looks scrambled; when optimized, packets glide exactly as today.
   - `drawRamStick` (~666): same treatment for its LED elements (silicon-ascent theme).
   - `renderCoreChamberBackground` energy beams (~330): drive `beam_alpha` from
     `lightSignal` (chaos = strobing beams, optimized = slow synchronized breathing).

4. **Temporary debug toggle** in `game.zig` `update` (next to the F12 block, same style):
   ```zig
   // DEBUG: F11 toggles system optimization to preview light states. Removed in Phase 4.
   if (rl.isKeyPressed(.f11)) self.tilemap.system_optimized = !self.tilemap.system_optimized;
   ```

**Acceptance:**
- Every level starts with all background lights (module LEDs, socket cells, strips, bus
  packets, RAM sticks, beams) flickering randomly — clearly "broken", no visible rhythm.
- Pressing F11 flips all of them to a clean ordered chase; pressing again restores chaos.
- Both states animate at full frame rate; no per-frame allocation, no RNG state added.
- All four themes show the contrast (visit each level via normal play or temporarily
  bumping the starting level — restore before commit).
- Game remains completable exactly as before (gating untouched).

---

### Phase 2 — Server Room door: JSON schema, world rendering, entry detection

**Objective:** Author a door in level JSON, render it in the world near the middle of the
level, and detect "player at door + submit" — which for now just toggles the debug flag
path (actual room comes in Phase 3).

**Files:** `src/tilemap.zig` (schema + `LevelData`), `src/game.zig` (apply, render, detect)

**Docs to verify first:** `std.json.parseFromSlice` optional-field defaults in the Zig
0.13.0 std docs (pattern: give the field a default value in the struct, exactly like
`moving_platforms: []const JsonMovingPlatform = &.{}` at ~line 749).

**Changes:**

1. **JSON schema** — optional `server_door` key:
   ```json
   "server_door": { "x": 56, "y": 30 }
   ```
   `x`,`y` = tile coordinates of the door's **top-left**; the door occupies 1 tile wide ×
   2 tiles tall (16×32 px) and its base must rest on a solid platform tile row (`y + 2` is
   the platform row).
   ```zig
   const JsonPoint = struct { x: i32, y: i32 }; // reuse if an equivalent already exists
   // In JsonLevelSchema:
   server_door: ?JsonPoint = null,
   // In LevelData:
   server_door_x: i32,
   server_door_y: i32,
   has_server_door: bool,
   ```
   Populate in `loadLevelFromJson`. Levels without the key get `has_server_door = false`.

2. **`Game` fields + apply:**
   ```zig
   server_door_pos: ?struct { x: i32, y: i32 },
   ```
   Reset to `null` in `loadLevel`; set from `level_data` in `applyLevelData` when
   `has_server_door`. **Defensive rule:** if a level has **no** door (old JSON, or the
   hardcoded `createLevel1` fallback), set `self.tilemap.system_optimized = true` at load
   so the level stays completable — a missing door must never soft-lock the game.

3. **Render the door** (world-space, in `render` right after `renderTerminal`; model the
   fn on `renderTerminal` ~line 959): a 16×32 px doorway — dark frame, recessed panel,
   tiny `SRV` label, and a small indicator light top-center that **blinks urgently
   (chaos-style, reuse `tilemap.system_optimized` check)** until the script has been run,
   then glows steady green. Keep it flat-shaded rectangles + `drawText`, consistent with
   the terminal's look.

4. **Proximity hint + entry detection** in `updatePlaying` (copy the terminal-overlap
   pattern at ~line 624): when the player AABB overlaps the door rect and the system is
   not yet optimized, draw a screen-space hint *"Press {prompt} to enter the Server Room"*
   (reuse the `renderTerminalHint` box style; suppress it once optimized). On
   `input.submit_pressed` while overlapping: for this phase, log-free no-op or directly
   set `system_optimized = true` behind a `// TODO(Phase 3)` — the real transition
   replaces it next phase.

**Acceptance:**
- Old JSONs (no `server_door`) still parse; levels without a door auto-set
  `system_optimized = true` and play exactly as before this feature.
- With a temporary `server_door` added to `level1.json` (use `{ "x": 56, "y": 30 }`), the
  door renders standing on the platform, indicator blinking chaotically.
- Standing at the door shows the enter hint; the hint disappears after optimization.
- `zig build` clean; Levels 2–4 unaffected.

---

### Phase 3 — The Server Room scene (per-level variants, terminal, optimizing script)

**Objective:** Entering the door switches to a single-screen Server Room. PM walks
left/right, runs `optimize.sh` at the room terminal (scrolling script output), the system
becomes optimized, and PM returns to the level exactly where he left it.

**Files:** new `src/serverroom.zig`; `src/game.zig` (state, wiring); `src/config.zig`
(constants); check `src/touch.zig` for exhaustive `GameState` switches.

**Docs to verify first:**
- `rl.drawTexturePro` signature in the raylib-zig binding source (already used in
  `game.zig` ~line 770 — copy that pattern for drawing PM's sprite in the room).
- Zig 0.13.0 langref on tagged-enum `switch` (room script state machine).

**Changes:**

1. **New state:** add `server_room` to `GameState`. Fix every exhaustive switch the
   compiler flags (at minimum `Game.update`, `Game.render`, and `touch.render`'s handling
   if it switches on state — treat the room like `playing` for touch controls so
   left/right/jump buttons keep working on web).

2. **`src/serverroom.zig`** — self-contained module, fixed-capacity, no allocation,
   styled after the other managers:
   ```zig
   pub const ScriptState = enum { idle, running, done };

   pub const ServerRoom = struct {
       variant: u8,        // = current_level (0..3), selects palette + decor
       pm_x: f32,          // PM's x in room space; y is fixed on the floor
       facing_right: bool,
       script_state: ScriptState,
       script_timer: f32,
       lines_shown: usize,

       pub fn enter(variant: u8) ServerRoom { ... } // PM starts at the left door
       pub fn update(self: *Self, dt: f32, input: controls.FrameInput) RoomEvent { ... }
       pub fn render(self: *const Self, player_texture: ?rl.Texture2D, time: f32) void { ... }
   };

   pub const RoomEvent = enum { none, script_finished, exit_requested };
   ```
   - **Layout (all variants share it):** screen-space 800×600, no camera. Floor line at
     y ≈ 500; door zone at the left edge (x < 90); terminal desk + monitor at the right
     (x ≈ 620–760); 2–3 server racks along the back wall between them.
   - **Movement:** `input.move_x` moves PM at `config.ROOM_WALK_SPEED` (new const,
     ≈ 160 px/s), clamped to `[40, 740]`; flip `facing_right` with direction. No jumping,
     no gravity, no hazards. Draw PM with the existing `player_texture` idle frame via
     `drawTexturePro` (flip the source rect width sign to mirror, same trick as any
     existing sprite-flip in `player.zig` — check and copy it).
   - **Terminal interaction:** when PM is within the terminal zone and
     `input.submit_pressed` and `script_state == .idle` → `.running`. While running,
     reveal one script line every `config.SCRIPT_LINE_INTERVAL` (0.45 s) from a fixed
     list, e.g.:
     ```
     $ ./optimize.sh
     Scanning system state.......... DEGRADED
     Defragmenting memory pages..... OK
     Reindexing interrupt table..... OK
     Rebalancing thread scheduler... OK
     Flushing corrupted caches...... OK
     Patching LED bus drivers....... OK
     Verifying system integrity..... PASS
     OPTIMIZATION COMPLETE
     ```
     After the last line, `script_state = .done` and return `.script_finished` **once**.
     Render the lines in a dark monitor rect with terminal-green text (`drawText`, size
     ~12, matching `credit_body` green `{0,255,128}`); show a blinking `_` cursor while
     running.
   - **Exit:** PM in the door zone + `submit_pressed` → return `.exit_requested`. Allowed
     at any time (a player may enter, leave, and come back later). Show a small "Press
     {prompt} to exit" hint while in the door zone, and after the script completes show
     *"System updated! Return to the level"*.
   - **Variants** — one palette + one signature decor per level, everything else shared:

     | variant | Level theme | Wall/floor palette | Signature decor |
     |---------|-------------|--------------------|-----------------|
     | 0 | Motherboard | dark teal walls, green accents | 3 racks with vertical LED columns + a hanging cable bundle |
     | 1 | Cooling Bay | steel blue walls, cyan accents | 2 racks + two wall-mounted cooling fans (reuse spinning-fan math from `drawCoolingFan` as a local copy or shared helper) |
     | 2 | Core Chamber | deep maroon walls, orange accents | 2 racks + two glowing energy-conduit columns |
     | 3 | Silicon Ascent | slate/violet walls, ice-blue accents | racks + an antenna/relay mast with a blinking beacon |

     Rack LEDs follow the same rule as the world: chaotic flicker while `script_state !=
     .done`, ordered chase after — reinforcing the fix *inside* the room the moment it
     happens. (Room has its own tiny copy of the signal logic or takes a `chaos: bool`;
     don't reach into `Tilemap` from here.)

3. **`game.zig` wiring:**
   - Fields: `server_room: ?serverroom.ServerRoom = null` (active room, null when not in
     one).
   - Entry (replaces the Phase 2 TODO): on door overlap + submit while not optimized →
     `self.server_room = ServerRoom.enter(self.current_level); self.state = .server_room;`
     The player's world position, camera, bugs, sparks, and platforms are **not** touched
     — the world freezes (its `updatePlaying` simply doesn't run) and resumes intact.
   - `update` arm:
     ```zig
     .server_room => {
         if (self.server_room) |*room| {
             switch (room.update(dt, input)) {
                 .script_finished => {
                     self.tilemap.system_optimized = true;
                     self.player.score += config.OPTIMIZE_BONUS; // new const, 500
                     audio SFX optional — only if an existing suitable SFX exists; do not add assets
                 },
                 .exit_requested => { self.server_room = null; self.state = .playing; },
                 .none => {},
             }
         } else self.state = .playing; // defensive
     },
     ```
   - `render` arm (early, like `.credits`): clear to the room's wall color and call
     `room.render(self.player_texture, <animation time>)`; then `touch.render(self.state)`
     so web touch buttons stay usable.
   - **Pause is disabled inside the room** (ignore `pause_pressed`; the scene is seconds
     long and `updatePaused` resumes to `.playing`, which would eject the player from the
     room). Level music keeps playing (music `update` already runs for all states).
   - Re-entering after optimization: door overlap hint is suppressed (Phase 2) and entry
     is refused once `system_optimized` — the room is a one-shot per level.

**Acceptance:**
- Entering the door mid-level switches to the room; the level is exactly as left upon
  return (player position, camera, remaining bugs, score, timer-free).
- Running the script shows the line-by-line output, flips the room's own rack LEDs to
  ordered, awards +500, and — back in the level — all background lights now run the
  ordered chase. Door indicator is steady green.
- Exiting without running the script leaves the system chaotic; the door still works.
- Each of the four variants is visibly distinct (verify all four).
- Pause is inert inside the room; touch controls work in the room on the web build.
- The F11 debug toggle still exists (removed next phase); `zig build` clean.

---

### Phase 4 — Dual-objective gating, adaptive hints, HUD status

**Objective:** The PR terminal requires **both** objectives; hints always point at the
remaining task; the HUD shows both task states; remove the F11 debug toggle.

**Files:** `src/game.zig`, `src/config.zig` (colors if needed)

**Changes:**

1. **Gate the terminal** (~line 623): replace `if (self.all_bugs_defeated)` with
   `if (self.all_bugs_defeated and self.tilemap.system_optimized)` around the
   overlap/submit → victory block. Same change for `renderTerminal`'s green-screen
   condition (~line 969) and the `>` cursor.

2. **Three-way hint** (replaces the `all_bugs_defeated`-only call at ~line 833). Extract
   the existing box-drawing into a small helper taking the string, then:
   - bugs ✓, system ✗ → `"Bugs squashed! Update the system in the Server Room"`
   - system ✓, bugs ✗ → `"System updated! Squash the remaining bugs"`
   - both ✓ → `"All tasks complete! Submit your PR at the terminal — press {prompt}"`
   - neither → no hint (unchanged early-game silence).

3. **HUD task checklist**: in `render`'s screen-space section (after
   `player.renderHUD`), draw two compact status items under the existing HUD, e.g.
   `BUGS [✓/3 left]  SYS [OK/ERR]` — green when done, HUD color otherwise. Keep it to two
   short `drawText` calls + `bugs.getActiveCount()`; no icons/textures. (ASCII only —
   raylib's default font has no ✓ glyph; use `OK` / `--`.)

4. **Remove the F11 debug toggle** from Phase 1.

**Acceptance:**
- Squashing all bugs first: terminal stays dim, hint directs to the Server Room; after
  the script, hint switches to "submit your PR", terminal activates.
- Running the script first: hint says squash remaining bugs; terminal activates only
  after the last stomp.
- Victory/level-advance/final-victory flow unchanged once submitted.
- HUD shows both states correctly through both orderings; F11 no longer does anything.

---

### Phase 5 — Author `server_door` in all four level JSONs

**Objective:** Place a door near the middle of every level on a safe, reachable platform.

**Files:** `assets/data/level1.json` … `level4.json` (and remove any temporary Phase 2
test entry).

Suggested placements (door is 1×2 tiles; `y` = door top, base row = `y + 2` must be the
platform row; all four sit on existing spark-free platforms near the level midpoint —
**verify in-game and nudge if the door overlaps a bug patrol or decoration**):

| Level | Platform (from JSON) | `server_door` |
|-------|----------------------|---------------|
| 1 — Circuit Board Alpha (100×37) | `x1:52, x2:60, y:32` | `{ "x": 56, "y": 30 }` |
| 2 — Danger Streets (110×37) | `x1:51, x2:60, y:22` | `{ "x": 55, "y": 20 }` |
| 3 — Lone Fighter (120×37) | `x1:58, x2:66, y:31` | `{ "x": 62, "y": 29 }` |
| 4 — Silicon Ascent (60×150, vertical) | `x1:12, x2:22, y:66` (≈ mid-climb) | `{ "x": 17, "y": 64 }` |

Also add a line to each JSON's `meta` block documenting the key, mirroring the existing
`meta` style, e.g. `"server_door": "1x2-tile Server Room door; top-left tile coords; base must rest on a platform"`.

**Acceptance:**
- All four levels load with a door near their midpoint (Level 4: mid-*height*), reachable
  with normal jumps, not overlapping bug patrols, sparks, moving-platform paths, or the
  PR terminal.
- Full playthrough of each level requires the Server Room visit; no level is completable
  without it, and none is soft-locked.

---

### Phase 6 — Integration testing & polish

**Objective:** Validate end-to-end on native and web; tune the chaos/order contrast.

**Checklist:**
- Full playthrough Levels 1→4 doing **bugs-first** on two levels and **script-first** on
  the other two; every ordering completes; score (incl. +500 bonuses) and lives persist.
- Chaos flicker reads as clearly broken and the optimized chase as clearly fixed in all
  four themes; tune `lightSignal` step/stride if any theme reads mushy.
- Server Room: enter/leave/re-enter before running the script; PM position/camera/bugs
  identical on return; all four room variants render correctly; pause inert inside.
- Door edge cases: dying after optimizing keeps `system_optimized` for that level until
  game-over (level reload via `loadLevel` resets it — confirm that a *game-over restart*
  and a *level advance* both reset to chaos, but an in-level respawn does not).
- Fallback levels (temporarily rename a JSON): level loads, auto-optimized, completable.
- Web build compiles and plays: door entry via touch (jump-tap = submit), room touch
  movement, no `GameState` switch missed
  (`zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast --sysroot "C:\Users\HP\emsdk\upstream\emscripten" run-web`).
- `zig build` clean; no allocations added to update/render paths; F11/F12 debug audit
  (F12 credits preview stays, F11 gone).

---

## 6. Files Changed / Added (summary)

| File | Change |
|------|--------|
| `src/tilemap.zig` | `system_optimized` flag; `lightSignal` helper; chaos/order wiring in `drawBoardModule`, `drawLightStrip`, `drawProcessorSocket`, `drawDataBus`, `drawRamStick`, core-chamber beams; `server_door` JSON schema + `LevelData` fields. |
| `src/serverroom.zig` | **New** — `ServerRoom` scene (variants, movement, script state machine, render). |
| `src/game.zig` | `server_room` GameState + update/render arms; door field/apply/render/entry; dual-objective gating; three-way hint; HUD checklist; +500 bonus; temporary F11 (added Phase 1, removed Phase 4). |
| `src/config.zig` | `ROOM_WALK_SPEED`, `SCRIPT_LINE_INTERVAL`, `OPTIMIZE_BONUS` (and any new colors). |
| `src/touch.zig` | Only if it switches exhaustively on `GameState` — extend for `server_room`. |
| `assets/data/level1..4.json` | Add `server_door` + `meta` note. |

---

## 7. Out of Scope

- New art, sprite, music, or SFX assets (room and door are drawn with primitives; PM
  reuses the existing texture; no new audio files).
- Saving optimization state across sessions; mid-level checkpoints.
- Bugs, hazards, or combat inside the Server Room.
- More than one Server Room per level, or randomized room contents.
- Changes to the `background.zig` opening/credits backdrop (its chip LEDs are not part of
  the in-level system state).
- Localizing hint text; accessibility options for flicker (see risk below — mitigated by
  intensity tuning, not an options menu).

---

## 8. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| A level without a door (old JSON / fallback path) becomes uncompletable. | Defensive rule in Phase 2: no door ⇒ `system_optimized = true` at load. |
| New `GameState` breaks exhaustive switches elsewhere (touch, future code). | Compiler surfaces them; §3 rule 5 forbids silencing with `else`. |
| Chaos flicker is unpleasant / seizure-adjacent at high contrast. | Flicker period ≥ 60 ms, alpha-range (not full black↔white) transitions, per-element desync; review in Phase 6 on both native and web. |
| Pausing in the room ejects the player into `.playing`. | Pause disabled inside the room (Phase 3). |
| Touch players can't enter the door (no dedicated submit button). | Jump-tap already maps to `submit_pressed` (existing terminal behavior); door reuses it. |
| Door placement collides with bug patrols or moving platforms after tuning. | Phase 5 placements chosen on spark-free static platforms; in-game verification required by acceptance. |
| Zig/raylib API drift (agent writes post-0.13 or wrong-signature code). | §3 pinned docs + prefer-precedent rule; every phase gates on a clean `zig build`. |
