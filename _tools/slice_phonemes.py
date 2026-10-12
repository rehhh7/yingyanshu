# -*- coding: utf-8 -*-
"""音素引擎素材管线第二步：切片/归一化 → cet4_app/assets/audio/phonemes/<cid>.wav

- bare（元音/双元音）：取稳定中段，长元音/双元音 300ms、短元音 160ms
- pre（辅音+ɑ）：检测元音起点，取 [语音起点, 元音起点) 的辅音段
- post（ɑ+ŋ）：取末尾 200ms 鼻音尾
全部 8ms 淡化 + 峰值归一 0.68，22050Hz/16bit/单声道
"""
import os, wave, math
import numpy as np

SR = 22050
TOOLS = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(TOOLS, "phonemes_raw")
OUT = os.path.join(TOOLS, "..", "cet4_app", "assets", "audio", "phonemes")
MANIFEST = os.path.join(TOOLS, "phoneme_manifest.tsv")
os.makedirs(OUT, exist_ok=True)

LONG_VOWELS = {"iː", "ɜː", "ɑː", "ɔː", "uː"}
DIPHTH = {"eɪ", "aɪ", "ɔɪ", "əʊ", "aʊ", "ɪə", "eə", "ʊə"}
SONORANT = {"m", "n", "l", "r", "w", "j"}
STOP = {"p", "b", "t", "d", "k", "g", "tʃ", "dʒ"}

def load(path):
    w = wave.open(path)
    assert w.getframerate() == SR and w.getsampwidth() == 2
    d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
    w.close()
    return d

def save(path, d):
    d = np.clip(d, -32768, 32767).astype(np.int16)
    w = wave.open(path, "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(d.tobytes()); w.close()

def rms_env(d, win=SR // 100):  # 10ms 窗
    n = len(d) // win
    return np.sqrt(np.mean(d[:n * win].reshape(n, win) ** 2, axis=1))

def speech_bounds(d):
    env = rms_env(d)
    th = max(env.max() * 0.08, 200.0)
    idx = np.where(env > th)[0]
    if len(idx) == 0:
        return 0, len(d)
    pad = 2  # 前后各留 20ms
    return max(0, (idx[0] - pad) * (SR // 100)), min(len(d), (idx[-1] + 1 + pad) * (SR // 100))

def vowel_onset(d, start, sonorant):
    """在 start 之后找元音起点：RMS 陡增处。找不到返回 None。"""
    win = SR // 100
    env = rms_env(d[start:])
    if len(env) < 6:
        return None
    ratio_th = 1.8 if sonorant else 2.5
    for i in range(3, len(env) - 2):
        base = np.median(env[max(0, i - 8):i]) + 1.0
        if env[i] > base * ratio_th and env[i + 1] > base * ratio_th and env[i] > 800:
            return start + i * win
    return None

def finish(d, cid, sym):
    # 8ms 淡化 + 归一
    f = SR * 8 // 1000
    if len(d) > 2 * f:
        ramp = 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, f))
        d[:f] *= ramp; d[-f:] *= ramp[::-1]
    peak = np.abs(d).max()
    if peak > 0:
        d = d * (0.68 * 32768 / peak)
    save(os.path.join(OUT, cid + ".wav"), d)
    return len(d) / SR

report = []
for line in open(MANIFEST, encoding="ascii"):
    line = line.rstrip("\n")
    if not line:
        continue
    cid, _ssml, mode = line.split("\t")
    sym = "".join(chr(int(h, 16)) for h in cid.split("_"))
    d = load(os.path.join(RAW, cid + ".wav"))
    s, e = speech_bounds(d)
    sp = d[s:e]
    if mode == "bare":
        target = int((0.30 if (sym in LONG_VOWELS or sym in DIPHTH) else 0.16) * SR)
        head = int(len(sp) * 0.15)
        seg = sp[head:head + target] if len(sp) - head >= target else sp[:target]
        if len(seg) < int(0.04 * SR):  # 兜底：极短则取中段全部
            seg = sp
    elif mode == "pre":
        onset = vowel_onset(d, s, sym in SONORANT)
        if sym in SONORANT:
            seg = sp[:int(0.12 * SR)]            # 响音边界渐变，检测不可靠，统一取头 120ms
        elif sym in STOP:
            cap = s + int(0.10 * SR)             # 爆破/破擦：爆音+送气 ≤100ms，避免元音泄漏
            if onset is not None and onset - s >= int(0.03 * SR):
                seg = d[s:min(onset, cap)]
            else:
                seg = sp[:int(0.10 * SR)]
        else:                                    # 擦音：检测到元音起点就切，限 70~170ms
            if onset is not None and onset - s >= int(0.05 * SR):
                seg = d[s:onset]
            else:
                seg = sp[:int(0.16 * SR)]
            lo, hi = int(0.07 * SR), int(0.17 * SR)
            if len(seg) < lo:
                seg = sp[:lo]
            elif len(seg) > hi:
                seg = seg[:hi]
    else:  # post：取尾部 200ms
        seg = sp[-int(0.20 * SR):]
    dur = finish(seg.copy(), cid, sym)
    report.append((sym, cid, mode, dur))

for sym, cid, mode, dur in report:
    print("%-4s %-14s %-4s %dms" % (sym, cid, mode, dur * 1000))
total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
print("片段数 =", len(report), "总体积 = %.1f KB" % (total / 1024))
