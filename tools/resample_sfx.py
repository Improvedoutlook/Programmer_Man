"""One-off: normalize SFX WAVs to the web audio device format — 44100 Hz, 2
channels (16-bit) — so miniaudio's data converter does a *format-only* pass
(s16 -> f32) on emscripten.

Why: raylib's LoadSound converts each sound to the device format (f32 / stereo /
44100). When BOTH a channel conversion (mono->stereo) AND a format conversion
(s16->f32) are required, miniaudio's `__channels_only` path divides by
`ma_get_bytes_per_frame(channelConverter.format, channelConverter.channelsOut)`,
which is 0 on the web build -> "divide by zero" wasm trap during Game.init.
Making the assets stereo + 44100 removes the channel/resample steps, routing to
the `__format_only` path (no division). Native is unaffected. Idempotent.
"""
import sys
import wave
import audioop

TARGET_RATE = 44100
TARGET_CHANNELS = 2
FILES = [
    "assets/audio/jump.wav",
    "assets/audio/pounce.wav",
    "assets/audio/stomp.wav",
]


def resample(path: str) -> None:
    with wave.open(path, "rb") as w:
        n_channels = w.getnchannels()
        sampwidth = w.getsampwidth()
        rate = w.getframerate()
        frames = w.readframes(w.getnframes())

    if rate == TARGET_RATE and n_channels == TARGET_CHANNELS:
        print(f"SKIP {path}: already {TARGET_RATE} Hz / {TARGET_CHANNELS} ch")
        return

    out = frames
    if rate != TARGET_RATE:
        out, _ = audioop.ratecv(out, sampwidth, n_channels, rate, TARGET_RATE, None)
    if n_channels == 1 and TARGET_CHANNELS == 2:
        out = audioop.tostereo(out, sampwidth, 1, 1)  # duplicate mono -> L/R

    with wave.open(path, "wb") as w:
        w.setnchannels(TARGET_CHANNELS)
        w.setsampwidth(sampwidth)
        w.setframerate(TARGET_RATE)
        w.writeframes(out)

    print(
        f"OK   {path}: {rate} Hz/{n_channels}ch -> "
        f"{TARGET_RATE} Hz/{TARGET_CHANNELS}ch ({sampwidth*8} bit)"
    )


def main() -> int:
    for f in FILES:
        resample(f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
