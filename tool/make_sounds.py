#!/usr/bin/env python3
"""Generates the monitor's tones into assets/sounds/.

Run from the project root:  python3 tool/make_sounds.py

  qrs_80.wav .. qrs_100.wav   pulse tone; pitch falls with SpO2
  alarm_high.wav              high priority  (burst of 3 + 2, twice)
  alarm_med.wav               medium priority (3 slower tones)
  alarm_low.wav               technical / low priority (2 soft tones)
  key.wav                     soft-key click
"""
import math
import os
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds')


def tone(freq, ms, attack=6, release=20, harmonics=(1.0, 0.35, 0.12), gain=0.6):
    n = int(RATE * ms / 1000)
    a, r = int(RATE * attack / 1000), int(RATE * release / 1000)
    out = []
    for i in range(n):
        env = min(1.0, i / max(a, 1), (n - i) / max(r, 1))
        v = sum(h * math.sin(2 * math.pi * freq * (k + 1) * i / RATE) for k, h in enumerate(harmonics))
        out.append(gain * env * v / sum(harmonics))
    return out


def gap(ms):
    return [0.0] * int(RATE * ms / 1000)


def save(name, samples):
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s)) * 32000)) for s in samples))


def main():
    os.makedirs(OUT, exist_ok=True)

    # Pulse tone: a quarter-tone lower for every percent of saturation lost.
    for spo2 in range(80, 101):
        f = 880 * 2 ** ((spo2 - 100) / 24)
        save(f'qrs_{spo2}.wav', tone(f, 70, attack=3, release=45, gain=0.55) + gap(20))

    hi = (1.0, 0.5, 0.3, 0.15)
    burst = []
    for _ in range(2):
        for i in range(3):
            burst += tone(988, 130, harmonics=hi, gain=0.7) + gap(90)
        burst += gap(220)
        for i in range(2):
            burst += tone(988, 130, harmonics=hi, gain=0.7) + gap(90)
        burst += gap(700)
    save('alarm_high.wav', burst)

    med = []
    for i in range(3):
        med += tone(740, 210, attack=15, release=40, harmonics=hi, gain=0.6) + gap(210)
    save('alarm_med.wav', med)

    low = tone(587, 260, attack=20, release=60, gain=0.45) + gap(180) + tone(494, 320, attack=20, release=80, gain=0.45)
    save('alarm_low.wav', low + gap(100))

    save('key.wav', tone(1400, 18, attack=1, release=12, harmonics=(1.0,), gain=0.35) + gap(20))


if __name__ == '__main__':
    main()
