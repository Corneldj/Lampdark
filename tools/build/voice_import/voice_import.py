#!/usr/bin/env python3
"""SND-13's voice import: recordings in, the exact files every system plays out.

    python3 tools/build/voice_import/voice_import.py placeholders   # espeak-ng sources -> build/voice_src
    python3 tools/build/voice_import/voice_import.py import         # build/voice_src -> client/audio, index
    python3 tools/build/voice_import/voice_import.py check [--decode]

Sources are 48 kHz mono WAV at <src>/<voice_id>/<line_id>.<form>.wav (the lampman under
<src>/lampman/). For each character line: trim silence to 20 ms each end, normalise to its band's
loudness target while limiting every 20 ms frame under SND-07's band cap, encode 20 ms Opus at
24 kbps into .lbv, then decode it back and measure, re-encoding until the decoded file is within
the tolerance. The lampman is normalised and written as dry Ogg Vorbis. The index
(data/voices/voice_index.json) records each file's frames, samples, duration, loudness, loudest
frame and SHA-256; the server reads only the index. `check` fails on any missing file, stray file
or index mismatch (and with --decode re-measures every file). Needs ffmpeg (libopus, libvorbis);
`placeholders` needs espeak-ng. Never touches a microphone or a player's voice.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lbv  # noqa: E402
import loudness  # noqa: E402

GAME = Path(__file__).resolve().parents[3]
TOOL = Path(__file__).resolve().parent
MANIFEST = GAME / "data" / "voices" / "manifest.json"
INDEX = GAME / "data" / "voices" / "voice_index.json"
VOICES_OUT = GAME / "client" / "audio" / "voices"
LAMPMAN_OUT = GAME / "client" / "audio" / "lampman"
SRC_DEFAULT = GAME / "build" / "voice_src"
RATE = 48000
CALLOUT_KINDS = ("warning", "order", "job")


def settings():
    return json.loads((TOOL / "settings.json").read_text())


def tuning(key):
    domain = key.split(".")[0]
    return json.loads((GAME / "data" / "tuning" / f"{domain}.json").read_text())["keys"][key]["value"]


def band_of(line, form):
    if form in ("whisper", "talk", "shout"):
        return form
    return line.get("band", "talk")


def band_cap(cfg, band):
    b = cfg["bands"][band]
    if "cap_dbfs" in b:
        return float(b["cap_dbfs"])
    return float(tuning(b["next_threshold_key"])) + float(tuning("voice.band_cap_headroom_db"))


def manifest():
    return json.loads(MANIFEST.read_text())


def character_files(m):
    """(voice_id, line, form) for every character file the manifest requires."""
    for v in m["voices"]:
        for line in m["lines"]:
            for form in line["forms"]:
                yield v["voice_id"], line, form


def lampman_files(m):
    for line in m["lampman"]["lines"]:
        for form in line["forms"]:
            yield line, form


# Audio I/O through ffmpeg ----------------------------------------------------------------------

def read_audio(path_or_bytes, fmt=None):
    args = ["ffmpeg", "-v", "error"]
    if fmt:
        args += ["-f", fmt]
    args += ["-i", "pipe:0" if isinstance(path_or_bytes, bytes) else str(path_or_bytes),
             "-ac", "1", "-ar", str(RATE), "-f", "f32le", "pipe:1"]
    data = path_or_bytes if isinstance(path_or_bytes, bytes) else None
    out = subprocess.run(args, input=data, capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).astype(np.float64)


def encode(x, codec_args, container):
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in.f32"
        dst = Path(tmp) / ("out." + container)
        src.write_bytes(np.asarray(x, dtype=np.float32).tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", str(src)]
                       + codec_args + [str(dst)], check=True, capture_output=True)
        return dst.read_bytes()


def encode_lbv(x, bitrate):
    ogg = encode(x, ["-c:a", "libopus", "-b:a", bitrate, "-frame_duration", "20", "-application", "voip"], "ogg")
    pre_skip, _granule, packets = lbv.packets_from_ogg(ogg)
    return lbv.write_lbv(pre_skip, len(x), packets)


def decode_lbv(data):
    return read_audio(lbv.ogg_from_lbv(data), "ogg")


# Processing ------------------------------------------------------------------------------------

def trim(x, margin_s=0.02, floor_db=45.0):
    """Cuts leading and trailing silence (10 ms frames more than floor_db under the loudest),
    keeping margin_s each side."""
    hop = RATE // 100
    n = max(1, len(x) // hop)
    rms = np.array([np.sqrt(np.mean(x[i * hop:(i + 1) * hop] ** 2) + 1e-20) for i in range(n)])
    db = 20 * np.log10(rms)
    loud = np.nonzero(db > db.max() - floor_db)[0]
    if len(loud) == 0:
        return x
    margin = int(margin_s * RATE)
    start = max(0, loud[0] * hop - margin)
    end = min(len(x), (loud[-1] + 1) * hop + margin)
    return x[start:end]


def limit(x, ceiling_dbfs):
    """Holds every 20 ms frame's RMS at or under ceiling_dbfs: a gain per frame (the least of it and
    its neighbours), interpolated between frame centres."""
    frame = lbv.FRAME_SAMPLES
    n = (len(x) + frame - 1) // frame
    padded = np.zeros(n * frame)
    padded[:len(x)] = x
    rms = np.sqrt(np.mean(padded.reshape(n, frame) ** 2, axis=1) + 1e-20)
    g = np.minimum(1.0, 10 ** ((ceiling_dbfs - 20 * np.log10(rms)) / 20))
    g = np.minimum(g, np.minimum(np.r_[g[1:], 1.0], np.r_[1.0, g[:-1]]))
    centres = np.arange(n) * frame + frame / 2
    gain = np.interp(np.arange(len(x)), centres, g)
    return x * np.minimum(gain, np.repeat(g, frame)[:len(x)])


def level(x, target, ceiling):
    """Normalises to `target` LUFS with every 20 ms frame held under `ceiling` dBFS."""
    for _ in range(40):
        x = x * 10 ** ((target - loudness.integrated_lufs(x)) / 20)
        x = limit(x, ceiling)
        if abs(loudness.integrated_lufs(x) - target) < 0.05:
            break
    return x


def import_character(job):
    voice_id, line, form, src, cfg = job
    x = trim(read_audio(src), cfg["trim_margin_s"], cfg["trim_floor_db"])
    band = band_of(line, form)
    target = cfg["bands"][band]["target_lufs"]
    cap = band_cap(cfg, band)
    # Level from the source each pass, correcting the aim and the ceiling by what the decoded
    # file measured. Opus is steep around a whisper's level, so the aim moves by half the error;
    # the closest pass within the tolerance is kept if none lands inside the aim.
    aim, ceiling = target, cap - cfg["cap_margin_db"]
    best = None
    for _ in range(12):
        data = encode_lbv(level(x, aim, ceiling), cfg["opus_bitrate"])
        y = decode_lbv(data)
        lufs = loudness.integrated_lufs(y)
        peak = float(loudness.frame_rms_dbfs(y).max())
        if peak <= cap - 0.1 and (best is None or abs(lufs - target) < abs(best[1] - target)):
            best = (data, lufs, peak)
        if abs(lufs - target) <= cfg["aim_lu"] and peak <= cap - 0.1:
            break
        aim += 0.5 * (target - lufs)
        if peak > cap - 0.1:
            ceiling -= peak - cap + 0.3
    if best is not None:
        data, lufs, peak = best
    if abs(lufs - target) > cfg["tolerance_lu"] or peak > cap:
        raise RuntimeError(f"{voice_id} {line['line_id']}.{form}: {lufs:.2f} LUFS (target {target}), loudest frame "
                           f"{peak:.2f} dBFS (cap {cap}); the recording needs work")
    out = VOICES_OUT / voice_id / f"{line['line_id']}.{form}.lbv"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    pre_skip, samples, packets = lbv.read_lbv(data)
    return voice_id, f"{line['line_id']}.{form}", {
        "frames": len(packets), "samples": samples, "duration_s": round(samples / RATE, 4), "band": band,
        "lufs": round(lufs, 2), "max_frame_rms_dbfs": round(peak, 2), "sha256": hashlib.sha256(data).hexdigest()}


def import_lampman(job):
    line, form, src, cfg = job
    x = trim(read_audio(src), cfg["trim_margin_s"], cfg["trim_floor_db"])
    target = cfg["lampman"]["target_lufs"]
    x = x * 10 ** ((target - loudness.integrated_lufs(x)) / 20)
    data = encode(x, ["-c:a", "libvorbis", "-q:a", str(cfg["lampman"]["vorbis_quality"])], "ogg")
    out = LAMPMAN_OUT / f"{line['line_id']}.{form}.ogg"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    return f"{line['line_id']}.{form}", {"duration_s": round(len(x) / RATE, 4), "sha256": hashlib.sha256(data).hexdigest()}


# Placeholders (espeak-ng) ----------------------------------------------------------------------

def spoken(cfg, line_id, form):
    p = cfg["placeholder"]
    if line_id.startswith("digit_"):
        word = p["digits"][int(line_id[6:])]
        # The continuing form rises (more to come); the final falls (Proposed placeholder intonation).
        return word + ("?" if form == "continuing" else ".")
    return p["spoken"][line_id]


def synth(job):
    params, text, form, dst, max_s = job
    variant = params["variant"]
    pitch, speed, amp = params["pitch"], params["speed"], 100
    if form == "whisper":
        variant = "whisperf" if params["variant"].startswith("f") else "whisper"
    elif form == "shout":
        pitch, speed, amp = min(99, pitch + 18), speed + 15, 200
    elif dst.stem.startswith("scream"):
        pitch, amp = 99, 200
    dst.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(6):
        with tempfile.TemporaryDirectory() as tmp:
            wav = Path(tmp) / "s.wav"
            subprocess.run(["espeak-ng", "-v", f"{params['lang']}+{variant}", "-p", str(pitch), "-s", str(speed),
                            "-a", str(amp), "-w", str(wav), text], check=True, capture_output=True)
            # Breathy placeholders (panting, the moan) lose their lows, as a close-miked breath would:
            # otherwise a low voice cannot reach the whisper target under the whisper cap.
            shape = ["-af", "highpass=f=500"] if dst.stem.split(".")[0] in ("panting", "moan") else []
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav)] + shape + ["-ac", "1", "-ar", str(RATE), str(dst)],
                           check=True, capture_output=True)
        if max_s <= 0 or len(trim(read_audio(dst))) / RATE <= max_s - 0.4:
            return str(dst)
        speed += 20
    raise RuntimeError(f"{dst}: still longer than {max_s} s")


def cmd_placeholders(args):
    cfg, m = settings(), manifest()
    src = Path(args.src)
    max_s = float(tuning("voice.callout_max_duration_s"))
    jobs = []
    for voice_id, line, form in character_files(m):
        if args.voice and voice_id != args.voice:
            continue
        params = cfg["placeholder"]["voices"][voice_id]
        limit_s = max_s if line["kind"] in CALLOUT_KINDS else 0
        jobs.append((params, spoken(cfg, line["line_id"], form), form, src / voice_id / f"{line['line_id']}.{form}.wav", limit_s))
    if not args.voice or args.voice == "lampman":
        for line, form in lampman_files(m):
            jobs.append((cfg["placeholder"]["lampman"], spoken(cfg, line["line_id"], form), form,
                         src / "lampman" / f"{line['line_id']}.{form}.wav", 0))
    src.mkdir(parents=True, exist_ok=True)
    (src / ".gdignore").write_text("")  # the sources are not game resources
    with ProcessPoolExecutor(args.jobs) as pool:
        done = list(pool.map(synth, jobs))
    print(f"placeholders: wrote {len(done)} sources under {src}")


def cmd_import(args):
    cfg, m = settings(), manifest()
    src = Path(args.src)
    index = json.loads(INDEX.read_text()) if INDEX.exists() else {}
    index.setdefault("voices", {})
    index.setdefault("lampman", {})
    jobs = [(v, line, form, src / v / f"{line['line_id']}.{form}.wav", cfg) for v, line, form in character_files(m)
            if not args.voice or v == args.voice]
    with ProcessPoolExecutor(args.jobs) as pool:
        for voice_id, key, entry in pool.map(import_character, jobs):
            index["voices"].setdefault(voice_id, {})[key] = entry
        if not args.voice or args.voice == "lampman":
            ljobs = [(line, form, src / "lampman" / f"{line['line_id']}.{form}.wav", cfg) for line, form in lampman_files(m)]
            for key, entry in pool.map(import_lampman, ljobs):
                index["lampman"][key] = entry
    index["note"] = ("SND-13: written by tools/build/voice_import (do not edit). Each character file's 20 ms Opus "
                     "frames, samples at 48 kHz, duration, band, decoded loudness (LUFS), loudest 20 ms frame (dBFS RMS) "
                     "and SHA-256; the lampman's Ogg Vorbis files. The server reads only this index.")
    index["frame_ms"] = 20
    index["sample_rate"] = RATE
    for group in ("voices", "lampman"):
        index[group] = {k: (dict(sorted(v.items())) if isinstance(v, dict) and group == "voices" else v)
                        for k, v in sorted(index[group].items())}
    INDEX.write_text(json.dumps(index, indent="\t", sort_keys=False) + "\n")
    print(f"import: {len(jobs)} character files; index {INDEX.relative_to(GAME)}")


def check(decode=False):
    """Every problem found, as text; empty when the files, the manifest and the index agree."""
    cfg, m = settings(), manifest()
    problems = []
    if not INDEX.exists():
        return ["no index: run voice_import.py import"]
    index = json.loads(INDEX.read_text())
    max_s = float(tuning("voice.callout_max_duration_s"))
    want = set()
    for voice_id, line, form in character_files(m):
        key = f"{line['line_id']}.{form}"
        path = VOICES_OUT / voice_id / f"{key}.lbv"
        want.add(path)
        entry = index.get("voices", {}).get(voice_id, {}).get(key)
        if not path.exists():
            problems.append(f"missing {path.relative_to(GAME)}")
            continue
        if entry is None:
            problems.append(f"no index entry for {voice_id} {key}")
            continue
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            problems.append(f"{voice_id} {key}: file differs from the index")
        try:
            pre_skip, samples, packets = lbv.read_lbv(data)
        except ValueError as e:
            problems.append(f"{voice_id} {key}: {e}")
            continue
        if len(packets) != entry["frames"] or samples != entry["samples"]:
            problems.append(f"{voice_id} {key}: index says {entry['frames']} frames, file has {len(packets)}")
        if not (len(packets) - 1) * lbv.FRAME_SAMPLES < samples + pre_skip <= len(packets) * lbv.FRAME_SAMPLES:
            problems.append(f"{voice_id} {key}: {len(packets)} frames cannot hold {samples} samples")
        if line["kind"] in CALLOUT_KINDS and entry["duration_s"] > max_s:
            problems.append(f"{voice_id} {key}: {entry['duration_s']} s is over {max_s} s")
        band = band_of(line, form)
        target, cap = cfg["bands"][band]["target_lufs"], band_cap(cfg, band)
        lufs, peak = entry["lufs"], entry["max_frame_rms_dbfs"]
        if decode:
            y = decode_lbv(data)
            if len(y) != samples:
                problems.append(f"{voice_id} {key}: decodes to {len(y)} samples, index says {samples}")
            lufs, peak = loudness.integrated_lufs(y), float(loudness.frame_rms_dbfs(y).max())
        if abs(lufs - target) > cfg["tolerance_lu"]:
            problems.append(f"{voice_id} {key}: {lufs:.2f} LUFS, target {target} +-{cfg['tolerance_lu']}")
        if peak > cap:
            problems.append(f"{voice_id} {key}: a frame at {peak:.2f} dBFS, over the {band} cap {cap}")
    for line, form in lampman_files(m):
        key = f"{line['line_id']}.{form}"
        path = LAMPMAN_OUT / f"{key}.ogg"
        want.add(path)
        entry = index.get("lampman", {}).get(key)
        if not path.exists() or entry is None:
            problems.append(f"lampman {key}: missing file or index entry")
        elif hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            problems.append(f"lampman {key}: file differs from the index")
    for found in list(VOICES_OUT.rglob("*.lbv")) + list(LAMPMAN_OUT.glob("*.ogg")):
        if found not in want:
            problems.append(f"stray file {found.relative_to(GAME)} (not in the manifest)")
    return problems


def cmd_check(args):
    problems = check(args.decode)
    for p in problems:
        print("FAIL " + p, file=sys.stderr)
    if problems:
        return 1
    print("ok   voice set complete: files, manifest and index agree" + (" (every file decoded)" if args.decode else ""))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("placeholders", "import"):
        p = sub.add_parser(name)
        p.add_argument("--src", default=str(SRC_DEFAULT))
        p.add_argument("--voice", default="", help="one voice_id, or lampman")
        p.add_argument("--jobs", type=int, default=os.cpu_count())
    c = sub.add_parser("check")
    c.add_argument("--decode", action="store_true")
    args = ap.parse_args()
    if args.cmd == "placeholders":
        cmd_placeholders(args)
    elif args.cmd == "import":
        cmd_import(args)
    else:
        return cmd_check(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
