# 英眼书 · 开发指南（交接版）

> 这份文档是给**下一个接手的开发者 / AI** 看的：看完应能直接构建、改功能、不踩旧坑。
> 问题档案和需求对照表在 `开发记录.md`（更细），本文档是「怎么跑起来 + 坑在哪」。

Godot 4.7.1 开发的安卓背单词应用：本地 Markdown 词库 + DeepSeek AI 助手（聊天整理/拍照识图）+ 离线真人发音 + 两台手机互传（局域网/蓝牙），目标用户是学生。

- 包名：`com.kimi.cet4words`
- 当前版本：**v0.9.30（versionCode 43）**。版本规则：用户没宣布「正式版」前一律 0.9.x 顺延，1.0 留给用户亲口确认
- 平台：**仅 arm64-v8a**（v0.9.26 起去掉 armv7）· **minSdk 24（安卓 7.0，引擎硬底线）** · targetSdk 35 · OpenGL ES 3.0（gl_compatibility）
- 词库策略：v0.9.25 起**不内置任何词条**，出厂空库 + 主页导入指引，全由用户导入（粘贴/文件/拍照识图/互传）

## 目录结构

```
cet4_app/            Godot 工程
  scripts/           全部 GDScript（autoload: DB=db.gd, AI=ai_client.gd；class_name: UI=widgets.gd, LanSync, TTS）
  data/words.md      单词库（出厂只有格式注释，无词条）
  data/phrases.md    词组库（同上）
  data/changelog.md  应用内更新日志（每版必加段落，更新弹窗读它）
  assets/audio/words/  605 个单词真人发音 OGG（共 4MB）
  assets/splash.webp   启动封面（226KB，勿再放 3MB PNG）
  android/plugins/YysKit.aar  自研安卓插件（见「插件重建」）
操作指南/            用户图文指南（4 张批注截图 + 操作指南.md）
开发记录.md          专业开发档案（需求对照/架构/问题档案/版本日志）
上架材料/            商店文案、隐私政策
_tools/              构建工具链（jdk-17、android-sdk、plugin_src 插件源码等，本机路径不入库）
```

## 词库数据格式（Markdown，机器可读）

直接编辑两个 .md 即可入库，无需转换：

```
## 分组名
trivial /ˈtrɪviəl/ adj. 琐碎的 | 近: insignificant(辨析); ... | 似: trifle(辨析); ...
```

解析器（`db.gd parse_import_text`）容忍手写变体：`abandon 放弃`、`abandon v. 放弃`、方括号音标、行首序号、全角空格、`=`/`—` 分隔符；`Day 5` 类标题行自动跳过，`#` 开头是注释。互传文件也是这个格式（`{父分组[名称] 子分组[内容]}` 由脚本切分）。

## 发音（三级兜底）

1. **内置录音包**：`assets/audio/words/<word>.ogg`，605 词真人感录音（SAPI 合成）。**v0.9.26 由 WAV 转 OGG：43.2MB→4.0MB**，`tts.gd` 先试 .ogg 回退 .wav
2. **系统 TTS**：`DisplayServer.tts_*`，有英文语音时用它
3. **有道在线发音**（`online_audio.gd`，设置里可关）：无系统语音时拉 `dict.youdao.com/dictvoice`，缓存到 `user://audio_cache/`

⚠️ 音素拼接引擎（`phonemes/` + test_phoneme.gd）**已被用户否决并移除**——「现场合成机器人味太重」。`_tools/` 里的 gen_phoneme_* 脚本只是历史遗留，不要再接回来，除非用户改主意。

## 构建与测试（Windows；路径一律用占位符，本机自行替换——勿把本机绝对路径写进文档）

```bash
# 占位符：<GODOT>=本机 Godot 4.7.1 编辑器 exe 路径；<REPO>=本仓库克隆目录（_tools/ 在仓库内，jdk-17 与 android-sdk 已自带）
GODOT="<GODOT>"                          # 例：C:/Tools/Godot_v4.7.1-stable_win64.exe
export JAVA_HOME="<REPO>/_tools/jdk-17"
export ANDROID_HOME="<REPO>/_tools/android-sdk"
cd "<REPO>/cet4_app"

# 回归测试（无头）
"$GODOT" --headless --path . -s scripts/test_runner.gd        # 22 项核心（自注入夹具，不依赖内置词）
"$GODOT" --headless --path . -s scripts/test_import_parse.gd  # 解析器（fails=0 为通过）
"$GODOT" --headless --path . -s scripts/test_transfer.gd      # 29 项导入/导出/回滚
"$GODOT" --headless --path . -s scripts/test_lan.gd           # 8 项局域网协议
# 截图冒烟（竖屏模拟，产物在 user://_shots/，脚本启动时会打印实际目录）
"$GODOT" --path . --resolution 540x1152 scenes/test_shots.tscn   # 注意：不能加 -s

# 导出（必须用 debug 签名，与已装包证书一致；换签名 = 用户必须卸载丢数据）
"$GODOT" --headless --path . --export-debug "Android"   # 产物 <REPO>/英眼书.apk
```

导出后**必做验签 + 验包**（中文文件名会让 aapt 报 Illegal byte sequence，先复制成英文名）：

```bash
cp ../英眼书.apk ../yys_check.apk
"$ANDROID_HOME/build-tools/35.0.0/apksigner.bat" verify --print-certs ../yys_check.apk
#   证书 SHA-256 必须是 f4f3a8844ae1da21669a479cdf7024ff4d625929ab6209be01266eb04ce30a13
"$ANDROID_HOME/build-tools/35.0.0/aapt.exe" dump badging ../yys_check.apk | grep -E "sdkVersion|native-code"
#   期望 sdkVersion:'24'、native-code: 'arm64-v8a'
```

## 插件重建（改了 YysKit.java 才需要）

```bash
cd _tools/plugin_src
javac -cp "$ANDROID_HOME/platforms/android-35/android.jar;../plugin_build/godotlib/classes.jar" YysKit.java YysShareProvider.java
jar cf classes.jar com/yys/kit/*.class        # 替换 plugin_build/aar/classes.jar
# 把 aar/ 目录 zip 成 YysKit.aar → 覆盖 cet4_app/android/plugins/YysKit.aar → 重新导出
```

插件职责：ContentResolver 直接读文件（识图/导入，修「图片读取失败」）、系统分享导出、蓝牙互传、震动。蓝牙权限清单在 `_tools/plugin_src/AndroidManifest.xml`（Android 12+ 新权限 / 旧系统经典权限双写）。

## 踩过的坑（别再踩）

| 坑 | 结论 |
|---|---|
| minSdk 想降到 21 | **不行**。godot-lib 4.7.1 模板 APK 自带 minSdkVersion=24（aapt 实测），引擎硬底线，已改回 24，不要再试 |
| 「解析包出现问题」 | 九成是微信/QQ 传包截断或改名——比对字节数、存文件管理器再装；其余是 <安卓7.0 或纯血鸿蒙 NEXT（无 AOSP，任何 APK 都装不了） |
| 识图/导入读不到 content:// 文件 | Godot FileAccess 读不了 content://，必须走自家插件的 ContentResolver（v0.9.23 修复） |
| 弹窗里滑动带动背景页 | 滚动穿透，弹窗容器要吃掉触摸事件（v0.9.20 修） |
| 设置页截图/自动化点不到按钮 | 设置页是**分帧构建**的，自动化脚本要轮询等分组头出现再操作 |
| 导出过滤 | exclude_filter 里排除 test/tool 脚本时**要连 `.gd.uid` 一起排**，否则 uid 残留进包 |
| 大资产 | 音频一律 OGG（WAV 的 1/10 体积）；大图一律 WebP。APK 每版控制在 100MB 内（当前 39.9MB） |
| 热更/导入大乱文档 | 解析器已容忍乱格式；导入后先提示分组单词数再整理，是用户明确要求 |

**发布即挂 Release**：每出一版把 APK 传到 GitHub Release（`gh release create vX.Y.Z 英眼书.apk` 或 Releases 网页上传），用户手机上直接下载；文档与脚本里永不写本机绝对路径（占位符 `<GODOT>`/`<REPO>`），防公开仓库时泄露机器用户名

## 工具链（_tools/）

| 脚本 | 用途 |
|---|---|
| `gen_word_audio.ps1` | SAPI 批量合成 605 词（可断点续跑） |
| `gen_synonyms.py` | DeepSeek 批量补全近义/形近词（`--key` 传入，**密钥不入库**） |
| `plugin_src/` + `plugin_build/` | YysKit 插件源码与 AAR 组装（见上） |
| `gen_phoneme_*` / `phoneme_manifest.tsv` | 已废弃的音素拼接管线，仅存档 |

## 安全约定

- 仓库内**不得出现任何 API Key**（`grep -r "sk-" .` 应为空）——用户曾经把 DeepSeek Key 贴在对话里，只能进本机设置页，永不入代码
- 签名只能用本机 debug keystore（已装包即此证书）
