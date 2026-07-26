#!/usr/bin/env python3
"""Derive the subdued walk row of assets/sprites/player.png from the run row.

The sheet ships four 200px rows of 166px frames. Row 3 (y=766) is the only
side-profile row and holds the run cycle in columns 2..5. Those poses are drawn
with a full sprint's arm reach and stride, which reads as goofy when the player
is only strolling, so this script appends a fifth row (y=1000) holding a walk
variant of the same four poses: same art, same columns, limbs pulled in toward
the body.

The transform is deliberately narrow. Within two horizontal bands -- the arm
band and the leg band -- every pixel outside the body core is resampled toward
the core edge by a fixed factor, so the head and torso are copied untouched and
only the swing of the limbs shrinks. Frames are then re-anchored on a shared
body axis, which removes the ~20px sideways drift the run frames accumulate
across the cycle (a wobble the run row still has; see PRD notes).

Run from the repo root:  python tools/make_walk_row.py
It is idempotent -- the walk row is always rebuilt from the pristine run row.
"""

import sys
from PIL import Image

SHEET = "assets/sprites/player.png"

FRAME_W = 166
FRAME_H = 200
RUN_ROW_Y = 766
WALK_ROW_Y = 1000
CYCLE_COLS = (2, 3, 4, 5)

# Vertical bands within a frame, measured from the run poses.
CHEST_BAND = (56, 74)     # narrowest part of the torso -- also the body axis
ARM_BAND = (76, 138)      # shoulders down to the swinging hands
LEG_BAND = (138, 200)     # hips down to the feet
HIP_BAND = (138, 150)     # pelvis, above the point where a stride splits the legs

# How much of the original limb swing survives. Each band keeps its own body
# core (chest for the arms, pelvis for the legs) so the torso is never pinched --
# only what protrudes past the silhouette gets pulled in.
ARM_KEEP = 0.40
LEG_KEEP = 0.55

ALPHA_MIN = 32


def opaque_span(px, y0, y1):
    """Horizontal extent of non-transparent pixels across a band of rows."""
    lo, hi = None, None
    for y in range(y0, y1):
        for x in range(FRAME_W):
            if px[x, y][3] > ALPHA_MIN:
                if lo is None or x < lo:
                    lo = x
                if hi is None or x > hi:
                    hi = x
    return lo, hi


def squeeze_band(src, dst, y0, y1, core_lo, core_hi, keep):
    """Copy rows [y0,y1) with everything outside the core pulled inward.

    Inside the core the copy is 1:1. Outside it, destination column `core+d`
    samples source column `core + d/keep`, i.e. a nearest-neighbour downsample
    of the limb that leaves no gaps because it only ever compresses.
    """
    for y in range(y0, y1):
        for x in range(FRAME_W):
            if core_lo <= x <= core_hi:
                sx = x
            elif x > core_hi:
                sx = core_hi + round((x - core_hi) / keep)
            else:
                sx = core_lo - round((core_lo - x) / keep)
            if 0 <= sx < FRAME_W:
                dst[x, y] = src[sx, y]


def make_walk_frame(frame, axis_target):
    px = frame.load()

    chest_lo, chest_hi = opaque_span(px, *CHEST_BAND)
    hip_lo, hip_hi = opaque_span(px, *HIP_BAND)
    axis = (chest_lo + chest_hi) / 2.0

    out = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    dst = out.load()

    # Head and torso: straight copy.
    for y in range(0, ARM_BAND[0]):
        for x in range(FRAME_W):
            dst[x, y] = px[x, y]

    squeeze_band(px, dst, ARM_BAND[0], ARM_BAND[1], chest_lo, chest_hi, ARM_KEEP)
    squeeze_band(px, dst, LEG_BAND[0], LEG_BAND[1], hip_lo, hip_hi, LEG_KEEP)

    # Re-anchor so every frame in the cycle shares one body axis.
    shift = round(axis_target - axis)
    if shift:
        anchored = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
        anchored.alpha_composite(out, (max(shift, 0), 0), (max(-shift, 0), 0))
        out = anchored
    return out


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    if sheet.width < FRAME_W * 6:
        sys.exit(f"unexpected sheet width {sheet.width}")

    run_frames = [
        sheet.crop((c * FRAME_W, RUN_ROW_Y, (c + 1) * FRAME_W, RUN_ROW_Y + FRAME_H))
        for c in CYCLE_COLS
    ]

    axes = []
    for f in run_frames:
        lo, hi = opaque_span(f.load(), *CHEST_BAND)
        axes.append((lo + hi) / 2.0)
    axis_target = sum(axes) / len(axes)

    out = Image.new("RGBA", (sheet.width, WALK_ROW_Y + FRAME_H), (0, 0, 0, 0))
    out.alpha_composite(sheet.crop((0, 0, sheet.width, min(sheet.height, WALK_ROW_Y))))

    for col, frame in zip(CYCLE_COLS, run_frames):
        walk = make_walk_frame(frame, axis_target)
        out.alpha_composite(walk, (col * FRAME_W, WALK_ROW_Y))

    out.save(SHEET)
    print(f"wrote {SHEET} ({out.width}x{out.height}); walk row at y={WALK_ROW_Y}")


if __name__ == "__main__":
    main()
