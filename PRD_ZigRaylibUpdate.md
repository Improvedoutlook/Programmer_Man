# PRD: Toolchain Upgrade — Zig 0.16.0 + raylib 6.0

**Status:** Deferred (captured for future implementation — not urgent)
**Author:** Investigation by Claude (Opus 4.8), reviewed by Mark Owens
**Date:** 2026-07-18

---

## 1. Overview

This document captures the findings of an investigation into upgrading
**Programmer_Man** from its current toolchain (Zig **0.13.0**, raylib-zig
**v5.5** / raylib 5.5) to Zig **0.16.0**. It exists so the work can be picked
up later with the analysis already done.

**Key conclusion:** This is not a Zig-only upgrade. Because `raylib-zig`'s
0.16-compatible line is tied to **raylib 6.0**, upgrading Zig necessarily bumps
raylib as well (and, very likely, Emscripten for the web build). Plan for a
**coupled Zig 0.13→0.16 + raylib 5.5→6.0** upgrade.

## 2. Motivation

- Stay current with the Zig toolchain and language.
- Gain raylib 6.0 features and fixes.
- Reduce future migration debt (the longer we stay on 0.13.0, the larger the
  eventual jump).

**Non-motivation:** There is no functional problem forcing this. The game
builds and runs on 0.13.0 today (native and web). This upgrade is
opportunistic, not corrective — hence "deferred."

## 3. Current State (baseline)

| Component | Current pin |
|---|---|
| Zig compiler | 0.13.0 (`C:\tools\zig-windows-x86_64-0.13.0\`) |
| `build.zig.zon` `minimum_zig_version` | `0.13.0` |
| `raylib_zig` dependency | tag `v5.5` (raylib 5.5) |
| Emscripten (web build) | 3.1.50 (`C:\Users\HP\emsdk\...`) |

## 4. Findings

### 4.1 raylib-zig has 0.16 support — but coupled to raylib 6.0
- Upstream `raylib-zig` (default `devel` branch) is documented as
  **"tested on raylib version 6.0 and Zig 0.16.0"**, with recent commits
  tracking Zig 0.15.1 → 0.16.0.
- There is **no** path to "Zig 0.16 with raylib 5.5". Taking Zig 0.16 means
  taking raylib 6.0 via raylib-zig.
- Repoint the dependency to the 0.16/raylib-6.0 release (its `devel` branch or
  the corresponding tag) using `zig fetch --save`, which computes the new
  (0.14+) hash format automatically.

### 4.2 Game source is low-risk for the *language* migration
A scan of `src/` (13 files, ~5,200 LOC) came back clean on the three changes
that most commonly break a Zig migration:

| Risk pattern | Why it hurts | Count in `src/` |
|---|---|---|
| `std.ArrayList` | Became unmanaged in 0.15 (`init`/`append` signatures changed) | **0** |
| `usingnamespace` | Removed in 0.15 | **0** |
| custom `pub fn format()` | Format API churned across 0.14–0.16 | **0** |

The main hands-on surface is the **77 distinct `rl.*` raylib call sites**,
which is a raylib-6.0 concern, not a Zig-language one.

> Note: the scan did not exhaustively check `std.io` ("Writergate", 0.15) or
> `std.json` usage (level loading). These are expected to be minor but should
> be confirmed during implementation.

## 5. Level of Effort

**Overall: Medium — roughly 1–2 focused days**, with variance skewed toward the
toolchain (raylib 6.0 + Emscripten), not the Zig language.

| Piece | Effort | Risk |
|---|---|---|
| Install Zig 0.16.0 | Trivial | — |
| `build.zig.zon`: bump min version, add `.fingerprint`, repoint dep via `zig fetch --save` | Low | Low |
| `build.zig`: migrate to 0.16 module API (`root_module = b.createModule(...)`), re-verify install-file/`InstallDir` APIs | Low–Med | Mechanical |
| raylib-zig emcc helper drift (`compileForEmscripten` / `linkWithEmscripten` / `emscriptenRunStep` signatures) | Med | **Med** |
| raylib **5.5 → 6.0** API changes across 77 call sites | Med | **Med** — bulk of hands-on fixing |
| Language/std migration in game code | Low | Low (per §4.2 scan) |
| Re-verify native + web builds | Med | — |

## 6. Risk Analysis

1. **raylib 6.0 API churn (Med).** Major-version bump; expect a compile-error
   triage pass across the 77 raylib call sites (renamed functions, changed
   signatures).
2. **Emscripten bump (highest hidden risk).** raylib 6.0 / raylib-zig `devel`
   likely expects a newer emsdk than the pinned **3.1.50**. The web build has
   carefully tuned settings that were dialed in *specifically* for 3.1.50:
   - `-sINITIAL_MEMORY=536870912`, `-sALLOW_MEMORY_GROWTH=0` (the
     "detached ArrayBuffer" / miniaudio + ASYNCIFY fix),
   - `-sSTACK_SIZE=4MB`, `-sASYNCIFY_STACK_SIZE=65536`.
   A toolchain bump can reopen the audio/heap stability work. **This is the
   item most likely to turn a 1-day job into a 3-day one.**
3. **build system API drift (Low–Med).** The 0.14/0.15 module split changed how
   artifacts are declared. Mechanical but touches every artifact definition.
   Verify the 0.16 build API against the **installed 0.16 std source**, not from
   memory (0.16 postdates the assistant's training cutoff).

## 7. Recommended Sequencing

Do it in two isolated phases so the risky web work can't block everything:

1. **Native first.** Get Zig 0.16 + raylib 6.0 compiling and running natively
   (`zig build run`). Resolve the language, build.zig, and raylib-6.0 API
   changes here where iteration is fast.
2. **Web second, separately.** Tackle the Emscripten/`emcc` path on its own so
   the audio/heap retuning is isolated. Re-validate the browser build against
   the memory/ASYNCIFY notes above.

## 8. Verification Checklist

- [ ] `zig build` (native) succeeds on 0.16.0.
- [ ] `zig build run` — game runs; movement, jump, stomp, HUD all correct.
- [ ] `zig build test` — unit tests pass.
- [ ] Web build (`.\web.ps1 -BuildOnly`) links without OOM/ASYNCIFY errors.
- [ ] Browser run: opening track plays (audio unlock), no "detached
      ArrayBuffer" crash, level transitions stable.
- [ ] Fullscreen work still intact (native Fullscreen path + `#fsdebug`).
- [ ] `build.zig.zon` fingerprint/hash valid; `zig fetch` reproducible.

## 9. Affected Files (anticipated)

- `build.zig.zon` — min version, fingerprint, dependency repoint.
- `build.zig` — module API migration; re-verify manifest/icon install steps.
- `src/*.zig` — raylib 6.0 call-site fixes (77 sites); spot std fixes.
- Web: possibly `web.ps1` / emsdk pin, and the emcc args in `build.zig`.

## 10. References

- **Zig canonical repo (as of 2025-11-26): <https://codeberg.org/ziglang/zig>.**
  Zig migrated off GitHub to Codeberg; the old `github.com/ziglang/zig` is now
  read-only ("Moved to Codeberg"). Consult Codeberg for Zig source, `std`, and
  issues.
- Zig downloads + release notes (unaffected by the move — still authoritative):
  <https://ziglang.org/download/> · <https://ziglang.org/news/0.16.0-released/>.
  Latest stable: **0.16.0 (released 2026-04-13)**, verified against
  ziglang.org/download.
- raylib-zig — **still on GitHub** (a separate third-party project, not affected
  by Zig's move): <https://github.com/raylib-zig/raylib-zig>. The
  `build.zig.zon` dependency URL therefore stays on github.com.
- Related internal notes: `docs/PM_BrowserGameplay.md` (web build phases),
  and project memory `web-wasm-toolchain` (Emscripten 3.1.50 setup).
