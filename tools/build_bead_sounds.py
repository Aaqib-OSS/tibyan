"""Renders the misbaha's bead sounds as small WAV files.

The same synthesis as the approved mockup (misbaha-preview/mockup.html,
`knock`): a few milliseconds of noise for the contact, three decaying
partials for the bead's own ring, and a faint rebound. Nothing is sampled
from a recording, so the files carry no third-party rights.

Usage: python3 build_bead_sounds.py <out_dir>
Writes <material>_<1..4>.wav (a count) and <material>_end_<1..2>.wav (the
imam crossing), 44.1 kHz mono 16-bit, for wood, amber, pearl, turquoise
and yusr. Runs are reproducible (fixed seeds).
"""
import math, random, struct, sys, wave
from pathlib import Path

SR = 44100
# (frequency Hz, gain, decay s) of each partial; the contact noise's band; the final low-pass.
SND = {
    'wood':      dict(m=[(1150, .5, .035), (2700, .3, .02), (4300, .14, .012)], bp=2400, lp=6000),
    'amber':     dict(m=[(2100, .42, .05), (3900, .3, .035), (6100, .14, .02)], bp=3600, lp=9000),
    'pearl':     dict(m=[(3300, .36, .09), (5900, .3, .06), (8700, .14, .04)], bp=5200, lp=12000),
    'turquoise': dict(m=[(2700, .4, .06), (5100, .3, .04), (7600, .14, .025)], bp=4400, lp=10500),
    'yusr':      dict(m=[(1600, .46, .04), (3300, .3, .025), (5200, .14, .015)], bp=2900, lp=7000),
}
# Detune and rebound gap of each variant (the mockup draws them at random).
VARIANTS = [(-.030, .031), (-.010, .036), (.012, .033), (.032, .040)]
END_VARIANTS = [(-.015, .034), (.018, .038)]
PEAK = .5  # every file is scaled to this peak, so the materials are equally loud


def biquad(x, b0, b1, b2, a0, a1, a2):
    y, x1, x2, y1, y2 = [], 0., 0., 0., 0.
    for v in x:
        o = (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y


def bandpass(x, f, q):
    w = 2 * math.pi * f / SR
    al = math.sin(w) / (2 * q)
    return biquad(x, al, 0, -al, 1 + al, -2 * math.cos(w), 1 - al)


def lowpass(x, f, q_db=1.0):
    w = 2 * math.pi * f / SR
    al = math.sin(w) / (2 * 10 ** (q_db / 20))
    c = math.cos(w)
    return biquad(x, (1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al)


def knock(buf, at, vol, snd, det, low, rng):
    """Adds one knock into buf, starting `at` seconds in."""
    n0 = int(at * SR)
    span = len(buf) - n0
    part = [0.] * span
    ln = math.ceil(SR * .004)
    noise = [(rng.random() * 2 - 1) * (1 - i / ln) for i in range(ln)] + [0.] * (span - ln)
    for i, v in enumerate(bandpass(noise, snd['bp'] * (.7 if low else 1), 1.2)):
        part[i] += v
    d = (1 + det) * (.72 if low else 1)
    for f, g, dec in snd['m']:
        dec *= 1.6 if low else 1
        for i in range(min(span, int(dec * SR))):
            t = i / SR
            part[i] += g * (.0001 / g) ** (t / dec) * math.sin(2 * math.pi * f * d * t)
    for i, v in enumerate(lowpass([p * vol * .34 for p in part], snd['lp'])):
        buf[n0 + i] += v


def render(name, det, gap, end, seed):
    snd, rng = SND[name], random.Random(seed)
    longest = max(dec for _, _, dec in snd['m']) * (1.6 if end else 1)
    total = (.11 if end else gap) + longest + .03
    buf = [0.] * int(total * SR)
    knock(buf, 0, 1, snd, det, end, rng)
    knock(buf, gap, .26, snd, det * .6, end, rng)
    if end:
        knock(buf, .11, .5, snd, -det, True, rng)
    peak = max(abs(v) for v in buf) or 1
    fade = int(.004 * SR)
    for i in range(fade):  # no click at the end of the file
        buf[-1 - i] *= i / fade
    return [v / peak * PEAK for v in buf]


def write(path, samples):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in samples))


def main():
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    for k, name in enumerate(SND):
        for i, (det, gap) in enumerate(VARIANTS, 1):
            write(out / f'{name}_{i}.wav', render(name, det, gap, False, 1000 * k + i))
        for i, (det, gap) in enumerate(END_VARIANTS, 1):
            write(out / f'{name}_end_{i}.wav', render(name, det, gap, True, 1000 * k + 50 + i))


if __name__ == '__main__':
    main()
