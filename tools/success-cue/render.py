#!/usr/bin/env python3
"""Render the Success cue's sound files from its chimes' note lists (ADR 0006).

Each chime is a note list in a JSON file that this script and the app both
read: this script turns its notes into sound, and the app turns the very same
notes into the haptic, so the two match by construction.

    python3 tools/success-cue/render.py

renders every chime the app ships, Grosh/Resources/Sounds/SuccessCue-*.json,
into NAME-income.caf and NAME-expense.caf beside it, where NAME is the note
list's file name without .json.

    python3 tools/success-cue/render.py NOTES.json ... [--out DIR] \
        [--format wav] [--format m4a] [--format caf]

renders the given note lists instead, into DIR (beside each note list if left
out), in each format given (.caf if none).

Either way it prints each ending's length, audible length, peak level and top
note, and whether the Income ending is higher and longer than the Expense one.

Note-list format
----------------

    {
      "name": "Marimba",
      "instrument": { ... },
      "endings": {
        "income":  [note, ...],
        "expense": [note, ...]
      }
    }

name is the chime's name as people see it. Each note in an ending:

    pitch     MIDI note number: 69 is A4 at 440 Hz, 84 is C6. The note's
              frequency is 440 * 2 ** ((pitch - 69) / 12).
    start     seconds from the start of the cue to the note's strike.
    loudness  the note's level, 0...1, linear.
    ring      seconds the note takes to fade out (to -60 dB).
    sparkle   optional, 0...1: how much shimmer rings above the note.

The instrument says how every note sounds; only this script reads it:

    attack    seconds from silence to the note's full level.
    partials  [{ratio, level, ring}]: sine tones at ratio times the note's
              frequency, at level times its loudness, each fading out over
              ring times the note's ring.
    glide     optional {semitones, time}: each note starts this many
              semitones off its pitch and slides onto it, with this time
              constant in seconds.
    sparkle   optional {partials: [{ratio, level}], shimmer, attack}: what a
              note's sparkle adds: partials that each beat shimmer times a
              second, swelling in over attack seconds and fading with the note.

The render is deterministic: nothing is random, so the same note list renders
the same files byte for byte. Both endings of a chime share one gain, which
puts the louder ending's peak at --peak dBFS, so they keep their relative level.
"""

import argparse
import json
import math
import struct
import subprocess
import wave
from pathlib import Path

import numpy as np

APP_SOUNDS = Path(__file__).resolve().parents[2] / "Grosh" / "Resources" / "Sounds"
SAMPLE_RATE = 48_000
ENDINGS = ("income", "expense")
FADE_OUT = 0.010  # seconds of fade at the very end, so the cut never clicks
SIXTY_DB = math.log(1000.0)  # exp(-SIXTY_DB) is -60 dB
AUDIBLE_DB = -40.0  # an ending is audible until it last reaches this, below its peak
NOTE_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")


def frequency(pitch):
    return 440.0 * 2.0 ** ((pitch - 69.0) / 12.0)


def note_name(pitch):
    return f"{NOTE_NAMES[round(pitch) % 12]}{round(pitch) // 12 - 1}"


def swell(t, seconds):
    """Rises from 0 to 1 over the given seconds along a raised cosine."""
    if seconds <= 0:
        return np.ones_like(t)
    return np.where(t < seconds, 0.5 - 0.5 * np.cos(np.pi * t / seconds), 1.0)


def fade(t, seconds):
    """Falls from 1 to -60 dB over the given seconds."""
    return np.exp(-t * SIXTY_DB / seconds)


def render_note(note, instrument):
    ring = note["ring"]
    t = np.arange(math.ceil(ring * SAMPLE_RATE)) / SAMPLE_RATE
    pitch = frequency(note["pitch"])

    glide = instrument.get("glide")
    if glide and glide["semitones"]:
        bend = 2.0 ** (glide["semitones"] * np.exp(-t / glide["time"]) / 12.0)
        widest = max(1.0, 2.0 ** (glide["semitones"] / 12.0))
    else:
        bend = None
        widest = 1.0

    def tone(hz):
        if hz * widest >= SAMPLE_RATE / 2:
            return np.zeros_like(t)
        if bend is None:
            return np.sin(2.0 * np.pi * hz * t)
        step = 2.0 * np.pi * hz * bend / SAMPLE_RATE
        return np.sin(np.concatenate(([0.0], np.cumsum(step[:-1]))))

    sound = np.zeros_like(t)
    for partial in instrument["partials"]:
        sound += partial["level"] * fade(t, ring * partial["ring"]) * tone(pitch * partial["ratio"])

    sparkle = note.get("sparkle", 0.0)
    shimmer = instrument.get("sparkle")
    if sparkle and shimmer:
        beat = shimmer["shimmer"] / 2.0
        envelope = sparkle * swell(t, shimmer["attack"]) * fade(t, ring)
        for partial in shimmer["partials"]:
            hz = pitch * partial["ratio"]
            pair = 0.5 * (tone(hz - beat) + tone(hz + beat))
            sound += partial["level"] * envelope * pair

    return note["loudness"] * swell(t, instrument["attack"]) * sound


def render_ending(notes, instrument):
    parts = [(round(note["start"] * SAMPLE_RATE), render_note(note, instrument)) for note in notes]
    mix = np.zeros(max(offset + len(sound) for offset, sound in parts))
    for offset, sound in parts:
        mix[offset:offset + len(sound)] += sound
    tail = min(len(mix), round(FADE_OUT * SAMPLE_RATE))
    mix[len(mix) - tail:] *= np.linspace(1.0, 0.0, tail)
    return mix


def render(chime, peak_db):
    """Both endings of a chime as 16-bit samples, sharing one gain."""
    mixes = {ending: render_ending(chime["endings"][ending], chime["instrument"]) for ending in ENDINGS}
    loudest = max(np.max(np.abs(mix)) for mix in mixes.values())
    gain = 10.0 ** (peak_db / 20.0) / loudest
    return {ending: np.round(mix * gain * 32767.0).astype(np.int16) for ending, mix in mixes.items()}


def write_wav(path, samples):
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(SAMPLE_RATE)
        file.writeframes(samples.astype("<i2").tobytes())


def write_caf(path, samples):
    """Core Audio Format holding 16-bit big-endian linear PCM, mono."""
    audio = samples.astype(">i2").tobytes()
    description = struct.pack(">d4sIIIII", SAMPLE_RATE, b"lpcm", 0, 2, 1, 1, 16)
    path.write_bytes(
        b"caff" + struct.pack(">HH", 1, 0)
        + b"desc" + struct.pack(">q", len(description)) + description
        + b"data" + struct.pack(">qI", 4 + len(audio), 0) + audio
    )


def write_m4a(path, samples):
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-f", "s16le", "-ar", str(SAMPLE_RATE), "-ac", "1", "-i", "-",
         "-c:a", "aac", "-b:a", "192k", "-map_metadata", "-1",
         "-fflags", "+bitexact", "-flags:a", "+bitexact", str(path)],
        input=samples.astype("<i2").tobytes(), check=True,
    )


WRITERS = {"wav": write_wav, "caf": write_caf, "m4a": write_m4a}


def describe(chime, samples):
    print(chime["name"])
    lengths = {}
    for ending in ENDINGS:
        sound = samples[ending]
        peak = int(np.max(np.abs(sound)))
        loud = np.nonzero(np.abs(sound) >= peak * 10.0 ** (AUDIBLE_DB / 20.0))[0]
        audible = (loud[-1] + 1) / SAMPLE_RATE
        top = max(note["pitch"] for note in chime["endings"][ending])
        lengths[ending] = (top, audible)
        print(f"  {ending:<8} {len(sound) / SAMPLE_RATE:.3f} s long, audible {audible:.3f} s, "
              f"peak {20.0 * math.log10(peak / 32767.0):+.1f} dBFS, top note {note_name(top)} ({top})")
    higher = lengths["income"][0] > lengths["expense"][0]
    longer = lengths["income"][1] > lengths["expense"][1]
    print(f"  income is {'higher' if higher else 'NOT higher'} and {'longer' if longer else 'NOT longer'} than expense")


def main():
    parser = argparse.ArgumentParser(description="Render the Success cue's sound files from its chimes' note lists.")
    parser.add_argument("notes", type=Path, nargs="*",
                        help="note-list JSON files (default: every chime the app ships, as .caf beside it)")
    parser.add_argument("--out", type=Path, help="folder to write the sound files into (default: beside each note list)")
    parser.add_argument("--format", action="append", choices=sorted(WRITERS), dest="formats",
                        help="file format to write; repeat for several (default: caf)")
    parser.add_argument("--peak", type=float, default=-1.0, help="peak level of the louder ending, in dBFS")
    args = parser.parse_args()

    for notes in args.notes or sorted(APP_SOUNDS.glob("SuccessCue-*.json")):
        chime = json.loads(notes.read_text())
        samples = render(chime, args.peak)
        out = args.out or notes.parent
        out.mkdir(parents=True, exist_ok=True)
        for extension in args.formats or ["caf"]:
            for ending in ENDINGS:
                WRITERS[extension](out / f"{notes.stem}-{ending}.{extension}", samples[ending])
        describe(chime, samples)


if __name__ == "__main__":
    main()
