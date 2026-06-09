# OpenLess for iOS

OpenLess 的 iOS 端：一个以**语音输入**为核心的第三方输入法。按住语音键说话，云端 ASR 转写 + LLM 润色后直接落到光标处；并能同步使用云端**风格包市场**。

> 与桌面端（`../openless-all/`）独立工程，仅共用同一套数据模型约定与同一个风格包市场后端。

## 关键架构约束（务必先读）

- **iOS 键盘扩展无法访问麦克风**（苹果硬限制，开 Full Access 也不行）。因此语音录制必须在**主 App** 内完成。
- 语音闭环：键盘语音键 → `openless://` 跳主 App（或 Phase 5 的后台常驻会话免跳转）→ 录音 → ASR → 润色 → 结果写入 **App Group** 共享容器 → 键盘用 `textDocumentProxy` 插入。
- 三个 target：
  - `OpenLess`（主 App，SwiftUI）
  - `OpenLessKeyboard`（键盘扩展，app-extension）
  - `OpenLessShared`（共享框架：数据模型 / 存储 / ASR&润色客户端）
- App Group：`group.top.openless.ios`

## 前置依赖

- **完整 Xcode.app**（不是 Command Line Tools）+ iOS 模拟器运行时。
- [XcodeGen](https://github.com/yonyz/XcodeGen)：`brew install xcodegen`

## 构建与运行（模拟器优先）

```bash
cd 1-app/openless-ios
xcodegen generate                 # project.yml → OpenLess.xcodeproj
open OpenLess.xcodeproj            # 用 Xcode 打开，选 iPhone 模拟器运行

# 或命令行编译（模拟器，无需签名）
xcodebuild -scheme OpenLess \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath build build
```

启用键盘：模拟器里 **设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → OpenLess 键盘**，并开启「允许完全访问」。

## 工程约定

- 只提交 `project.yml` 与源码；`OpenLess.xcodeproj` 由 XcodeGen 生成，不入库（见 `.gitignore`）。
- 数据模型对齐桌面 `src-tauri/src/types.rs`、`persistence.rs`，JSON 一律 camelCase。
- 凭据存 Keychain，结构沿用桌面 `CredsRoot`。

## 进度（分阶段交付，每阶段可在模拟器跑起来）

- [x] **Phase 0** 工程骨架（3 target 可生成，最小可用键盘 + 首页引导）
- [ ] **Phase 1** 共享数据模型 + 存储（Keychain 凭据、round-trip 单测）
- [ ] **Phase 2** 云端 ASR（Volcengine/Bailian/Whisper）+ 润色客户端
- [ ] **Phase 3** 语音闭环（跳转模式）
- [ ] **Phase 4** 完整键盘 + 拼音引擎
- [ ] **Phase 5** 免跳转后台会话 + 悬浮控件
- [ ] **Phase 6** 云端风格包市场（拉取 / 安装）
- [ ] **Phase 7** 设置 / 配置录入 / 收尾打磨
