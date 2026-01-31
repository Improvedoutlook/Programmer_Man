Programmer_Man — Instructions & Coding Guidelines
===============================================

Overview
-	Short description: Retro-style 2D platformer written in Zig using Raylib.
-	Primary layout: source lives under `src/`, assets and data under `assets/` and `data/`.

Project goals
-	Clear, maintainable code for a small retro platformer.
-	Prioritize correctness, performance, and readability.
-	Prefer simple, well-reasoned solutions over premature abstraction.

Technologies
-	Zig — language used for the project.
-	Raylib — rendering/audio/input library (bindings used in code).
-	Build: `zig build` and provided scripts in the repo root.

Core principles (apply consistently)
-	DRY: centralize repeated logic and constants (use `src/config.zig`).
-	Consistent names and conventions: align file and type names (e.g., `player.zig` -> `Player`).
-	Single Responsibility: keep modules focused (input, physics, entities, rendering, audio).
-	Prefer the simplest solution that works; avoid over-engineering.
-	Reasoned engineering: when solving problems, pick patterns an experienced game dev would use.

Coding standards & best practices for 2D platformers
-	Game loop separation: strictly separate update (physics, AI, state) from render.
-	Use a fixed-timestep update for deterministic physics; interpolate rendering if needed.
-	Tile collisions: prefer simple AABB tile-based collisions and resolve with minimal code.
-	Encapsulate movement and collision response into reusable helpers.
-	Keep magic numbers out of code: place tuning values in `src/config.zig`.
-	Comment intent, not line-by-line implementation details; choose expressive names.

Performance & safety
-	Measure before optimizing; optimize hotspots found via profiling or simple timers.
-	Minimize heap allocations in hot loops; use pre-allocated arrays (e.g., `MAX_BUGS`).
-	Batch rendering and reuse assets/textures when possible.
-	Validate external inputs (level files, assets) and fail gracefully on missing resources.
-	Limit global mutable state; prefer explicit ownership and small public APIs.

Design & problem-solving guidance
-	Decompose the game into clear subsystems that communicate via simple interfaces.
-	Start with the straightforward implementation, add observability (logs, debug view), then refactor.
-	Aim for deterministic gameplay logic; randomness is fine for visuals/effects.

Testing, debugging & tooling
-	Add unit tests for deterministic functions (math, collision helpers) where practical.
-	Include an in-game debug mode: show FPS, collision boxes, and entity counts.
-	Keep logs concise; use them to record critical failures and recoverable errors.

Extensibility
-	Keep data-driven systems for content (tilemaps, level JSON under `data/`).
-	Design component boundaries so new enemies or powerups can be added with minimal changes.

Where to find things
-	Configuration constants: src/config.zig
-	Main entry: src/main.zig
-	Game loop and systems: src/game.zig, src/player.zig, src/tilemap.zig

How to extend this document
-	Keep entries short and prescriptive; include a one-line rationale and (optionally) a small code example.
-	Append new rules rather than rewriting the file; include links to relevant source files.

Contact / notes
-	Reference README.md for high-level project info.

-- end
