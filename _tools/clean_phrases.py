# -*- coding: utf-8 -*-
"""清洗四级听力词组 OCR 数据"""
import re, json, itertools, sys
from pathlib import Path
sys.path.insert(0, str(Path(r"C:\Users\s\Desktop\英语\_tools\pylib")))
sys.path.insert(0, str(Path(r"C:\Users\s\Desktop\英语\_tools")))
from wordfreq import zipf_frequency, top_n_list
from overrides import OVERRIDES, CN_FIX_EXTRA

ROOT = Path(r"C:\Users\s\Desktop\英语")
SRC = ROOT / "新建文件夹" / "四级听力高亮词汇合集.md"
WORDS = set((ROOT / "_tools" / "downloads" / "words_alpha.txt").read_text(encoding="utf-8").split())
COMMON = set((ROOT / "_tools" / "downloads" / "words120k.txt").read_text(encoding="utf-8").split())
WORDS |= COMMON   # 词频表天然含变形词，与词典合并做合法性校验
SHORT_OK = {w for w in top_n_list("en", 6000) if len(w) <= 3} | {"a", "i"}
SUFFIX_FRAG = {"ing","ed","er","es","tion","sion","ment","ness","ly","al","le","el","en","ic",
               "ty","ry","ous","ive","ism","ist","ate","ion","ors","ers","ies","sts","nts"}

CONTRACTIONS = {"that's","it's","don't","doesn't","didn't","can't","couldn't","won't","wouldn't",
    "isn't","aren't","wasn't","weren't","haven't","hasn't","hadn't","i'm","you're","we're","they're",
    "i've","we've","they've","you've","i'll","you'll","we'll","they'll","i'd","you'd","we'd","they'd",
    "let's","there's","here's","what's","who's","he's","she's","ain't","gonna","wanna","gotta",
    "o'clock","'em","y'all","mustn't","shan't","shouldn't","mightn't","needn't","daren't","n't"}
WORDS |= CONTRACTIONS | {"ok","okay","etc","vs","tv","usa","uk","diy","ai","ad","ads","co","inc"}

DIGIT_MAP = {"0":"o","1":"l","2":"z","3":"e","4":"a","5":"s","6":"g","7":"t","8":"b","9":"g"}

def is_valid(t):
    """合法 = 常用词（含变形），或词典词且词频不算太冷；后缀碎片和生僻短词不算"""
    if t in SUFFIX_FRAG:
        return False
    if len(t) <= 3:
        return t in SHORT_OK
    if t in COMMON:
        return True
    return t in WORDS and zipf_frequency(t, "en") >= 2.5

def _pick(cands):
    """多个候选用词频裁决：第一名 zipf 领先第二名 ≥1.5 才采纳"""
    if not cands:
        return None
    if len(cands) == 1:
        return cands[0]
    ranked = sorted(cands, key=lambda c: -zipf_frequency(c, "en"))
    if zipf_frequency(ranked[0], "en") - zipf_frequency(ranked[1], "en") >= 1.5:
        return ranked[0]
    return None

def edit1_fix(t):
    """编辑距离 1 的候选修复"""
    if len(t) < 4:
        return None
    letters = "abcdefghijklmnopqrstuvwxyz"
    cands = set()
    for i in range(len(t) + 1):
        for c in letters:
            cands.add(t[:i] + c + t[i:])
    for i in range(len(t)):
        cands.add(t[:i] + t[i + 1:])
        for c in letters:
            cands.add(t[:i] + c + t[i + 1:])
    for i in range(len(t) - 1):
        cands.add(t[:i] + t[i + 1] + t[i] + t[i + 2:])
    return _pick([c for c in cands if c in COMMON and c != t])

def variants_repeat(tok):
    """把连续重复字母折叠"""
    runs = []
    i = 0
    while i < len(tok):
        j = i
        while j < len(tok) and tok[j] == tok[i]:
            j += 1
        runs.append((tok[i], j - i)); i = j
    if not any(n >= 2 for _, n in runs):
        return None
    opts = [[ch * k for k in range(1, n + 1)] for ch, n in runs]
    hits = [c for c in ("".join(p) for p in itertools.product(*opts)) if c in WORDS and c != tok]
    return _pick(hits)

def fix_token(tok):
    """返回修复后的合法 token，修不了返回 None"""
    t = re.sub(r"[^a-z']", "", tok.lower())
    if not t:
        return ""
    if is_valid(t):
        return t
    # 数字替换
    if any(c.isdigit() for c in tok):
        base = tok.lower()
        pools = []
        ok = True
        for c in base:
            if c.isdigit():
                pools.append([DIGIT_MAP[c]])
            elif c.isalpha() or c == "'":
                pools.append([c])
            else:
                ok = False; break
        if ok and sum(1 for c in base if c.isdigit()) <= 4:
            hits = set()
            for combo in itertools.product(*pools):
                cand = re.sub(r"[^a-z']", "", "".join(combo))
                if cand in WORDS:
                    hits.add(cand)
            pick = _pick(list(hits))
            if pick:
                return pick
    # 折叠重复字母
    r = variants_repeat(t)
    if r:
        return r
    # 编辑距离 1 修复
    e = edit1_fix(t)
    if e:
        return e
    return None

def clean_phrase(raw):
    """返回 (清洗后词组 or None, 原因)"""
    s = raw.strip().strip("|").strip()
    s = s.replace("，", " ").replace(".", " . ")
    s = re.sub(r"\s+", " ", s).strip()
    if not s:
        return None, "空"
    toks = s.split()
    # 去掉首尾游离单字母（OCR 列噪声），词首保留 a/i
    while toks and len(re.sub(r"[^a-z]", "", toks[0].lower())) <= 1 \
            and toks[0].lower().strip("'.,;:!?") not in ("a", "i"):
        toks.pop(0)
    while toks and len(re.sub(r"[^a-z]", "", toks[-1].lower())) <= 1:
        toks.pop()
    # 句中游离单字母（a/i 除外）是碎片，剔除
    toks = [t for t in toks if len(re.sub(r"[^a-z]", "", t.lower())) > 1
            or t.lower().strip("'.,;:!?") in ("a", "i")]
    out = []
    i = 0
    fixes = 0
    while i < len(toks):
        tok = toks[i]
        core = re.sub(r"[^a-z']", "", tok.lower())
        if not core:
            if re.fullmatch(r"\d+", tok):  # 纯数字噪声
                i += 1; continue
            i += 1; continue
        if is_valid(core):
            out.append(core); i += 1; continue
        # 与后面的 token 拼接（优先，OCR 常把词劈开）
        joined = None
        for k in (2, 3):
            if i + k <= len(toks):
                cand = re.sub(r"[^a-z']", "", "".join(toks[i:i + k]).lower())
                if len(cand) >= 4 and cand in WORDS:
                    joined = (cand, k); break
        if joined:
            out.append(joined[0]); fixes += 1; i += joined[1]; continue
        # 修复当前 token
        fixed = fix_token(tok)
        if fixed == "":
            i += 1; continue
        if fixed:
            out.append(fixed); fixes += 1; i += 1; continue
        # 拆分粘连 token 为两个词（两段都 ≥3 字母且都是常用词）
        split_ok = False
        split_cands = []
        for j in range(3, len(core) - 2):
            a, b = core[:j], core[j:]
            if len(b) >= 3 and a in COMMON and b in COMMON:
                split_cands.append((a, b, zipf_frequency(a, "en") + zipf_frequency(b, "en")))
        if split_cands:
            split_cands.sort(key=lambda x: -x[2])
            a, b, _ = split_cands[0]
            out.extend([a, b]); fixes += 1; split_ok = True
        if split_ok:
            i += 1; continue
        return None, f"无法识别的词: {tok}"
    if not out:
        return None, "清洗后为空"
    if len(out) == 1 and len(out[0]) <= 1:
        return None, "单字母残片"
    if fixes > 2:
        return None, "修复过多，不可靠"
    # 终检：每个 token 都必须通过严格校验（挡住词典里的生僻垃圾词和碎片）
    for t in out:
        if not is_valid(t):
            return None, f"含可疑低频词: {t}"
    return " ".join(out), ("已修复" if fixes else "原文")

CN_FIX = [("井非", "并非"), ("喵准", "瞄准"), ("颜为", "颇为"), ("威助", "威胁"),
          ("惊取", "惊异"), ("天错", "大错"), ("，，", "，")] + list(CN_FIX_EXTRA)
def clean_cn(raw):
    s = re.sub(r"[a-zA-Z0-9]+", " ", raw)          # 去掉混入的拉丁字符
    s = re.sub(r"[/\\|<>~@#$%^&*+=_—–-]+$", "", s.strip())
    for a, b in CN_FIX:
        s = s.replace(a, b)
    s = re.sub(r"\s+", "", s)                       # 中文内部不留空格
    s = re.sub(r"[.。]{2,}", "……", s)
    return s.strip("。.;；,，")

def main():
    lines = SRC.read_text(encoding="utf-8").splitlines()
    sections = []   # [(标题, [(词组,释义,状态,原文)])]
    cur_title, cur = None, []
    total = ok = fixed = dropped = manual = 0
    review = []
    for ln in lines:
        m = re.match(r"^## (P\d+\..+)", ln)
        if m:
            if cur_title: sections.append((cur_title, cur))
            cur_title, cur = m.group(1).strip(), []
            continue
        m = re.match(r"^\|\s*\d+\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*$", ln)
        if m and cur_title:
            raw_en, raw_cn = m.group(1), m.group(2)
            total += 1
            ov = OVERRIDES.get(raw_en.strip())
            if ov is None and raw_en.strip() in OVERRIDES:
                # 人工复核确认剔除
                dropped += 1
                review.append((cur_title, raw_en, raw_cn, "人工复核剔除"))
                continue
            if ov is not None:
                # 人工修正：直接采用覆盖结果
                if isinstance(ov, str):
                    en, cn_ov = ov, None
                else:
                    en, cn_ov = ov
                cn = cn_ov if cn_ov else clean_cn(raw_cn)
                ok += 1; manual += 1
                cur.append((en, cn, "人工修正", raw_en))
                continue
            en, status = clean_phrase(raw_en)
            cn = clean_cn(raw_cn)
            if en is None:
                dropped += 1
                review.append((cur_title, raw_en, raw_cn, status))
                continue
            if status == "已修复": fixed += 1
            ok += 1
            cur.append((en, cn, status, raw_en))
    if cur_title: sections.append((cur_title, cur))

    # 组内去重
    for idx, (t, items) in enumerate(sections):
        seen, dedup = set(), []
        for it in items:
            if it[0] not in seen:
                seen.add(it[0]); dedup.append(it)
        sections[idx] = (t, dedup)

    # 输出清洗版
    out = ["# 四级听力词组（清洗版）", "",
        f"> 源数据 3469 条（50 套真题 OCR）→ 保留 {ok} 条，其中自动修复 {fixed} 条、人工复核修正 {manual} 条，剔除 {dropped} 条（明细见《待复核》）",
        "> 清洗规则：修粘连/多余空格/重复字母/数字误识别；英文经 23 万词词典校验；组内去重", ""]
    for t, items in sections:
        out.append(f"## {t}")
        out.append(f"*共 {len(items)} 个词组*")
        out.append("")
        out.append("| 序号 | 词组 | 释义 |")
        out.append("| --- | --- | --- |")
        for i, (en, cn, st, _) in enumerate(items, 1):
            out.append(f"| {i} | {en} | {cn} |")
        out.append("")
    (ROOT / "新建文件夹" / "四级听力词组_清洗版.md").write_text("\n".join(out), encoding="utf-8")

    rv = ["# 词组清洗 · 复核文件", "",
          "## 一、被剔除的条目（实在修不了）", "", f"共 {dropped} 条", ""]
    for t, en, cn, why in review:
        rv.append(f"- [{t}] `{en}` | {cn} —— {why}")
    rv += ["", "## 二、自动修复的条目（请抽查是否修对了）", "", f"共 {fixed} 条", ""]
    for t, items in sections:
        for en, cn, st, raw in items:
            if st == "已修复":
                rv.append(f"- [{t}] `{raw}` → **{en}** | {cn}")
    (ROOT / "新建文件夹" / "四级听力词组_待复核.md").write_text("\n".join(rv), encoding="utf-8")

    # 修复样例（供抽查）
    samples = [(t, it[3], it[0]) for t, items in sections for it in items if it[2] == "已修复"][:40]
    print(f"total={total} ok={ok} fixed={fixed} manual={manual} dropped={dropped}")
    print(json.dumps(samples[:25], ensure_ascii=False, indent=1))

if __name__ == "__main__":
    main()
