# Product Requirements Document (PRD)

## Feature: Browser Gameplay — Compile Programmer_Man to WebAssembly

### Project: Programmer_Man

> **Filename note:** Created as requested as `PM_BroswerGamply.md`. Rename to
> `PM_BrowserGameplay.md` at your discretion — nothing references this file by name.

---

## 1. Overview

Programmer_Man is a Zig + raylib 2D platformer that currently builds a native
desktop executable (`zig build run`). This feature adds a **second build target**
— `wasm32-emscripten` — so the *same source tree* compiles to WebAssembly and runs
in a browser via an HTML/JS shell, with no gameplay code forked.

The headline technical fact that shapes this entire plan:

> **raylib-zig v5.5 (the version this project already pins) ships a complete
> Emscripten build path in `emcc.zig`**, exposing `compileForEmscripten`,
> `linkWithEmscripten`, and `emscriptenRunStep`. Its linker step enables
> **`-sASYNCIFY`**, which means the existing blocking main loop
> (`while (!rl.windowShouldClose())` in `src/main.zig`) **runs in the browser
> unchanged**. We are wiring up an existing capability, not porting an engine.

### What changes
- `build.zig` gains a `wasm32-emscripten` branch (build-system only).
- A handful of **portability fixes** in game code (case-sensitive asset paths,
  audio-unlock-on-gesture, a couple of platform guards).
- A **web deliverable**: custom HTML shell, canvas, loading bar, hosting layout.

### What does NOT change
- Game logic, physics, rendering, level format, scoring, enemies, camera.
- The native desktop build and `zig build run` workflow.
- The data-driven level system (`assets/data/levelN.json` parsed by `tilemap.zig`).

---

## 2. Goals

- **One codebase, two targets.** `zig build run` (native) and
  `zig build -Dtarget=wasm32-emscripten ...` (web) from identical source.
- **Playable in a modern browser** (Chrome/Edge/Firefox/Safari) at the game's
  native feel: 60 fps, keyboard controls, audio, all four levels.
- **No regression** to the desktop build.
- **Expansion-safe.** Adding `level5.json`, new music, or new sprites must require
  *zero* changes to the web build wiring — just drop the asset in `assets/` and
  rebuild. (Section 9 hardens this.)
- **Self-hostable static output.** Final artifact is a folder of static files
  (`.html`, `.js`, `.wasm`, `.data`) that works on GitHub Pages, itch.io, or any
  static host.

### Non-goals (this PRD)
- Mobile/touch controls (noted as a future phase, not built here).
- Multiplayer, save-to-cloud, leaderboards.
- Rewriting the main loop to `emscripten_set_main_loop` (ASYNCIFY makes it
  optional; revisit only if profiling demands it — see Phase 6).

---

## 3. Technical Background (grounded in this repo)

### 3.1 Toolchain reality
| Component | Current state | Web requirement |
|-----------|---------------|-----------------|
| Zig | `minimum_zig_version = "0.13.0"` (`build.zig.zon`) | Same. The pinned `emcc.zig` uses `b.addStaticLibrary` / `std.builtin.Mode` — **0.13-era API**. Do **not** upgrade to Zig 0.14+ without also bumping raylib-zig; the devel `emcc.zig` uses the 0.14 `b.addLibrary` API and is incompatible with 0.13. |
| raylib-zig | `v5.5`, hash `122022ceb2a0…` (`build.zig.zon`) | Already supports Emscripten. No bump needed. |
| Emscripten SDK | Not installed | **New dependency.** Install `emsdk`, activate a version, pass its path to `zig build` via `--sysroot`. |

### 3.2 How raylib-zig wires Emscripten (verified in the pinned package)
From `raylib-zig/build.zig`:
```zig
pub const emcc = @import("emcc.zig");      // exposed to dependents
// ...
.emscripten, .wasi => { /* raylib is built for emscripten; emcc links it later */ }
```
From `raylib-zig/emcc.zig` `linkWithEmscripten`, the emcc flags it emits:
```
-sUSE_OFFSET_CONVERTER  -sFULL-ES3=1  -sUSE_GLFW=3  -sASYNCIFY  -O3  --emrun
```
Output lands in `zig-out/htmlout/index.html` (+ `.js`, `.wasm`, `.data`).

Because our `build.zig.zon` names the dependency `raylib_zig`, our `build.zig` can
reach the helper with `@import("raylib_zig").emcc`.

### 3.3 The main loop (why ASYNCIFY matters)
`src/main.zig` is a classic blocking loop:
```zig
while (!rl.windowShouldClose()) {
    const dt = rl.getFrameTime();
    game.update(dt);
    // render to texture, scale, draw
}
```
Browsers own the event loop and forbid blocking it. `-sASYNCIFY` rewrites the
Wasm so this loop yields to the browser each frame and resumes — so it **works
as-is**. Cost: larger `.wasm` and some overhead. Acceptable for v1; Phase 6 covers
an optional refactor if needed.

### 3.4 Asset loading inventory (what must reach the browser FS)
| Loader | Call site | Path used | Folder on disk | Web risk |
|--------|-----------|-----------|----------------|----------|
| Textures | `game.zig:188` | `assets/sprites/player.png` | **`assets/Sprites/`** | ⚠️ **Case mismatch — fails on web** |
| Textures | `game.zig:189` | `assets/Images/PM_OpeningImage.png` | `assets/Images/` | OK |
| Music | `audio.zig` (multiple) | `assets/music/*.mp3,*.ogg` | `assets/music/` | OK (size — see 3.6) |
| SFX | `audio.zig:35` | `assets/audio/*.wav` | `assets/audio/` | Verify case |
| Levels | `tilemap.zig:797` | `assets/data/levelN.json` via `std.fs.cwd().openFile` | `assets/data/` | OK once preloaded |
| Gamepad DB | `controls.zig:45` | `@embedFile("gamecontrollerdb.txt")` | compiled in | OK (compile-time) |

**std.fs works on the emscripten target** — Zig's emscripten libc backs
`std.fs.cwd().openFile` with Emscripten's MEMFS. Files made available via
`--preload-file assets@/assets` appear at the path `assets/...`, so
`tilemap.zig`'s runtime JSON reads keep working **without code changes**.

### 3.6 Asset size / packaging
`assets/music/` holds several MP3s plus a full OGG (multiple MB total). Two emcc
options:
- `--embed-file` — bakes bytes into the `.wasm`/`.js`. Simple, but bloats the
  module and blocks startup. Used by raylib-zig's *example* code.
- `--preload-file` — emits a separate `.data` sidecar fetched asynchronously with
  progress reporting. **Chosen** — better startup UX for a multi-MB audio payload.

### 3.5 Browser constraints to design around
- **Audio autoplay policy.** Browsers block audio until a user gesture. The game
  calls `rl.initAudioDevice()` and starts music at startup; on web, sound stays
  silent until the first click/keypress. Needs an explicit unlock (Phase 4).
- **Case-sensitive FS** (covered above).
- **`setTargetFPS` is ignored on web** — raylib drives frames via
  `requestAnimationFrame` (browser vsync). `getFrameTime()` still works; the
  existing `dt > 0.1` clamp in `main.zig` already guards tab-switch hitches. No
  change needed.
- **Canvas sizing.** The game renders to a fixed 800×600 render texture then
  scales to the window — this maps cleanly onto an HTML `<canvas>` (Phase 5).
- **Gamepad** on web is best-effort (Gamepad API); keyboard is the primary path.

---

## 4. Phase 0 — Toolchain & Baseline Validation ✅ COMPLETE (2026-06-14)

**Outcome:** Emscripten SDK `3.1.50` installed at `C:\Users\HP\emsdk` and activated.
The Zig 0.13.0 → raylib-zig v5.5 → Emscripten chain is validated on this machine: a
raylib `basic_window` sample compiled to `zig-out/htmlout/{index.html, index.js,
index.wasm}`. raylib compiled cleanly for `wasm32-emscripten` and emcc linked it with
the helper's flags (`-sUSE_OFFSET_CONVERTER -sFULL-ES3=1 -sUSE_GLFW=3 -sASYNCIFY -O3`).
Setup + working command pattern recorded in `README.md` → "Web / Browser Build".
Validation scaffold left at `C:\Users\HP\rlz_validate` (safe to delete).

**Goal:** Prove the existing repo can produce *any* running Wasm build before
touching game logic. De-risks everything downstream.

**Tasks**
1. Install and activate Emscripten SDK (pin a known-good version, e.g. a 3.1.x
   line known to work with Zig 0.13):
   ```
   git clone https://github.com/emscripten-core/emsdk
   cd emsdk && ./emsdk install latest && ./emsdk activate latest
   ```
   Note the sysroot path: `<emsdk>/upstream/emscripten`.
2. Confirm `emcc.bat`/`emrun.bat` are on PATH (the v5.5 helper calls
   `emcc.bat`/`emrun.bat` on Windows).
3. Build a raylib-zig **example** for web from the cached package to confirm the
   emsdk ↔ Zig ↔ raylib-zig chain works end-to-end in *this* environment, before
   blaming our own code.
4. Record the exact, working invocation (sysroot path, Zig version) in the README.

**Exit criteria:** A raylib-zig sample renders in a local browser via `emrun`.

---

## 5. Phase 1 — `build.zig` Web Target

**Goal:** Add a `wasm32-emscripten` branch to our `build.zig`. Build-system only;
no game-code edits.

**Approach** — mirror the verified raylib-zig example pattern, adapted to our
single executable. At the top of `build.zig`:
```zig
const rlz = @import("raylib_zig"); // exposes rlz.emcc
```
Inside `build`, after the existing `raylib` module / `raylib_artifact` are
resolved, branch on the target OS:
```zig
if (target.result.os.tag == .emscripten) {
    const exe_lib = try rlz.emcc.compileForEmscripten(
        b, "programmer_man", "src/main.zig", target, optimize);
    exe_lib.root_module.addImport("raylib", raylib);
    exe_lib.linkLibrary(raylib_artifact);

    const link = try rlz.emcc.linkWithEmscripten(
        b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact });

    // Package assets as an async sidecar mounted at /assets (Section 3.6).
    link.addArg("--preload-file");
    link.addArg("assets@/assets");
    // Phase 5 adds: link.addArg("--shell-file"); link.addArg("web/shell.html");

    b.getInstallStep().dependOn(&link.step);

    const run = try rlz.emcc.emscriptenRunStep(b);
    run.step.dependOn(&link.step);
    b.step("run-web", "Build & serve the web build via emrun")
        .dependOn(&run.step);
    return; // skip native-only test_exe / unit-test wiring for the web target
}
// ...existing native build continues unchanged...
```

**Notes / pitfalls**
- The native `test_window` exe and `addTest` steps must **not** be built for the
  emscripten target (raylib-zig builds tests as native). The early `return` above
  keeps the web branch clean.
- `compileForEmscripten` reads `b.sysroot`; it must be supplied via `--sysroot`
  on the command line (Phase 0).
- Keep all native behavior in the `else`/fall-through path byte-for-byte.

**Build command (document in README):**
```
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast \
  --sysroot "C:\emsdk\upstream\emscripten" run-web
```

**Exit criteria:** `zig build -Dtarget=wasm32-emscripten ...` produces
`zig-out/htmlout/index.html` and the wasm/js/data artifacts without errors.

---

## 6. Phase 2 — Asset Portability Fixes

**Goal:** Make every runtime asset path resolve on a **case-sensitive** FS, since
the preloaded `/assets` tree mirrors disk casing exactly.

**Tasks**
1. **Fix the player sprite path.** `game.zig:188` uses `assets/sprites/player.png`
   but the folder is `assets/Sprites/`. Pick ONE canonical casing and make code +
   disk agree. **Recommended:** normalize the *folder* to lowercase `assets/sprites/`
   (and update `.paths`/git), because lowercase asset dirs are the de-facto web
   convention and the rest of the tree (`audio`, `music`, `data`) is already
   lowercase. Then `assets/Images/` is the lone capitalized outlier — optionally
   lowercase it too and update `game.zig:189`.
2. **Audit remaining paths** in `audio.zig` (SFX + every `loadMusicStream` literal)
   against on-disk casing, including the space-containing filename
   `the_world_ stood_ still.mp3` (verify the literal matches byte-for-byte).
3. **Guarantee assets are in the preload set.** `build.zig.zon` `.paths` already
   includes `"assets"`; `--preload-file assets@/assets` packages the whole tree.
   Confirm no asset is loaded from outside `assets/`.

**Verification aid:** Build once on a case-sensitive check (or simply load each
asset on web and watch the console for `FS error` / `Failed to load` lines).

**Exit criteria:** On web, every texture, sound, music track, and level loads with
no filesystem errors in the browser console.

---

## 7. Phase 3 — Compile & Runtime Portability Guards

**Goal:** Resolve anything that compiles natively but breaks under
`wasm32-emscripten`.

**Tasks**
1. **Compile the Wasm target and triage.** Expect possible issues around:
   - `std.heap.page_allocator` in `tilemap.zig` — valid on wasm (memory grows),
     but confirm no native-only allocator assumptions.
   - Any direct OS calls, threads, or timers. (Grep for `std.time`, `Thread`,
     `std.process`.) The game appears single-threaded; confirm.
2. **Window flags.** `main.zig` sets `WINDOW_RESIZABLE` via a raw bitcast config
   flag. Confirm it's harmless on web (canvas resize is handled by the shell in
   Phase 5); guard with `if (builtin.target.os.tag != .emscripten)` if it
   misbehaves.
3. **Clean-exit code.** Native relies on `defer closeWindow()` after the loop. With
   ASYNCIFY the loop effectively never returns in the browser; ensure no logic
   *depends* on post-loop cleanup running on web. (Cosmetic only — the tab just
   closes.)

**Exit criteria:** Clean compile for `wasm32-emscripten`; the game boots to the
opening screen in-browser and the main loop runs.

---

## 8. Phase 4 — Audio Unlock (Browser Gesture)

**Goal:** Make music and SFX actually play, respecting autoplay policy.

**Background:** The first user gesture (click/keydown) unlocks the WebAudio
context. Until then `rl.initAudioDevice()` succeeds but output is muted.

**Tasks**
1. Add a one-time "audio armed" gate in the game: defer starting music until the
   first input event is observed (the title/opening screen already waits for a
   keypress to start — hook music start to that transition rather than to
   `Game.init`).
2. If music is started at `Game.init` today, move the first `playMusicStream`/
   track start to the first real input frame. Keep `updateMusicStream` in the loop.
3. Confirm SFX (`jump`, `pounce`, `stomp`) play after the first interaction.
4. Optional: a short "Click to start" overlay in the shell (Phase 5) doubles as
   the audio-unlock gesture.

**Exit criteria:** Music begins on/after the first interaction; SFX audible; no
console autoplay warnings blocking gameplay.

---

## 9. Phase 5 — Web Presentation Shell & Hosting

**Goal:** Replace emcc's bare default page with a polished, embeddable shell, and
define the publish layout.

**Tasks**
1. Create `web/shell.html` (custom emcc `--shell-file`): centered responsive
   `<canvas id="canvas">`, a loading/progress bar wired to Emscripten's
   `Module.setStatus`/`monitorRunDependencies`, a "Click to start" gesture
   surface (ties into Phase 4), and basic page chrome (title, controls legend,
   credits link).
2. Wire it in `build.zig` web branch:
   ```zig
   link.addArg("--shell-file");
   link.addArg("web/shell.html");
   ```
3. Canvas/scale behavior: the game already letterboxes a fixed 800×600 render
   texture, so the canvas can be a fixed logical size with CSS scaling; confirm
   crisp `point`/nearest filtering survives (it's set in `main.zig`).
4. **Publish layout.** Output is `zig-out/htmlout/{index.html, .js, .wasm, .data}`.
   Document deploying that folder to GitHub Pages / itch.io. Note `.data` and
   `.wasm` MIME types must be served correctly (GitHub Pages handles this; some
   hosts need `application/wasm`).
5. Add a `web/` README snippet: local test via `emrun zig-out/htmlout/index.html`
   or `python -m http.server` from that dir (don't open `file://` — fetch of
   `.data`/`.wasm` requires HTTP).

**Exit criteria:** A shareable URL/folder where the game loads with a progress bar
and plays full-screen-ish in a browser tab.

---

## 10. Phase 6 — Optimization & Hardening (optional / iterative)

**Goal:** Shrink/clean the build once it's playable. Do only what profiling
justifies.

**Candidate tasks**
- **Binary size:** `-Doptimize=ReleaseSmall` vs `ReleaseFast`; measure `.wasm`.
  Note the helper hardcodes `-O3` in `emcc.zig`; if size matters, a forked link
  step (or upstream override) may be needed.
- **ASYNCIFY cost:** if frame overhead or size is a problem, refactor `main.zig`
  into a `frame()` function registered via `emscripten_set_main_loop_arg`, behind
  `if (builtin.target.os.tag == .emscripten)`, keeping the native blocking loop in
  the `else`. This is the "proper" raylib web pattern; deferred because ASYNCIFY
  already works.
- **Audio payload:** transcode/normalize music to a single web-friendly codec
  (OGG Vorbis is well supported and smaller than the mixed MP3/OGG set) to cut the
  `.data` size.
- **Crisp scaling / DPI:** verify on high-DPI displays.

**Exit criteria:** Acceptable load time and size; documented numbers.

---

## 11. Expansion Safety — Adding Levels/Features After Web Ship

This is a stated requirement: **keep expanding the game after it's on the web.**
The architecture already favors this, and this PRD preserves it:

- **Levels are data, loaded at runtime.** `tilemap.zig:loadLevelFromJson` reads
  `assets/data/levelN.json` from the (virtual) FS. Because the web build preloads
  the entire `assets/` tree (`--preload-file assets@/assets`), **dropping a new
  `level5.json` into `assets/data/` and rebuilding automatically ships it to web —
  no build-wiring change.** Same for new music/sprites under `assets/`.

- **One known coupling to fix for true data-driven expansion:** level progression
  is currently **hardcoded** — `game.zig` switches on level number to pick
  `level2/3/4.json` (`game.zig:297,308,319`) and music track selection is a
  hardcoded `switch` (noted in `PRD_Level4.md` §3). Adding level 5 today means
  editing `game.zig`. **Recommended hardening (small, optional, can be its own
  task):** introduce a `levels` manifest (e.g. `assets/data/levels.json` listing
  ordered level files + their music key), and have `Game` iterate the manifest
  instead of a hardcoded switch. After that, **adding a level is pure data**:
  author `levelN.json`, add one manifest entry, rebuild. Works identically native
  and web.

- **Asset-path discipline going forward:** keep all asset folders **lowercase**
  and reference them with exact case, so future assets never hit the
  Phase-2 case-sensitivity trap on web.

- **CI idea (optional):** add a `zig build -Dtarget=wasm32-emscripten` step to
  catch web-breaking changes (e.g. a new native-only syscall, or a new
  miscased asset path) at PR time rather than at deploy time.

---

## 12. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Zig 0.13 ↔ emsdk version mismatch | Medium | Phase 0 pins & records a known-good emsdk version before any code work. |
| Case-sensitivity breaks asset loads silently | High (one bug already present) | Phase 2 audit + browser-console check; lowercase convention going forward. |
| Audio stays muted (autoplay policy) | High | Phase 4 gesture-gated audio start. |
| `.wasm`/`.data` too large / slow first load | Medium | `--preload-file` sidecar + Phase 6 audio transcode + size build. |
| ASYNCIFY overhead unacceptable | Low | Phase 6 optional `emscripten_set_main_loop` refactor (kept behind target guard). |
| Native build regresses from build.zig edits | Low | Web logic isolated in an `if (… == .emscripten) { … return; }` branch; native path untouched. |
| raylib-zig helper hardcodes `-O3`/flags | Low | Acceptable for v1; fork link step only if Phase 6 needs other flags. |

---

## 13. Definition of Done

- [ ] `zig build run` (native) still works, unchanged.
- [ ] `zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast --sysroot <emsdk> run-web`
      builds and launches the game in a browser.
- [ ] All four levels load and are completable in-browser.
- [ ] Player sprite, opening image, SFX, and music all load (no FS errors).
- [ ] Audio plays after first interaction.
- [ ] Custom shell with loading bar; output folder deployable to a static host.
- [ ] README documents the emsdk setup + exact web build command.
- [ ] (If done) levels manifest in place so a 5th level needs no `game.zig` edit.

---

## 14. Phase Summary

| Phase | Title | Scope | Touches game code? | Status |
|-------|-------|-------|--------------------|--------|
| 0 | Toolchain & baseline | Install emsdk, validate chain on a sample | No | ✅ Done |
| 1 | `build.zig` web target | Add `.emscripten` branch + `run-web` step | No (build only) | Next |
| 2 | Asset portability | Fix case-sensitive paths (player sprite!) | Paths only | — |
| 3 | Portability guards | Compile-clean for wasm; platform guards | Minor | — |
| 4 | Audio unlock | Gesture-gated audio start | Minor | — |
| 5 | Web shell & hosting | Custom HTML shell, deploy layout | No (web assets) | — |
| 6 | Optimize & harden | Size, ASYNCIFY, audio payload | Optional | — |
| — | Expansion safety | Levels manifest (recommended) | Optional refactor | — |
