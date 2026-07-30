#!/usr/bin/env python3
"""Generates the board's move and capture sounds into App/Resources/Sounds.

These are synthesized rather than fetched because the app is GPLv3 and every
other bundled asset (cburnett pieces, the opening book) carries a license we
had to check. Sound generated here has no third-party provenance to track.

The model is a wooden piece meeting a wooden board: a short noise burst
shaped by a few resonant modes, decaying fast. A capture is the same knock
preceded by the scrape of the taken piece being swept off, which is what
makes the two audibly different without needing a different instrument.

Run: python3 scripts/generate-sounds.py
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100
OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "App",
    "Resources",
    "Sounds",
)


def resonant_knock(duration, modes, decay, seed, noise_level=1.0):
    """A noise burst rung through fixed resonant modes.

    `modes` are (frequency_hz, amplitude, decay_multiplier) triples: the few
    frequencies a small wooden object actually rings at when struck.
    """
    random.seed(seed)
    frame_count = int(SAMPLE_RATE * duration)
    samples = [0.0] * frame_count

    for frequency, amplitude, decay_multiplier in modes:
        phase = random.uniform(0, 2 * math.pi)
        mode_decay = decay * decay_multiplier
        for index in range(frame_count):
            t = index / SAMPLE_RATE
            envelope = math.exp(-t / mode_decay)
            samples[index] += amplitude * envelope * math.sin(2 * math.pi * frequency * t + phase)

    # The initial transient - the click of contact before the body rings.
    transient_frames = int(SAMPLE_RATE * 0.004)
    for index in range(min(transient_frames, frame_count)):
        envelope = 1.0 - index / transient_frames
        samples[index] += noise_level * 0.5 * envelope * random.uniform(-1, 1)

    return samples


def mix(base, overlay, offset_seconds):
    """Adds `overlay` into `base` starting at `offset_seconds`."""
    offset = int(SAMPLE_RATE * offset_seconds)
    result = list(base)
    if len(result) < offset + len(overlay):
        result.extend([0.0] * (offset + len(overlay) - len(result)))
    for index, value in enumerate(overlay):
        result[offset + index] += value
    return result


def scrape(duration, seed):
    """Filtered noise, for the taken piece sliding off the square."""
    random.seed(seed)
    frame_count = int(SAMPLE_RATE * duration)
    samples = []
    previous = 0.0
    for index in range(frame_count):
        t = index / SAMPLE_RATE
        envelope = math.exp(-t / (duration * 0.35)) * (t / duration) ** 0.3
        # One-pole lowpass turns white noise into something woodier.
        previous = previous * 0.72 + random.uniform(-1, 1) * 0.28
        samples.append(previous * envelope * 0.55)
    return samples


def normalize(samples, peak):
    loudest = max(abs(value) for value in samples) or 1.0
    return [value / loudest * peak for value in samples]


def fade_out(samples, seconds=0.008):
    """Prevents the click a hard cut at the end would otherwise produce."""
    frames = int(SAMPLE_RATE * seconds)
    for index in range(min(frames, len(samples))):
        samples[len(samples) - 1 - index] *= index / frames
    return samples


def write_wav(path, samples):
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, value)) * 32767)) for value in samples
        )
        handle.writeframes(frames)
    print(f"wrote {path} ({len(samples) / SAMPLE_RATE * 1000:.0f}ms)")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # A move: one dry knock, low and short enough to disappear behind the
    # next thing the user does.
    move = resonant_knock(
        duration=0.13,
        modes=[(196.0, 1.0, 1.0), (392.0, 0.45, 0.6), (734.0, 0.22, 0.35), (1180.0, 0.1, 0.2)],
        decay=0.028,
        seed=7,
    )
    move = fade_out(normalize(move, 0.62))

    # A capture: the scrape of the taken piece, then the knock of the taker
    # landing. Slightly brighter and a touch louder, so it reads as the more
    # consequential of the two without being startling.
    capture = scrape(0.055, seed=11)
    capture = mix(
        capture,
        resonant_knock(
            duration=0.15,
            modes=[(174.0, 1.0, 1.0), (349.0, 0.5, 0.6), (696.0, 0.3, 0.35), (1420.0, 0.16, 0.18)],
            decay=0.032,
            seed=13,
            noise_level=1.3,
        ),
        offset_seconds=0.042,
    )
    capture = fade_out(normalize(capture, 0.78))

    write_wav(os.path.join(OUTPUT_DIR, "move.wav"), move)
    write_wav(os.path.join(OUTPUT_DIR, "capture.wav"), capture)


if __name__ == "__main__":
    main()
