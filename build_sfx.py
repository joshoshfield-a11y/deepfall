"""build_sfx.py - DEEPFALL Phase 12 procedural sound effects.

Small retro SFX synthesised from noise / square / sine voices with
pitch sweeps and envelopes (no external tools). 22.05 kHz 16-bit mono.
Output: assets/sfx/<name>.wav     Run:  python3 build_sfx.py
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "assets", "sfx")
random.seed(7)


def env(t, dur, attack=0.005, curve=2.0):
    if t < attack:
        return t / attack
    return max(0.0, 1.0 - (t - attack) / max(1e-4, dur - attack)) ** curve


def synth(dur, fn):
    n = int(SR * dur)
    return [fn(i / SR, dur) for i in range(n)]


class Noise:
    """Low-passed noise (one-pole) with adjustable brightness."""

    def __init__(self):
        self.v = 0.0

    def __call__(self, bright):
        self.v += (random.uniform(-1, 1) - self.v) * bright
        return self.v


def write(name, samples, gain=0.8):
    peak = max(1e-6, max(abs(s) for s in samples))
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s / peak * gain)) * 32000)) for s in samples))


def sq(phase):
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def main():
    nz = Noise()
    # swoosh: band noise with rising-then-falling brightness
    write("swing", synth(0.16, lambda t, d: nz(0.05 + 0.5 * math.sin(math.pi * t / d)) * env(t, d, 0.03, 1.5)), 0.55)
    # pickaxe on rock: sharp click + short noisy thunk
    write("mine_hit", synth(0.12, lambda t, d: (nz(0.7) * env(t, d, 0.001, 4) + 0.6 * math.sin(2 * math.pi * 520 * t) * env(t, 0.05, 0.001, 3))), 0.7)
    # block break: crumbly noise burst falling in brightness
    write("mine_break", synth(0.3, lambda t, d: nz(0.6 * (1 - t / d) + 0.05) * env(t, d, 0.002, 1.6)), 0.8)
    # melee impact on flesh: low thump + noise
    write("hit", synth(0.14, lambda t, d: (math.sin(2 * math.pi * (160 - 500 * t) * t) * env(t, d, 0.001, 2) + 0.5 * nz(0.4) * env(t, 0.06, 0.001, 2))), 0.85)
    # player hurt: falling square blip
    write("hurt", synth(0.22, lambda t, d: sq((420 - 900 * t) * t) * 0.5 * env(t, d, 0.003, 1.2)), 0.6)
    # jump: rising square chirp
    write("jump", synth(0.12, lambda t, d: sq((300 + 1400 * t) * t) * 0.4 * env(t, d, 0.003, 1.5)), 0.45)
    # land: soft low noise thud
    write("land", synth(0.1, lambda t, d: nz(0.12) * env(t, d, 0.002, 2.5)), 0.6)
    # dash: whoosh, brighter and longer than swing
    write("dash", synth(0.22, lambda t, d: nz(0.1 + 0.6 * (t / d)) * env(t, d, 0.01, 1.4)), 0.6)
    # slam: deep boom + rumble
    write("slam", synth(0.5, lambda t, d: (math.sin(2 * math.pi * (90 - 80 * t) * t) * env(t, d, 0.002, 1.5) + 0.6 * nz(0.15) * env(t, d, 0.002, 2))), 0.95)
    # pickup: two-note sine sparkle
    write("pickup", synth(0.18, lambda t, d: math.sin(2 * math.pi * (880 if t < 0.07 else 1320) * t) * 0.5 * env(t, d, 0.003, 1.3)), 0.45)
    # wooden prop break: woody knock + splinter noise
    write("prop_break", synth(0.28, lambda t, d: (0.7 * math.sin(2 * math.pi * 230 * t) * env(t, 0.08, 0.001, 2) + nz(0.45) * env(t, d, 0.002, 1.8))), 0.8)
    # enemy death: falling square + noise puff
    write("enemy_die", synth(0.35, lambda t, d: (0.5 * sq((260 - 500 * t) * t) * env(t, d, 0.003, 1.4) + 0.4 * nz(0.3) * env(t, d, 0.002, 2))), 0.7)
    print("sfx written to", OUT)


if __name__ == "__main__":
    main()
