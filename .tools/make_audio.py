#!/usr/bin/env python3
"""生成 8 首环境音乐，作为 BhandsMusic 的示例音轨。

为什么自己合成而不是找素材：**版权**。这些文件完全由本脚本生成，
不存在任何第三方权利，可以直接随仓库分发。

音乐设计（刻意做得简单，但听感成立）：
- 自然小调，和弦进行 i - VI - III - VII（每个和弦 2 小节）
- 铺底：根音 / 三音 / 五音的叠加正弦，相邻和弦交叉淡入淡出
- 低音：根音降八度，按拍点做短衰减脉冲
- 空气感：低通白噪声，缓慢起伏

用法：
    python3 .tools/make_audio.py
输出到 GlassMusicPlayer/Resources/Audio/*.m4a（AAC 64kbps 单声道）
"""

import os
import subprocess
import wave

import numpy as np

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "GlassMusicPlayer", "Resources", "Audio")
WAV_DIR = "/tmp/bhands_audio_wav"

# (文件名, 根音 MIDI, BPM, 时长秒, 低音强度)
TRACKS = [
    ("ink_rivers",        45, 68, 225, 0.55),   # A2
    ("midnight_neon",     50, 74, 252, 0.60),   # D3
    ("neon_tokyo",        42, 78, 208, 0.50),   # F#2
    ("tokyo_rain",        48, 64, 302, 0.45),   # C3
    ("cyber_bloom",       43, 82, 234, 0.62),   # G2
    ("chrome_heart",      52, 70, 276, 0.58),   # E3
    ("deep_space_love",   47, 58, 168, 0.40),   # B2
    ("velvet_circuit",    45, 88, 245, 0.65),   # A2
]

# i - VI - III - VII，用 (半音偏移, 是否大三和弦)
PROGRESSION = [(0, False), (8, True), (3, True), (10, True)]


def midi_to_hz(n: float) -> float:
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


def chord_freqs(root_midi: int, offset: int, major: bool):
    base = root_midi + offset
    third = 4 if major else 3
    return [midi_to_hz(base), midi_to_hz(base + third), midi_to_hz(base + 7)]


def build(root_midi: int, bpm: float, seconds: float, bass_gain: float) -> np.ndarray:
    n = int(SR * seconds)
    out = np.zeros(n, dtype=np.float64)

    beat = 60.0 / bpm
    chord_len = beat * 4 * 2                 # 2 小节
    overlap = 2.0                            # 交叉淡化时长
    step = int(chord_len * SR)
    seg_total = step + int(overlap * SR)

    # 交叉淡化的窗：两端为 0，中间为 1
    window = np.hanning(seg_total)

    idx = 0
    start = 0
    while start < n:
        offset, major = PROGRESSION[idx % len(PROGRESSION)]
        freqs = chord_freqs(root_midi, offset, major)

        seg_n = min(seg_total, n - start)
        tt = np.arange(seg_n) / SR
        seg = np.zeros(seg_n, dtype=np.float64)

        for i, f in enumerate(freqs):
            # 每个音稍微去谐，产生自然的合唱感
            detune = 1.0 + (i - 1) * 0.0016
            seg += np.sin(2 * np.pi * f * detune * tt) * (0.9 - i * 0.12)
            seg += np.sin(2 * np.pi * f * 2.0 * tt) * 0.06   # 一点泛音

        out[start:start + seg_n] += seg * window[:seg_n] * 0.16
        start += step
        idx += 1

    # 低音脉冲：每拍一个短衰减的根音
    root_hz = midi_to_hz(root_midi - 12)
    pulse_len = int(beat * 1.6 * SR)
    pulse_t = np.arange(pulse_len) / SR
    pulse = np.sin(2 * np.pi * root_hz * pulse_t) * np.exp(-pulse_t * 4.5)

    t = 0.0
    while t < seconds:
        s = int(t * SR)
        seg_n = min(pulse_len, n - s)
        if seg_n > 0:
            out[s:s + seg_n] += pulse[:seg_n] * bass_gain * 0.55
        t += beat

    # 空气感：低通白噪声，缓慢起伏
    noise = np.random.default_rng(7).normal(0, 1, n)
    smoothed = np.convolve(noise, np.ones(64) / 64, mode="same")
    lfo = 0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * np.arange(n) / SR)
    out += smoothed * lfo * 0.012

    # 首尾淡入淡出，避免爆音
    fade_in, fade_out = int(SR * 2.0), int(SR * 4.0)
    out[:fade_in] *= np.linspace(0, 1, fade_in)
    out[-fade_out:] *= np.linspace(1, 0, fade_out)

    peak = np.max(np.abs(out)) or 1.0
    return (out / peak * 0.89).astype(np.float32)


def write_wav(path: str, samples: np.ndarray) -> None:
    pcm = (samples * 32767).astype(np.int16)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(WAV_DIR, exist_ok=True)

    total = 0
    for name, root, bpm, seconds, bass in TRACKS:
        wav_path = os.path.join(WAV_DIR, f"{name}.wav")
        m4a_path = os.path.join(OUT_DIR, f"{name}.m4a")

        print(f"合成 {name}  {seconds}s  bpm={bpm} ...", end=" ", flush=True)
        write_wav(wav_path, build(root, bpm, seconds, bass))

        subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", wav_path, m4a_path],
            check=True, capture_output=True,
        )
        size = os.path.getsize(m4a_path)
        total += size
        print(f"{size/1024/1024:.1f}MB")

    print(f"\n合计 {total/1024/1024:.1f}MB → {OUT_DIR}")


if __name__ == "__main__":
    main()
