# 英眼书（CET-4 背单词 App）

Godot 4.7.1 开发的安卓背单词应用：本地词库 + AI 助手 + 离线发音，目标用户是学生，兼容 Android 5.0（minSdk 21）起的低配机型，全程可离线使用（AI 功能除外）。

- 包名：`com.kimi.cet4words`
- 当前版本：v0.9.14（versionCode 27；未宣布正式版前一律 0.9.x 顺延，1.0 留给用户确认）
- 渲染器 / 架构：OpenGL ES 3.0（gl_compatibility），armeabi-v7a + arm64-v8a 双架构

## 目录结构

```
cet4_app/            Godot 工程（scripts/ 全部 GDScript，data/ 词库，assets/ 字体图标音频）
  data/words.md      单词库（605 词，Markdown 纯文本）
  data/phrases.md    词组库（3366 条，Markdown 纯文本）
  data/changelog.md  应用内更新日志
新建文件夹/           词库上游源稿（Markdown 单词/词组合集）
上架材料/             商店文案、隐私政策、上架手册
_tools/              构建工具链（语音包合成、近义词生成等，见下）
开发记录.md           专业开发档案（需求对照/架构/32 条问题档案/测试矩阵/版本日志）
```

## 词库数据格式（Markdown，机器可读）

词库就是两个 Markdown 文件，**直接编辑即可入库**，无需任何转换：

```
# 四级单词库（可直接编辑：## 开头是分组，每行一个单词）
# 格式：单词 /音标/ 词性. 释义 | 近: 近义词(辨析); ... | 似: 形近词(辨析); ...

## 手写一
trivial /ˈtrɪviəl/ adj. 琐碎的；不重要的 | 近: insignificant(...) | 似: trifle(...)
```

导入解析器（`db.gd parse_import_text`）同时容忍手写常见变体：`abandon 放弃`、`abandon v. 放弃`、`abandon/əˈbændən/ 放弃`、方括号音标、行首序号 `1.` `-` `•`、全角空格、`=` `＝` `—` 等分隔符；`Day 5`/`Unit 2` 标题行自动跳过，`#` 开头是注释。

## 离线发音（三级兜底，零网络）

1. **内置录音包**：`assets/audio/words/` 605 个 WAV（Windows SAPI en-US 合成，导入时 QOA 压缩 → APK 内 8.6MB）
2. **音素拼接引擎**：`assets/audio/phonemes/` 44 个 IPA 音素片段（PCM 290KB），运行时按音标现场拼接（重音增益 + 12ms 交叉淡化），任何带音标的导入词都能发声
3. **系统 TTS**：最后兜底（AI 页长句、词组）

## 构建与测试

```bash
# 回归测试（无头）
godot --headless --path cet4_app --script res://scripts/test_runner.gd        # 23 项核心
godot --headless --path cet4_app --script res://scripts/test_import_parse.gd  # 14 项解析
godot --headless --path cet4_app --script res://scripts/test_phoneme.gd       # 音素引擎 + 全库冒烟
# 导出（必须用 debug 签名，与已装包证书一致；换签名=用户必须卸载丢数据）
godot --headless --path cet4_app --export-debug "Android" ../英眼书.apk
```

打包环境：`_tools/jdk-17` + `_tools/android-sdk`（本地路径，不入库）。

## 工具链（_tools/）

| 脚本 | 用途 |
|---|---|
| `gen_word_audio.ps1` | SAPI 批量合成 605 词 WAV（可断点续跑） |
| `gen_phoneme_manifest.py` → `gen_phoneme_raw.ps1` → `slice_phonemes.py` | 音素包三步管线 |
| `gen_synonyms.py` | DeepSeek 批量补全词库近义/形近词（`--key` 传入，**密钥不入库**） |

## 安全约定

- 仓库内**不得出现任何 API Key**（`grep -r "sk-" .` 应为空）
- 签名只能用本机 debug keystore（已装包即此证书）
