# 英眼书 · AI 交接手册

> 写给下一个接手本项目的 AI（或人类工程师）：读完这一份就能改代码、能构建、能避坑。
> 最后更新：v0.9.17（2026-10-12）。本手册与代码同库，改架构时请同步更新。

---

## 0. 一页速览

| 项 | 值 |
|---|---|
| 项目 | 英眼书 —— 离线优先的英语背单词 Android 应用（面向学生、低配手机） |
| 技术栈 | Godot 4.7.1 stable（GDScript）+ 自写 Java 插件 YysKit（系统分享/蓝牙）+ Gradle 构建 |
| 仓库 | GitHub 私有 `rehhh7/yingyanshu`；**仓库根 = 工作区 `C:\Users\s\Desktop\英语`**，工程在 `cet4_app/` |
| 当前版本 | v0.9.17 / versionCode 30。**版本规则：用户未宣布正式版前一律 0.9.x 递增；1.0 才是正式版** |
| 签名 | debug keystore，SHA-256 `f4f3a8844ae1da21669a479cdf7024ff4d625929ab6209be01266eb04ce30a13`。**换签名 = 老用户无法覆盖安装，绝不能换** |
| 平台底线 | **Android 7.0（API 24）**。godot-lib 4.7.1 的 AAR 自带 minSdkVersion=24，早期文档写的"Android 5.0"从未成立过；Android 4.x 在 Godot 4 下不可能支持 |
| 词库规模 | 单词 605、词组 3366（测试实测值），全部 Markdown 文本存于 `cet4_app/data/` |
| 用户数据 | `user://`（词库副本、学习进度、设置、备份）。APK 覆盖安装即保留 |

---

## 1. 目录地图

```
英语/                        ← 仓库根（也是 Kimi 工作区）
├── cet4_app/                ← Godot 工程根（--path 指这里）
│   ├── project.godot        ← 自动加载 DB(db.gd)、UI(widgets.gd) 等单例
│   ├── export_presets.cfg   ← Android 导出预设（Gradle 构建、插件开关、版本号）
│   ├── main.tscn            ← 唯一场景，所有视图挂在它下面切换
│   ├── scripts/             ← 全部 GDScript，约 7100 行（含测试）
│   │   ├── main.gd          ← 入口：视图路由、返回键、启动封面
│   │   ├── db.gd            ← 数据中心：词库/分组/设置/备份/互传解析（最大文件）
│   │   ├── widgets.gd       ← UI 工厂：按钮、弹窗、卡片、确认框、震动
│   │   ├── home_view.gd     ← 主页：词表卡片网格（长按出组菜单）
│   │   ├── study_view.gd    ← 学习页（看词选义/拼写）
│   │   ├── dictation_view.gd← 听写页
│   │   ├── star_view.gd     ← 星标页
│   │   ├── stats_view.gd    ← 统计页（streak 等）
│   │   ├── settings_view.gd ← 设置页（导入/导出/互传/发音/关于）
│   │   ├── ai_view.gd       ← AI 助手界面
│   │   ├── ai_client.gd     ← DeepSeek API 客户端（用户的 key 存 user:// 设置，不入库）
│   │   ├── tts.gd           ← 发音三级兜底：录音包 → 系统 TTS → 在线发音
│   │   ├── online_audio.gd  ← 有道语音接口兜底 + user://audio_cache 缓存
│   │   ├── share.gd         ← YysKit 分享封装（Share.available/file/text）
│   │   ├── lan_sync.gd      ← 局域网互传协议（UDP 发现 + TCP 握手传输）
│   │   ├── lan_sync_dialog.gd← 互传弹窗（局域网/蓝牙双通道 UI）
│   │   ├── test_*.gd        ← headless 测试脚本（见第 6 节）
│   │   └── tool_*.gd        ← 一次性工具脚本
│   ├── data/
│   │   ├── words.md         ← 单词主词库（Markdown，# Day 分组）
│   │   ├── phrases.md       ← 词组库
│   │   ├── changelog.md     ← 应用内"更新日志"页读取它（每次发版必更）
│   │   └── audio/words/     ← 605 个 QOA 录音（离线发音，QOA 比 PCM 省 ~70%）
│   ├── android/
│   │   ├── .build_version   ← Gradle 构建必需！内容 `4.7.1.stable`（见踩坑 2）
│   │   ├── plugins/
│   │   │   ├── YysKit.aar   ← 编译产物（由 _tools/plugin_src 构建）
│   │   │   └── YysKit.gdap  ← 插件声明（config name="YysKit"）
│   │   └── build/           ← Gradle 构建模板（android_source.zip 解出后定制）
│   │       ├── .gdignore    ← 必需！防止编辑器扫描本目录（见踩坑 2）
│   │       ├── config.gradle← compileSdk 35 / targetSdk 35 / buildTools 35.0.0
│   │       └── gradle/wrapper/gradle-wrapper.properties ← distributionUrl 指向本地 zip
│   └── assets/              ← 图标、封面
├── _tools/
│   ├── plugin_src/          ← YysKit Java 源码（YysKit.java + YysShareProvider.java + AndroidManifest.xml）
│   ├── plugin_build/        ← javac 编译与 AAR 打包工作区（classes.jar 从这里出）
│   ├── jdk-17/              ← 本地 JDK 17（构建用 JAVA_HOME）
│   ├── android-sdk/         ← platforms 只有 android-35；build-tools 35.0.0
│   └── gradle-8.11.1-bin.zip← Gradle 发行包（网络被拦截，wrapper 走本地文件）
├── 开发记录.md               ← 人类读的开发历史（版本表、设计决策、已知限制）
├── AI交接手册.md            ← 本文件（注：实际放 cet4_app/ 内则随工程走）
└── 英眼书.apk               ← 导出产物（.gitignore 排除）
```

---

## 2. 架构与设计思路（为什么这么写）

### 2.1 单场景 + 视图路由，不用 Godot 场景切换
所有"页面"是 `main.tscn` 下的 Control 子树，由 `main.gd` 显隐切换。
- 理由一：低配机内存小，场景切换会释放/重建整棵树，卡顿明显；显隐切换是 O(1)。
- 理由二：跨页状态（学习进度、滚动位置）天然保留，不用存档恢复。
- 代价：所有视图常驻内存。对策：视图构建时懒加载重资源，列表用固定行高 + 不复用但限量渲染（词表卡片一次全建，因为组数量 < 50，实测无压力）。

### 2.2 DB 单例是唯一数据入口
`db.gd` 持有 words/phrases 数组、分组索引、设置字典；UI 层只调 DB 方法，从不自己读写文件。
- 写入路径统一走 `DB.save_*()` → 先写 `user://*.tmp` 再 rename（防写一半断电损坏）。
- 每次结构性修改（删组、覆盖导入）前自动 `backup_libraries()` 留快照，设置页可回滚。
- 查重规则：单词按 `w`（原形小写），词组按 `en` 小写；**自定义词条打 `custom=true` 标记**，互传导出只导自定义的（内置词库对方本来就有）。

### 2.3 widgets.gd 工厂统一交互规格
- 所有按钮热区 ≥ 48dp、按下有震动（设置里可关）、滑动中不触发点击（`_pressed` 里判 `累计位移 < 24px` 才算点击，防误触——这是用户实测提的需求）。
- `UI.confirm_dialog(title, body, ok_text, on_ok, danger, cancel_text, on_cancel)`：danger=true 按钮变红（删除操作用）；**on_cancel 是后加的尾参，遮罩点击和取消按钮都会触发**——互传确认框靠它回"拒绝"。
- `UI.double_press(btn, hint, on_confirm)`：双击确认模式（互传入口用，防误触）。
- `UI.sheet(title, items, on_pick)`：底部动作菜单（词表组长按菜单用）。

### 2.4 词库一律 Markdown 文本
用户硬性要求：好打包、机器可读、方便别的工具生成。内置库 `data/words.md`、互传载荷、本地导入全部走同一套容错解析器（`_parse_word_lines`，23 项解析测试）。
- 兼容格式：纯词、`词 音标 释义`、TSV、ECDICT 式 CSV、JSONL、双栏合并行、带词性缩写并入释义。
- 解析不出的行进 unknown 列表返回给调用方提示，**绝不静默丢弃**。

### 2.5 发音三级兜底（tts.gd）
1. 内置录音包（605 词 QOA，离线、音质最好）；
2. `has_english_voice()` 为真 → 系统 TTS（DisplayServer.tts）；
3. 设置里「无系统语音时联网发音」开（默认开）→ `online_audio.gd` 拉有道接口 `https://dict.youdao.com/dictvoice?audio=<词>&type=1`，mp3 存 `user://audio_cache/`，AudioStreamMP3.data 播放，8 秒超时，失败回调退回系统 TTS。
- 曾评估过「48 音素现场拼接」方案（老式电子词典思路，<1MB）：已否决，机器人味太重，代码已剔除（v0.9.15 提交记录有详情）。

### 2.6 触控与长按约定（用户实测磨出来的）
- 词表组卡片：550ms 长按 → 组菜单（重命名 / 分享本组 / 删除分组）。
- 文本输入框：长按 2 秒 → 系统选择/粘贴菜单 + 震动一下（设置可关）。
- 输入框区域内滑动 = 滚动，不是选择文本。
- AI 输入框贴输入法上沿（键盘弹出时整个输入栏上移），文档文字黑色加粗。

---

## 3. 数据格式规范

### 3.1 内置词库 data/words.md
```markdown
# Day 1
abandon /əˈbændən/ v. 放弃；抛弃
ability n. 能力
```
- `# ` 开头 = 父项目（分组名，Day N / 手写一 / 自定义……）；其下每行一个词条 = 子项目。
- 词条行：`单词 [音标] 释义`；词组行：`英文 中文`（两个以上空格或 TSV 分隔均可，解析器兼容）。

### 3.2 互传载荷（固定 Markdown，v0.9.17 起）
```
# 英眼书互传

# 我的小组
apple /ˈæpl̩/ n. 苹果（新释义）

# 另一个组
...
```
- 第一行标记头 `# 英眼书互传`（解析后丢弃该空组）。
- 只含**自定义词条**；学习记录不传，接收方保留自己的进度（v0.9.17 起从 JSON 备份格式改为此，老 JSON 载荷仍可被 `import_backup` 兼容接收）。
- 接收方二选一：**扩展词汇**（merge，只加自己没有的）或**覆盖原词汇**（overwrite，同名组的自定义词条先清空再写入）。

### 3.3 传输握手协议（LAN 与蓝牙 RFCOMM 完全相同）
```
请求方 → 宿主：  "REQ|<自报设备名>\n"
宿主   → 请求方：4 字节大端长度 N + N 字节 UTF-8 载荷
                 N = 0 表示用户点了拒绝
```
- 蓝牙 UUID：`3f6b2a10-7c4e-4b2d-9a1f-2e5c8d0b9a77`（两端必须一致）。
- LAN：UDP 37020 广播发现（JSON 自报：名字+IP+端口），TCP 传输。
- GDScript 侧状态机（`lan_sync.gd::_poll_client`）：-1 发 REQ → -3 等 4 字节长度 → >0 读载荷。

### 3.4 user:// 文件清单
| 文件 | 内容 |
|---|---|
| `custom_words.json` / `custom_phrases.json` | 自定义词条（含分组归属） |
| `settings.json` | 设置字典（含 `online_audio`、`group_renames`、`group_deletes`、AI key） |
| `backup_*.json` | 结构修改前的自动快照（设置页可回滚） |
| `audio_cache/` | 在线发音 mp3 缓存 |
| `share_cache/` | （应用私有 filesDir 内）分享暂存，YysShareProvider 只服务这个目录 |
| `session.json` | 学习会话断点续学 |

---

## 4. 构建流水线（照抄可复现）

### 4.1 环境（全部本地，不装系统级；路径用占位符，勿把本机绝对路径写进文档）
```
Godot : <GODOT>                     （本机 Godot 4.7.1-stable win64 编辑器 exe）
JDK   : <REPO>/_tools/jdk-17        （JAVA_HOME 指它）
SDK   : <REPO>/_tools/android-sdk   （platforms/android-35 + build-tools/35.0.0）
Gradle: 由 wrapper 解析，distributionUrl=file:///C:/gradle/gradle-8.11.1-bin.zip
        （官网 gradle-8.11.1-bin.zip 下载后放 C:/gradle/——中性路径不含用户名；本机 TLS 拦截导致官方源直连失败，勿改回 https）
```
> 本机有 TLS 拦截：`curl` 一律 `--ssl-no-revoke`；仓库已设 `http.sslVerify=false`；
> Gradle 发行包下载被拦，所以 wrapper 指本地 zip。Maven Central 依赖可正常下载。

### 4.2 导出 APK（每次发版就这一条命令）
```bash
cd "<REPO>/cet4_app" && \
JAVA_HOME="<REPO>/_tools/jdk-17" \
ANDROID_HOME="<REPO>/_tools/android-sdk" \
"<GODOT>" --headless --path . --export-debug "Android"
# 产物：<REPO>/英眼书.apk
```

### 4.3 改 YysKit 插件后的重编译
```bash
cd "<REPO>/_tools"
"<REPO>/_tools/jdk-17/bin/javac" --release 11 \
  -cp "android-sdk/platforms/android-35/android.jar;plugin_build/godotlib/classes.jar" \
  -d plugin_build/classes plugin_src/YysKit.java plugin_src/YysShareProvider.java
# 打 classes.jar → 与 plugin_src/AndroidManifest.xml + 空 R.txt 一起 zip 成 YysKit.aar
# （zip 结构见 _tools/plugin_build/aar/；没有 zip 命令就用 Python zipfile）
# 拷到 cet4_app/android/plugins/YysKit.aar，重跑 4.2
```

### 4.4 验签与体检（发布前必做）
```bash
cp 英眼书.apk yys_check.apk     # ← aapt 不认非 ASCII 文件名，必须先复制（见踩坑 6）
_tools/android-sdk/build-tools/35.0.0/aapt.exe dump badging yys_check.apk | grep -E "package:|sdkVersion"
# 期望：versionCode 30、versionName 0.9.17、sdkVersion:'24'
JAVA_HOME="C:\Users\s\Desktop\英语\_tools\jdk-17" \
  _tools/android-sdk/build-tools/35.0.0/apksigner.bat verify --print-certs yys_check.apk
# SHA-256 必须是 f4f3a884…，变了就停下来查原因，绝不能带新签名发布
```

### 4.4b 新机器上重建 android/build（本目录的 libs/ 与 src/ 不入库）
```bash
# 1) 从导出模板解出官方模板（路径按实际 Godot 版本目录调整）
unzip "%APPDATA%/Godot/export_templates/4.7.1.stable/android_source.zip" -d cet4_app/android/build
# 2) 应用本仓库已跟踪的定制：config.gradle / gradle-wrapper.properties / res/（git 检出即覆盖回定制版）
# 3) 补两个文件：android/.build_version（内容 4.7.1.stable）、android/build/.gdignore（空）
# 4) 解出 godot-lib 的 classes.jar 供插件编译（只编译插件时需要）：
#    从 android_source.zip 内的 godot-lib.*.aar 里取 classes.jar → _tools/plugin_build/godotlib/
```

### 4.5 版本号三处同步（漏一个就会显示不一致）
1. `cet4_app/scripts/db.gd` → `const VERSION := "0.9.17"`（应用内设置页/AI 上下文/更新弹窗读它）；
2. `cet4_app/export_presets.cfg` → `version/code`（单调 +1）、`version/name`；
3. `cet4_app/data/changelog.md` 顶部加条目（应用内更新日志页读它）；
4. `开发记录.md` 第 7 节版本表加一行（人类档案）。

---

## 5. 踩坑记录（现象 → 根因 → 修法）★ 本手册最有价值的一节

### 5.1 Gradle / 导出链

1. **「未在项目中安装 Android 构建模板」但模板明明在**
   - 根因：`export_presets.cfg` 里 `gradle_build/gradle_build_directory` 要填 `res://android`（父目录），Godot 自己再拼 `/build`。填成 `res://android/build` 它就去找 `…/build/build/build.gradle`。
   - 依据：源码 `platform/android/export/export_plugin.cpp` 该选项占位符就是 `res://android`。
2. **「尝试从自定义构建模板构建，但是它所使用的版本信息不存在」**
   - 根因：手动安装的构建模板缺 `android/.build_version`（构建目录的**父目录**下）。官方「项目 → 安装构建模板」会自动写，手动复制不会。
   - 修法：文件内容写 `4.7.1.stable`（= `GODOT_VERSION_FULL_CONFIG` = 版本号.状态，stable 无模块后缀）。官方安装器同时会在 `android/build/` 里放空文件 `.gdignore`——**也必须补**，否则编辑器会扫描模板目录并警告 "Detected another project.godot"。
3. **Manifest merger failed: Missing 'package' declaration in manifest（指向 YysKit.aar）**
   - 根因：新 AGP 强制 AAR 的 AndroidManifest.xml 根元素带 `package="…"`。
   - 修法：`<manifest … package="com.yys.kit">` 后重打 AAR。没有 zip 命令时用 Python `zipfile`（aar 结构：AndroidManifest.xml + classes.jar + 空 R.txt）。
4. **Godot v2 插件不生效**
   - 要件：AAR manifest 里 `<meta-data android:name="org.godotengine.plugin.v2.YysKit" android:value="com.yys.kit.YysKit"/>` + Java 类 `extends GodotPlugin`、方法加 `@UsedByGodot` + `.gdap` 的 config name 与 preset 里 `plugins/YysKit=true` 三处名字一致。
5. **headless 导出找不到 SDK / Java**
   - SDK 路径读的是**编辑器设置**（`%APPDATA%/Godot/editor_settings-4.tres` 里 `export/android/android_sdk_path`），不是环境变量；Java 走 `JAVA_HOME` 环境变量或编辑器设置 `export/android/java_sdk_path`。命令行导出时两个都要喂（见 4.2）。
6. **aapt dump badging 对中文文件名报错**
   - 根因：aapt 是老工具，非 ASCII 路径直接失败。修法：`cp 英眼书.apk yys_check.apk` 再查。
7. **TLS 拦截下的各种网络失败**
   - curl 加 `--ssl-no-revoke`；git 仓库本地配置 `http.sslVerify=false`；raw.githubusercontent.com 经常被断 → 用 gitee 镜像 `https://gitee.com/mirrors/godot/raw/<tag>/<path>` 拉 Godot 源码；Gradle 发行包下不动 → wrapper `distributionUrl=file:///…gradle-8.11.1-bin.zip`（Maven 依赖本身能下）。
8. **debug APK 体积**：双架构 libgodot.so 约 158MB 是体积大头（85%）。已开 `gradle_build/compress_native_libraries=true`（v0.9.18），包体 169MB→71MB；代价仅是安装时解压略慢，运行无感。还能再瘦的接口：裁 `architectures/armeabi-v7a`（-30MB，但失去 32 位老机，不建议）、boot splash 的 splash.png（3MB）转 webp、裁 classes.dex 里的 androidx（风险高不值得）。
9. **★最严重★ 内置词库根本没进 APK（关于页 单词 0 · 词组 0）**
   - 根因：Godot 4.7 把 `.md`/`.txt` 识别为 `TextFile` 资源类型，导出收集文件时显式跳过（`editor_export_platform.cpp::_export_find_resources` 里 `if type == "TextFile": continue`）。v0.9.14–0.9.17 所有安装包都没有词库。
   - 修法：`export_presets.cfg` 设 `include_filter="data/*.md, data/*.json"`（include 走真实文件系统 glob，不受 TextFile 跳过影响）。**任何运行时 FileAccess 读取的非导入文本都必须在这里登记**；验证方法：解 APK 取 `assets/assets.sparsepck`，扫字符串应见 data/words.md 等路径。
10. **`-s` 脚本模式下全局类编译早于 autoload 注册**
   - 现象：`--headless -s scripts/test_shots.gd` 报 "Identifier not found: DB"（widgets.gd 等 `class_name` 脚本），而无 class_name 的测试脚本正常。
   - 修法：需要加载真实场景/截图的测试改走场景运行——`godot --path . scenes/test_shots.tscn`（Node 脚本 + 单节点场景）。纯 DB 逻辑测试用 `-s` 没问题。
11. **弹窗挂错父节点被容器排版**：LanSyncDialog.open 曾 `parent.add_child(d)`，parent 是设置页 VBox → 弹窗被当成列表项挤到屏幕底部只露一条边。全幅弹窗一律挂 `get_tree().root`（UI.sheet 早就是这么做的）。

### 5.2 GDScript / 逻辑 bug

9. **lambda 按值捕获陷阱**：`parse_groups_md` 曾把"flush 当前组"写成闭包，闭包里拿到的是定义时的旧变量，新组名/新缓冲丢失 → 改成内联代码。**GDScript 的 Callable 捕获局部变量是按值快照，不是引用。**
10. **导出只有组头没有词条**：`_append_md_section` 建了 `by_group[g] = []` 却忘了 `by_group[g].append(it)`——测试「导出含词条」抓出来的。教训：**写完遍历组装逻辑，立刻跑往返测试**。
11. **覆盖导入把自己的旧词条挡住**：`import_groups_md` 覆盖模式必须先扫一遍组名、清空同名组的自定义词条，**再**解析写入；否则查重逻辑把刚要写入的词判成"已存在"。
12. **测试残留导致假失败**：测试在 `user://` 留下的自定义词条会参与判重，重跑同一测试可能失败。修法：测试组名带随机后缀，或先清 `user://custom_words.json`（Windows 实际路径用 `ProjectSettings.globalize_path("user://")` 查，通常在 `%APPDATA%\Godot\app_userdata\英眼书`）。

### 5.3 Android 平台行为

13. **蓝牙权限分代**：Android 12+（31+）要运行时申请 `BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN`；≤10 发现设备要 `ACCESS_FINE_LOCATION`（manifest 里加 `maxSdkVersion="30"` 避免新机多要权限）。YysKit 的 `bt_ensure_perms()` 已处理，但**运行时弹窗行为没真机验证过**（见第 9 节）。
14. **minSdk 真相**：godot-lib 4.7.1 AAR 内置 `minSdkVersion=24`。此前 legacy 导出即使 preset 写 21，成品 APK 实际也是 24。**平台底线就是 Android 7.0，别再往下承诺。**
15. **targetSdk 两个键**：`version/target_sdk_version`（preset 显示用）与 `gradle_build/target_sdk`（Gradle 构建实际用，空 = Godot 默认 36）不是同一个键，别只改一个就以为生效了。
16. **FileProvider 两套并存**：godot-lib 自带 androidx FileProvider（authority `${applicationId}.fileprovider`），YysKit 用零依赖自写的 `YysShareProvider`（authority `${applicationId}.yys_share`，只服务私有 share_cache）——避免引入 androidx 依赖，两者 authority 不同不冲突。

---

## 6. 测试体系（改代码前后各跑一遍）

全部 headless、无需手机、每个一分钟内跑完：

```bash
cd "<REPO>/cet4_app"
G="<GODOT>"   # 本机 Godot 4.7.1 编辑器 exe 路径
"$G" --headless --path . -s scripts/test_runner.gd        # 核心：词库/分组/星标/备份/回滚/会话（23 项）
"$G" --headless --path . -s scripts/test_import_parse.gd  # 导入解析器容错（23 项）
"$G" --headless --path . -s scripts/test_transfer.gd      # 互传 Markdown 往返/覆盖/删组（17 项）
"$G" --headless --path . -s scripts/test_lan.gd           # 互传协议：本机自连+2MB 载荷+拒绝路径（8 项）
# 看结果：grep -E "PASS|FAIL|fails="
```
- 新增测试：仿照任一 `test_*.gd`，`extends SceneTree`，`check("名称", 条件)`，结尾打印 `fails=N`。
- `test_touch_all.gd`：触控模拟（模拟手指按下/滑动/抬起遍历所有按钮），UI 大改后跑。
- **红线：改 db.gd 必跑 test_runner + test_transfer；改解析器必跑 test_import_parse。**

---

## 7. 常见修改食谱

| 需求 | 动手点 |
|---|---|
| 改内置词库 | 编辑 `data/words.md` / `phrases.md` → 跑 test_runner（会自动校验解析与计数） |
| 加设置开关 | `settings_view.gd` 加行 + `DB.settings` 读写 + 默认值在 `db.gd` `_default_settings()` |
| 加视图 | 新建 `xxx_view.gd`（仿 study_view）→ `main.gd` 注册路由 → `project.godot` 不用动 |
| 改互传协议 | `lan_sync.gd` + `YysKit.java` 蓝牙部分**必须同步改**（同一套字节协议）→ 跑 test_lan |
| 加插件方法 | `YysKit.java` 加 `@UsedByGodot` 方法 → 重编译 AAR（4.3）→ `share.gd` 或新封装脚本调用 |
| 改 UI 交互 | 只动 `widgets.gd` 工厂，让全应用一起生效；别在单个视图里造轮子 |
| AI 功能 | `ai_client.gd`（DeepSeek 兼容接口）；key 存设置，**永远不要把 key 写进仓库文件** |

---

## 8. 平台适配结论（用户问过，直接引用）

- **Android**：底线 Android 7.0（API 24，见踩坑 14）。armv7 + arm64 双架构包。
- **iOS**：Godot 4 支持导出，同一套代码可用；录音包直接可用，系统 TTS（AVSpeechSynthesizer）原生英文朗读质量好，**不需要**在线发音兜底。但打包签名必须 macOS + Xcode（Windows 做不了）；免费开发者账号 7 天有效签名，上架/TestFlight 需 $99/年。iOS 上没有 SAF/蓝牙 RFCOMM 这套，互传只能保留局域网通道，分享走 UIActivityViewController（需另写 iOS 插件）。
- **鸿蒙**：HarmonyOS NEXT（纯血）装不了 APK、Godot 无官方导出 → **暂不可行**；鸿蒙 4.x 及更早可装我们的 APK。
- **低配/60fps**：单场景显隐切换 + 固定行高列表 + QOA 音频 + 懒加载，已按 Android 7.0 老机目标设计；`project.godot` 渲染用 gl_compatibility。

---

## 9. 未验证清单（接手者第一件事：补真机验证）

| 功能 | 状态 |
|---|---|
| YysKit 蓝牙（权限弹窗、发现、RFCOMM 传输） | 只过了编译与单元级 GDScript 协议测试，**未真机** |
| 局域网互传两台真机 | 只本机自连测过 |
| 系统分享面板（分享到微信等） | manifest/provider 已验进 APK，**未真机点过** |
| 在线发音（有道接口） | curl 验证接口返回 mp3，**未真机** |
| release 包 | 从未打过（签名流程需另配 release keystore，且发布签名一旦定下不能再换） |

---

## 10. 给下一个 AI 的工作方式建议

1. **先跑四个测试再动手**，改完再跑一遍；红了就修到绿，不要带病提交。
2. 版本号守 0.9.x 规则；签名指纹 `f4f3a884…` 是生命线。
3. 别把 `_tools/` 大文件（JDK/SDK/gradle zip，共 2GB+）推上 GitHub；`_tools/plugin_src/` 是源码必须入库。
4. 用户沟通偏好：中文、全角标点、先做出来再迭代、版本未官宣都是 0.9.x、改动要在 `data/changelog.md`（应用内可见）和 `开发记录.md`（档案）双记。
5. 用户是学生向个人开发者，方案选型优先级：**免服务器 > 离线可用 > 包体小 > 音质/动画精致**。凡是需要花钱 API、架服务器、NAS 的方案，先给替代再让他选。
6. 本机网络有 TLS 拦截，任何下载失败先想到踩坑 7。
