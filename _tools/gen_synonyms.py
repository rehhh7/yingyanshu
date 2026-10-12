#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批量为 words.md 中缺近义词/形近词的词条生成「近:/似:」字段（DeepSeek API）。

用法：
  python gen_synonyms.py --key sk-xxx            # 正式生成（自动备份、逐批落盘、可断点续跑）
  python gen_synonyms.py --dry-run               # 只统计缺多少，不联网
  python gen_synonyms.py --key sk-xxx --limit 30 # 只生成前 30 个（试跑）

断点续跑：每批写完直接保存 words.md，中断后重跑会跳过已有近/似的词。
"""
import argparse
import json
import re
import shutil
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent / "cet4_app"
WORDS_MD = APP_DIR / "data" / "words.md"
BACKUP_DIR = APP_DIR.parent / "_tools" / "words_backup"   # 备份放项目外，避免被打进 APK
SETTINGS = Path.home() / "AppData/Roaming/Godot/app_userdata/英眼书/settings.json"

LINE_RE = re.compile(r"^(?P<head>[A-Za-z][^/|]*?)\s*/(?P<phon>[^/]*)/\s*(?P<mean>[^|]+?)(?P<tail>\s*\|.*)?$")


def load_settings():
    if SETTINGS.exists():
        try:
            return json.loads(SETTINGS.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def parse_words(text):
    """返回 (lines, items)；items: [{idx, word, phon, mean, has_syn, has_sim}]"""
    lines = text.split("\n")
    items = []
    for i, ln in enumerate(lines):
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        m = LINE_RE.match(ln)
        if not m:
            continue
        tail = m.group("tail") or ""
        items.append({
            "idx": i,
            "word": m.group("head").strip(),
            "phon": m.group("phon").strip(),
            "mean": m.group("mean").strip(),
            "has_syn": "近:" in tail,
            "has_sim": "似:" in tail,
        })
    return lines, items


def call_api(base, key, model, batch, retries=3):
    words_desc = "\n".join(
        f'{it["word"]} /{it["phon"]}/ {it["mean"]}' for it in batch
    )
    prompt = (
        "你是英语四级词汇老师。下面每个单词给出音标和释义，请为每个单词各配：\n"
        "1. syn：1 个最常用的近义词，格式「近义词(一句中文辨析，20 字内，说清两者区别)」\n"
        "2. sim：1 个容易混淆的形近词，格式「形近词(词性+中文释义，15 字内)」\n"
        "要求：近义词必须真实常用且词义确实相近；形近词必须拼写相近、真实存在；"
        "实在没有合适的就近义词/形近词就填空字符串，不要硬编。\n"
        "只输出 JSON，不要输出任何其他内容：\n"
        '{"results":[{"w":"原单词","syn":"...","sim":"..."}]}\n\n'
        "单词列表：\n" + words_desc
    )
    body = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": "你是严谨的英语词汇编辑，只输出合法 JSON。"},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.3,
        "max_tokens": 6000,
        "response_format": {"type": "json_object"},   # JSON 模式：强制完整合法 JSON，不再截断残缺
    }).encode("utf-8")
    url = base.rstrip("/") + "/chat/completions"
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, data=body, headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer " + key,
            })
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]
            return extract_json(content)
        except (urllib.error.URLError, urllib.error.HTTPError, KeyError, json.JSONDecodeError,
                TimeoutError, ValueError) as e:
            last_err = e
            wait = 5 * (attempt + 1)
            print(f"  ! 第 {attempt + 1} 次尝试失败：{e}，{wait}s 后重试", flush=True)
            time.sleep(wait)
    raise RuntimeError(f"API 连续失败：{last_err}")


def extract_json(content):
    """从回复里抠出 JSON（容忍 ```json 围栏）"""
    m = re.search(r"\{.*\}", content, re.S)
    if not m:
        raise ValueError("回复中没有 JSON")
    return json.loads(m.group(0))


BAD_PAT = re.compile(r"[|/\n\r]")  # 会破坏 words.md 行格式的字符


def clean_field(s):
    s = (s or "").strip().strip("；;。 ")
    return BAD_PAT.sub("", s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", default="", help="DeepSeek API Key（不给则读应用设置）")
    ap.add_argument("--base", default="", help="API Base（默认读应用设置）")
    ap.add_argument("--model", default="", help="模型名（默认读应用设置）")
    ap.add_argument("--batch", type=int, default=25, help="每批词数")
    ap.add_argument("--limit", type=int, default=0, help="只处理前 N 个待生成词（试跑）")
    ap.add_argument("--dry-run", action="store_true", help="只统计，不联网")
    args = ap.parse_args()

    st = load_settings()
    key = args.key or st.get("api_key", "")
    base = args.base or st.get("api_base", "https://api.deepseek.com")
    model = args.model or st.get("api_model", "deepseek-v4-flash")

    text = WORDS_MD.read_text(encoding="utf-8")
    lines, items = parse_words(text)
    todo = [it for it in items if not (it["has_syn"] and it["has_sim"])]
    if args.limit:
        todo = todo[:args.limit]
    print(f"词条总数 {len(items)}，缺近义或形近的 {len([i for i in items if not (i['has_syn'] and i['has_sim'])])}，本次处理 {len(todo)}")
    if args.dry_run:
        for it in todo[:20]:
            print(f"  待生成: {it['word']}  (近:{'有' if it['has_syn'] else '缺'} 似:{'有' if it['has_sim'] else '缺'})")
        return
    if not todo:
        print("全部词条都已有近义词和形近词，无需生成。")
        return
    if not key:
        print("错误：没有 API Key。用 --key sk-xxx 传入，或先在 App 设置里填好。")
        sys.exit(2)

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    bak = BACKUP_DIR / f"words.md.bak-{datetime.now():%Y%m%d-%H%M%S}"
    shutil.copy2(WORDS_MD, bak)
    print(f"已备份原词库 → {bak}")

    done = 0
    queue = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    bi = 0
    while bi < len(queue):
        batch = queue[bi]
        print(f"[批 {bi + 1}/{len(queue)} · {len(batch)} 词] 请求 {model} …", flush=True)
        try:
            res = call_api(base, key, model, batch)
        except RuntimeError as e:
            if len(batch) > 1:
                mid = len(batch) // 2
                queue[bi:bi + 1] = [batch[:mid], batch[mid:]]
                print(f"  ! 批次失败，拆成两半重试（{e}）", flush=True)
                continue
            print(f"  - 放弃 {batch[0]['word']}：{e}", flush=True)
            bi += 1
            continue
        by_word = {}
        for r in res.get("results", []):
            w = str(r.get("w", "")).strip().lower()
            if w:
                by_word[w] = r
        for it in batch:
            r = by_word.get(it["word"].lower())
            if not r:
                print(f"  - 跳过 {it['word']}：回复里没这个词", flush=True)
                continue
            syn, sim = clean_field(r.get("syn")), clean_field(r.get("sim"))
            add = ""
            if syn and not it["has_syn"]:
                add += " | 近: " + syn
            if sim and not it["has_sim"]:
                add += " | 似: " + sim
            if add:
                lines[it["idx"]] = lines[it["idx"]].rstrip() + add
                done += 1
        # 每批落盘：中断不丢
        WORDS_MD.write_text("\n".join(lines), encoding="utf-8")
        print(f"  ✓ 本批写入 {done} 词（累计），已保存", flush=True)
        bi += 1
        time.sleep(1)  # 限流缓冲

    # 完整性校验：词条数、分组数不能变
    _, items2 = parse_words(WORDS_MD.read_text(encoding="utf-8"))
    assert len(items2) == len(items), f"词条数变了！{len(items)} → {len(items2)}，请从备份恢复"
    print(f"完成：共为 {done} 个词补全近义/形近；词条数校验通过（{len(items2)}）。")


if __name__ == "__main__":
    main()
