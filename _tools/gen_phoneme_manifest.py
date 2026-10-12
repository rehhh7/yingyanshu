# -*- coding: utf-8 -*-
"""音素引擎素材管线第一步：生成 SSML 合成清单（纯 ASCII，IPA 用 XML 实体表示）。

清单格式（TSV）：clip_id \\t ssml_markup \\t mode
- clip_id：音素符号逐字符转 unicode 码位十六进制（如 0259），与运行时 GDScript 计算规则一致
- mode：bare=元音单独合成；pre=辅音+ɑ（取元音前的部分）；post=ɑ+辅音（取尾部，ŋ 专用）
"""
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "phoneme_manifest.tsv")

def ent(sym: str) -> str:
    """音素符号 → XML 实体串（纯 ASCII）"""
    return "".join("&#x%X;" % ord(c) for c in sym)

def cid(sym: str) -> str:
    """音素符号 → 文件名 id（码位十六进制下划线连接）"""
    return "_".join("%04X" % ord(c) for c in sym)

# 44 音素清单（DJ 音标体系，与词库 words.md 用符号一致）
VOWELS = ["iː", "ɪ", "e", "æ", "ɜː", "ə", "ʌ", "ɑː", "ɒ", "ɔː", "ʊ", "uː"]
DIPHTH = ["eɪ", "aɪ", "ɔɪ", "əʊ", "aʊ", "ɪə", "eə", "ʊə"]
CONS_PRE = ["p", "b", "t", "d", "k", "g",           # 爆破
            "f", "v", "θ", "ð", "s", "z", "ʃ", "ʒ", "h",  # 擦音
            "tʃ", "dʒ",                               # 破擦
            "m", "n", "l", "r", "w", "j"]             # 鼻/舌边/半元音
CONS_POST = ["ŋ"]                                     # ŋ 不能作音节首，放元音后取尾

rows = []
for s in VOWELS + DIPHTH:
    rows.append((cid(s), '<phoneme alphabet="ipa" ph="%s">x</phoneme>' % ent(s), "bare"))
for s in CONS_PRE:
    ph = ent(s) + "&#x251;"   # 辅音 + ɑ
    rows.append((cid(s), '<phoneme alphabet="ipa" ph="%s">x</phoneme>' % ph, "pre"))
for s in CONS_POST:
    ph = "&#x251;" + ent(s)   # ɑ + 辅音
    rows.append((cid(s), '<phoneme alphabet="ipa" ph="%s">x</phoneme>' % ph, "post"))

with open(OUT, "w", encoding="ascii", newline="") as f:
    for c, m, mode in rows:
        f.write("%s\t%s\t%s\n" % (c, m, mode))
print("清单条数 =", len(rows), "->", OUT)
