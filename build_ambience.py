"""build_ambience.py - DEEPFALL Phase 13 looping cave ambience.

Three seamless 16 s loops (22.05 kHz mono) mixed live by fx.gd, which
lowers the drone's pitch and raises the rumble as the player descends:
  amb_drone.wav   low drone pad (all partials complete whole cycles in
                  16 s, so the loop point is click-free) + soft air noise
  amb_drips.wav   water drips with cave echoes (wrapped modulo the loop)
  amb_rumble.wav  distant rumbles: low noise swells + sub tone
Run:  python3 build_ambience.py
"""
import math
import os
import random
import struct
import wave

SR = 22050
LOOP = 16
N = SR * LOOP
OUT = os.path.join(os.path.dirname(__file__), "assets", "sfx")
random.seed(42)


def write(name, s, gain):
    peak = max(1e-6, max(abs(v) for v in s))
    with wave.open(os.path.join(OUT, name + ".wav"), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(v / peak * gain * 32000)) for v in s))


def lowpass_noise(n, bright):
    out = [0.0] * n
    v = 0.0
    for i in range(n):
        v += (random.uniform(-1, 1) - v) * bright
        out[i] = v
    return out


def loop_noise(bright):
    # generate 1 s extra and crossfade the tail into the head
    x = lowpass_noise(N + SR, bright)
    out = x[:N]
    for i in range(SR):
        k = i / SR
        out[i] = out[i] * k + x[N + i] * (1 - k)
    return out


def drone():
    parts = [(55.0, 1.0), (82.5, 0.55), (110.0, 0.35), (65.5, 0.4), (164.75, 0.12)]
    air = loop_noise(0.02)
    s = []
    for i in range(N):
        t = i / SR
        lfo = 0.75 + 0.25 * math.sin(2 * math.pi * t / LOOP)
        lfo2 = 0.6 + 0.4 * math.sin(2 * math.pi * 2 * t / LOOP + 1.0)
        v = 0.0
        for k, (f, a) in enumerate(parts):
            v += a * math.sin(2 * math.pi * f * t) * (lfo if k % 2 == 0 else lfo2)
        s.append(v + air[i] * 1.5)
    return s


def drips():
    s = [0.0] * N
    t = 0.4
    while t < LOOP - 0.2:
        f0 = random.uniform(700, 1300)
        amp = random.uniform(0.4, 1.0)
        for echo, (delay, g) in enumerate([(0.0, 1.0), (0.17, 0.35), (0.39, 0.16), (0.7, 0.07)]):
            start = int((t + delay) * SR)
            for j in range(int(0.09 * SR)):
                tt = j / SR
                f = f0 * (1 + 2.5 * tt / 0.09)
                v = math.sin(2 * math.pi * f * tt) * math.exp(-tt * 55) * amp * g
                s[(start + j) % N] += v
        t += random.uniform(0.6, 2.4)
    return s


def rumble():
    base = loop_noise(0.006)
    s = [0.0] * N
    swells = [(3.0, 1.6, 1.0), (9.5, 2.2, 0.8), (13.6, 1.2, 0.55)]
    for i in range(N):
        t = i / SR
        env = 0.08
        for (c, w, a) in swells:
            for off in (-LOOP, 0, LOOP):
                d = (t - c - off) / w
                env += a * math.exp(-d * d)
        sub = math.sin(2 * math.pi * 40.0 * t) * 0.4
        s[i] = (base[i] * 6.0 + sub) * env
    return s


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("amb_drone", drone(), 0.6)
    write("amb_drips", drips(), 0.7)
    write("amb_rumble", rumble(), 0.9)
    print("ambience written")
