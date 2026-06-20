const std = @import("std");
const rlz = @import("raylib_zig"); // exposes rlz.emcc (Emscripten helpers)

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Web builds need Emscripten's sysroot (passed via --sysroot). The
    // raylib_zig dependency dereferences b.sysroot while configuring its own
    // emscripten examples, so a missing --sysroot otherwise panics deep inside
    // the dependency with an opaque "attempt to use null value". Fail early here
    // with an actionable message instead. See README "Web / Browser Build".
    if (target.result.os.tag == .emscripten and b.sysroot == null) {
        @panic(
            "Web build requires --sysroot. Re-run as ONE line (no backtick continuation):\n" ++
                "  zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast " ++
                "--sysroot \"C:\\Users\\HP\\emsdk\\upstream\\emscripten\" run-web\n",
        );
    }

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Web target: compile the same source to wasm32-emscripten and link with
    // emcc. Build-system only — no game-code changes. Isolated in this branch so
    // the native path below is untouched (see PM_BrowserGameplay.md, Phase 1).
    if (target.result.os.tag == .emscripten) {
        const exe_lib = rlz.emcc.compileForEmscripten(
            b,
            "programmer_man",
            "src/main.zig",
            target,
            optimize,
        ) catch @panic("emcc compileForEmscripten failed");
        exe_lib.root_module.addImport("raylib", raylib);
        // raylib isn't baked into exe_lib's output, so emcc links it too.
        exe_lib.linkLibrary(raylib_artifact);

        const link = rlz.emcc.linkWithEmscripten(
            b,
            &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact },
        ) catch @panic("emcc linkWithEmscripten failed");

        // Package the whole assets/ tree as an async sidecar mounted at /assets
        // so runtime std.fs reads (e.g. levelN.json) resolve unchanged.
        link.addArg("--preload-file");
        link.addArg("assets@/assets");

        // Emscripten 3.1.50 defaults to a 64 KB stack and a fixed heap with no
        // growth. The Game struct embeds a ~32 KB tilemap (200x160 TileType
        // array) plus the bug/spark/platform managers, and Game.init() builds
        // it and returns it by value up through main (Tilemap.initDefault()
        // also returns a 32 KB struct by value). That overflows the 64 KB
        // stack during init and traps as "memory access out of bounds" right
        // after the SFX load. Native stacks (~8 MB) hide this. Give the web
        // build a generous stack and let the heap grow.
        link.addArg("-sSTACK_SIZE=4MB");
        // CRITICAL: the WASM heap must NEVER grow during a session. A growth
        // event replaces the underlying ArrayBuffer, which detaches every cached
        // typed-array view and crashes two subsystems for the rest of the run:
        //   1. miniaudio ScriptProcessorNode: captures HEAPF32 at setup; after a
        //      buffer swap every onaudioprocess throws "detached ArrayBuffer" —
        //      audio is permanently dead.
        //   2. ASYNCIFY doRewind: _emscripten_memcpy_js closes over HEAPU8 from
        //      module-load time; a swap makes copyWithin throw on the next rewind.
        // The previous config set a big INITIAL_MEMORY but left ALLOW_MEMORY_GROWTH=1
        // (with a 2 GB ceiling). That only RAISED the growth threshold — it didn't
        // remove it. A late allocation (the 5-track LoadMusicStream sequence + the
        // state transition on Enter) still pushed past 256 MB, fired grow(), and
        // hit both bugs above.  Pinning the heap to a fixed size makes grow()
        // impossible, so the buffer address is stable for the whole session.
        //
        // 512 MB fixed covers stack (4 MB) + MEMFS preloaded assets (~26 MB) +
        // all music streams resident in RAM + textures (~6 MB) + game heap +
        // ASYNCIFY stack, with headroom. If the build ever aborts with OOM, the
        // real culprit is an allocation that keeps growing (suspect: music streams
        // reloaded on transitions without UnloadMusicStream) — fix that leak
        // rather than just raising this number.
        link.addArg("-sINITIAL_MEMORY=536870912");
        link.addArg("-sALLOW_MEMORY_GROWTH=0");
        // Pre-allocate a generous ASYNCIFY save-stack so it never calls realloc
        // and triggers a secondary sbrk/memory.grow mid-session.  The playing
        // state's render path (tilemap + mode2D + HUD) is much deeper than the
        // opening screen and easily exceeds the 4096-byte default.
        link.addArg("-sASYNCIFY_STACK_SIZE=65536");

        // Custom presentation shell (Phase 5): centered responsive canvas, a
        // loading/progress bar wired to Module.setStatus/monitorRunDependencies,
        // a click-to-start gesture surface (also unlocks WebAudio, see Phase 4),
        // and page chrome (title + controls legend). Replaces emcc's bare
        // default index.html. emcc substitutes {{{ SCRIPT }}} with its loader.
        link.addArg("--shell-file");
        link.addArg(b.pathFromRoot("web/shell.html"));

        b.getInstallStep().dependOn(&link.step);

        const run = rlz.emcc.emscriptenRunStep(b) catch @panic("emcc emscriptenRunStep failed");
        run.step.dependOn(&link.step);
        b.step("run-web", "Build & serve the web build via emrun")
            .dependOn(&run.step);
        return; // skip native-only test_exe / unit-test wiring for the web target
    }

    const exe = b.addExecutable(.{
        .name = "programmer_man",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);

    b.installArtifact(exe);

    // Test window executable
    const test_exe = b.addExecutable(.{
        .name = "test_window",
        .root_source_file = b.path("src/test_window.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_exe.linkLibrary(raylib_artifact);
    test_exe.root_module.addImport("raylib", raylib);
    b.installArtifact(test_exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Programmer_Man");
    run_step.dependOn(&run_cmd.step);

    // Test window run command
    const test_run_cmd = b.addRunArtifact(test_exe);
    test_run_cmd.step.dependOn(b.getInstallStep());
    const test_run_step = b.step("test-window", "Run raylib window test");
    test_run_step.dependOn(&test_run_cmd.step);

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkLibrary(raylib_artifact);
    unit_tests.root_module.addImport("raylib", raylib);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
