# Drinking Project

Drinking Project 是一个本地 macOS 喝水提醒 App。它默认使用 Mac 本地系统时间，在每天 08:00 到 22:00 之间每 30 分钟提醒一次，包括 22:00。

This public version does not include private video or image assets. Add your own local media under `视频/视频素材/` after cloning.

## 功能

- 菜单栏常驻入口，标题为“水”
- 原创蓝色水滴 App 图标，用于 Finder、Dock 和 Launchpad 中的 `.app` 展示
- 基础 SwiftUI 管理窗口：总览、提醒规则、视频库、设置
- 总览会显示今日提醒次数、今日完成次数、完成率、最近完成时间和可播放视频数
- 提醒规则本地 CRUD：新增、查看、修改、删除、启用或停用规则
- 视频引用本地 CRUD：添加本地视频或文件夹引用、扫描、启用或停用、移除引用但不删除原文件
- 视频库可以一键打开默认素材文件夹 `视频/视频素材/`
- 视频库会显示候选数、可播放数、不可播放文件名，以及缺失或外接硬盘未连接的引用
- 设置本地管理：播放模式、提醒音量、今日暂停、轻松测试模式、恢复默认设置
- 使用 Application Support 下的 JSON 文件保存本地规则、视频引用、设置和提醒状态
- 如果本地 JSON 损坏，App 会先备份为 `.corrupt-时间戳` 文件，再恢复默认值，避免启动崩溃
- 自动扫描 `视频/视频素材/` 和兼容扫描 `视频/` 第一层中的 `.mp4`、`.mov`、`.m4v`
- 自动忽略 macOS 的 `._` 元数据文件
- 每次提醒都会重新扫描本地视频，并随机选择一个可播放视频
- 支持“播完换下一个”和“单条循环”两种播放模式
- 视频全屏铺底显示，网页 HUD 只负责视觉和点击消息
- 提醒弹出前会尝试暂停常见后台媒体来源，例如浏览器视频、音乐、播客、网易云音乐和常见播放器
- 提醒弹出时打开视频声音，并把 macOS 输出音量设为设置里的提醒音量，默认 15%
- 外接显示器时会覆盖所有屏幕；主屏幕显示确认按钮，其他屏幕同步显示视频和进度
- 沉浸式置顶全屏窗口
- 30 秒内不显示确认按钮，并拦截 Esc、Command+W 等普通关闭方式
- `Command + Q` 保留为紧急退出后门；如果提醒窗口异常卡住，可以直接退出程序
- 30 秒后启用“已饮水”按钮
- 必须点击“已饮水”3 次才能关闭
- 每次点击之间必须间隔至少 5 秒
- 支持“今日暂停”和“重新开启今日提醒”
- 设置页可以真实安装、加载或移除用户级 LaunchAgent，用于开机自动运行
- 菜单栏会显示当前状态、下次提醒和可播放视频数；今日暂停时标题会变成“水⏸”，提醒中会变成“水!”

macOS 强制退出仍然保留为最后后门。

## 如何运行

最简单的方法是双击项目根目录里的：

```text
开启 Drinking Project.command
```

它会自动编译并启动程序。启动后，菜单栏会出现“水”。

如果项目已经在运行，再次双击开启文件会弹窗提示“该项目已在运行中”，不会重复启动。

也可以在终端运行：

```zsh
cd "/path/to/Drinking Project"
bash ./script/build_and_run.sh
```

脚本会编译 Swift/AppKit/SwiftUI 源码，生成：

```text
dist/Drinking Project.app
```

然后以普通 macOS `.app` bundle 方式启动。Codex 桌面环境也可以使用 `.codex/environments/environment.toml` 里的 Run action。

底层构建入口是：

```zsh
bash ./script/build_and_run.sh
```

## 如何关闭

双击项目根目录里的：

```text
关闭 Drinking Project.command
```

这会关闭当前正在运行的 Drinking Project。如果之前安装过 LaunchAgent，它也会先停止本次登录会话中的后台启动项，避免刚关掉又被系统拉起。

## 如何设置开机启动

打开管理窗口，进入“设置”，开启“开机自动运行”。设置页会显示真实的 LaunchAgent 状态和 plist 路径：

```text
~/Library/LaunchAgents/com.local.drinkingproject.plist
```

如果你更喜欢脚本，也可以运行：

```zsh
cd "/path/to/Drinking Project"
bash ./script/build_and_run.sh --build-only
zsh ./scripts/install_launch_agent.sh
```

如果以后想取消开机启动：

```zsh
cd "/path/to/Drinking Project"
zsh ./scripts/uninstall_launch_agent.sh
```

## 如何添加或替换视频

把新视频放进：

```text
视频/视频素材/
```

支持格式：

```text
mp4, mov, m4v
```

程序每次提醒前都会优先扫描 `视频/视频素材/`，并兼容扫描 `视频/` 第一层。管理窗口里的“视频库”也可以添加额外的本地视频或文件夹引用。移除引用只会从 App 的本地列表删除，不会删除用户原始媒体文件。

如果外接硬盘断开，或引用路径已经不存在，视频库会把该引用显示为不可用。重新连接硬盘后，点击“扫描视频”或对应文件夹的“重新扫描”即可刷新。

管理窗口的“视频库”页也可以点击“打开素材文件夹”，直接在 Finder 打开默认素材目录。

为了保护隐私，仓库里的 `.gitignore` 会默认排除 `视频/` 下的真实视频、图片和音频文件，只保留占位说明。

GitHub 版本只保留：

```text
视频/README.md
视频/视频素材/README.md
视频/视频素材/.gitkeep
```

不应该提交任何实际视频文件。

## 如何暂停或重新开启

点击菜单栏“水”：

- `今日暂停`：当天剩余提醒全部暂停
- `重新开启今日提醒`：当天恢复提醒
- `开启提醒`：确保提醒功能处于开启状态

今日暂停只影响当天。第二天会自动恢复，除非你关闭了提醒进程或取消开机启动。

## 如何测试提醒窗口

双击项目根目录里的：

```text
测试 Drinking Project.command
```

它会立刻打开一次提醒窗口，不需要等到半点。

也可以点击菜单栏“水”，选择：

```text
手动测试提醒窗口
```

默认情况下，测试窗口和正式提醒窗口使用同一套规则：30 秒等待、3 次确认、每次间隔 5 秒。

## 个人玩法 / 快速测试

如果今天只是想看一下效果，可以打开管理窗口，在“总览”或“设置”里开启“轻松测试模式”，然后点击“轻松测试提醒”或菜单栏里的“手动测试提醒窗口”。

轻松测试模式只影响手动测试提醒，不影响正式定时提醒。开启后，手动测试会临时使用：

- 约 3 秒等待
- 1 次确认
- 约 1 秒点击冷却

正式定时提醒仍然使用你在“提醒规则”里设置的真实等待时间、确认次数和冷却时间。

玩法建议：

- 把喜欢的 `mp4`、`mov` 或 `m4v` 放到 `视频/视频素材/`
- 在“视频库”里点“扫描视频”
- 在“总览”看今日提醒次数、今日完成次数和最近完成时间
- 需要安静一天时，在菜单栏或设置页点“今日暂停”

这个项目默认保持本地-only：规则、视频引用、设置和历史都保存在本机 JSON，仓库不包含你的个人视频素材。

## 提醒窗口界面层

提醒窗口的强制逻辑仍由 Swift/AppKit 控制，包括全屏置顶、视频播放、30 秒等待、3 次确认、5 秒点击间隔和 `Command + Q` 紧急退出。

当前 v2 界面使用 `WKWebView` 加载 bundle 内资源：

```text
Sources/DrinkingProject/WebResources/ReminderWeb/index.html
```

构建脚本会把它复制到：

```text
dist/Drinking Project.app/Contents/Resources/WebResources/ReminderWeb/
```

HTML/CSS/JS 只负责视频上的 HUD 视觉、倒计时展示和点击消息发送；最终确认逻辑仍以 Swift/AppKit 状态为准。如果没有找到可播放视频，界面会提示检查 `视频/视频素材/`。

旧的 `Test /ReminderWeb/` 仍保留为历史测试来源和兼容入口；注意 `Test ` 目录名末尾带一个空格。

## 本地数据

MVP 使用 JSON 文件保存本地状态，位置在：

```text
~/Library/Application Support/Drinking Project/
```

包括：

```text
reminder-rules.json
video-library.json
settings.json
history.json
```

这些是用户本机数据，不需要提交到 GitHub。

## 提醒时间

每天按本地系统时间提醒：

```text
08:00, 08:30, 09:00, 09:30, ..., 21:30, 22:00
```

22:30 不会提醒。

如果多个启用规则在同一分钟同时匹配，只会触发列表中靠前的第一个规则。跨夜规则也支持，例如 22:00 到第二天 02:00。

## 本地 QA

开发或提交 PR 前可以运行：

```zsh
cd "/path/to/Drinking Project"
bash ./script/build_and_run.sh --qa
```

这个命令会检查：

- `Sources/DrinkingProject/WebResources/ReminderWeb/app.js` 语法
- `Test /ReminderWeb/app.js` 语法
- 是否有真实视频、图片或音频文件被 Git 跟踪或暂存
- macOS `.app` 构建
- `Info.plist` 格式
- JSON 持久化、坏 JSON 备份、默认提醒规则和跨夜规则边界

也可以单独运行：

```zsh
bash ./script/build_and_run.sh --build-only
bash ./script/build_and_run.sh --verify
bash ./script/build_and_run.sh --self-test-persistence
bash ./script/build_and_run.sh --media-privacy-check
```

## 常见恢复方法

- 找不到视频：先确认 `视频/视频素材/` 里有 `mp4`、`mov` 或 `m4v`，再点“视频库”里的“扫描视频”。
- 外接硬盘视频不可用：重新连接硬盘后再扫描；路径如果仍显示不可用，删除旧引用后重新添加文件夹。
- 提醒窗口卡住：按 `Command + Q` 退出，这是保留的紧急出口。
- 本地设置异常：检查 `~/Library/Application Support/Drinking Project/`，损坏 JSON 会保留 `.corrupt-时间戳` 备份。
- 开机启动异常：在“设置”里刷新开机启动状态，或删除 `~/Library/LaunchAgents/com.local.drinkingproject.plist` 后重新开启。
