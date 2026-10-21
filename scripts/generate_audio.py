#!/usr/bin/env python3
"""Compose original looping village and ruins themes, plus interface/weapon sounds.

Requires NumPy and ffmpeg to regenerate the checked-in OGG assets. Runtime playback
has no Python dependency. The melodies and synthesized sounds are original.
"""
from pathlib import Path
import math
import subprocess
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game/assets/audio"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
TEMPO = 96
BEAT = 60 / TEMPO
BAR = BEAT * 4
LENGTH = BAR * 8


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def tone(track, start, duration, note, voice, gain=1.0):
    begin = int(start * RATE)
    count = min(int(duration * RATE), len(track) - begin)
    if count <= 0:
        return
    t = np.arange(count, dtype=np.float64) / RATE
    freq = hz(note)
    if voice == "lute":
        sound = np.sin(math.tau * freq * t) + .43*np.sin(math.tau * freq * 2*t) + .13*np.sin(math.tau * freq * 3*t)
        envelope = np.minimum(1, t/.008) * np.exp(-3.2*t/max(.15, duration))
    elif voice == "flute":
        phase = math.tau * freq * t + .05*np.sin(math.tau*5.2*t)
        sound = np.sin(phase) + .13*np.sin(2*phase)
        envelope = np.minimum(1, t/.09) * np.minimum(1, (duration-t)/.17)
    elif voice == "bow":
        sound = np.sin(math.tau*freq*t) + .20*np.sin(math.tau*freq*2*t)
        envelope = np.minimum(1, t/.19) * np.minimum(1, (duration-t)/.24)
    elif voice == "drum":
        phase = math.tau * (freq*t + freq*0.009*(1-np.exp(-t*35)))
        sound = np.sin(phase)
        envelope = np.exp(-t*18)
    else:
        sound = np.sin(math.tau*freq*t)
        envelope = np.exp(-t*24)
    track[begin:begin+count] += (sound*envelope*gain).astype(np.float32)


def save_ogg(name, track):
    # A short room reflection glues the instruments together without source samples.
    mix = track.copy()
    for delay, strength in [(.105, .13), (.22, .08), (.37, .04)]:
        offset = int(delay*RATE)
        mix[offset:] += track[:-offset] * strength
    fade = min(int(.15*RATE), len(mix)//4)
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)
    peak = max(.01, float(np.max(np.abs(mix))))
    mix = np.clip(mix * (.78/peak), -1, 1)
    wav_path = OUT / (name + ".wav")
    with wave.open(str(wav_path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((mix*32767).astype("<i2").tobytes())
    if name in ("village", "ruins"):
        subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i",
                        str(wav_path), "-c:a", "libvorbis", "-q:a", "5", str(OUT/(name+".ogg"))], check=True)
        wav_path.unlink()
    print("AUDIO_EXPORT", name)


village = np.zeros(int(LENGTH*RATE), dtype=np.float32)
progression = [(50, 53, 57), (46, 50, 53), (53, 57, 60), (48, 52, 55)]
melody = [69, 72, 74, 72, 69, 67, 65, 67, 69, 65, 64, 62, 65, 67, 69, 65]
for bar in range(8):
    chord = progression[bar%4]
    base = bar*BAR
    tone(village, base, BAR*.93, chord[0]-12, "bow", .18)
    for eighth in range(8):
        note = chord[[0,1,2,1,0,1,2,1][eighth]]
        tone(village, base+eighth*BEAT/2, BEAT*.48, note+12, "lute", .19)
    for phrase in range(2):
        note = melody[(bar*2+phrase)%len(melody)]
        tone(village, base+phrase*BEAT*2, BEAT*1.85, note, "flute", .12)
save_ogg("village", village)

ruins = np.zeros(int(LENGTH*RATE), dtype=np.float32)
for bar in range(8):
    base = bar*BAR
    for beat in range(4):
        tone(ruins, base+beat*BEAT, .24, 38 if beat in (0,2) else 45, "drum", .24)
    for eighth in range(8):
        tone(ruins, base+eighth*BEAT/2, BEAT*.45,
             [50, 50, 53, 49, 50, 50, 57, 53][eighth], "lute", .14)
    tone(ruins, base, BAR*.9, 38 if bar%2==0 else 41, "bow", .2)
    tone(ruins, base+BEAT*2, BEAT*1.8, [62, 65, 60, 58][bar%4], "flute", .10)
save_ogg("ruins", ruins)

for name, note, length, voice in [("ui", 81, .19, "bell"), ("swing", 55, .23, "drum"),
                                  ("gather", 74, .28, "lute"), ("step", 34, .15, "drum")]:
    sound = np.zeros(int(length*RATE), dtype=np.float32)
    tone(sound, 0, length, note, voice, .7)
    save_ogg(name, sound)
