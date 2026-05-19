# Drinking Project

Drinking Project 是一个本地 macOS 喝水提醒小工具。它使用 MacBook 本地系统时间，在每天 08:00 到 22:00 之间每 30 分钟提醒一次，包括 22:00。

This public version does not include private video or image assets. Add your own local media under `视频/` after cloning.

## 功能

- 菜单栏常驻入口，标题为“水”
- 自动扫描 `视频` 文件夹中的 `.mp4`、`.mov`、`.m4v`
- 自动忽略 macOS 的 `._` 元数据文件
- 每次提醒都会重新扫描 `视频` 文件夹，并随机选择一个可播放视频
- 视频居中显示，保持原始比例和原始尺寸；如果视频大于屏幕，才会按比例缩小
- 提醒弹出前会尝试暂停常见后台媒体来源，例如浏览器视频、音乐、播客、网易云音乐和常见播放器
- 提醒弹出时打开视频声音，并把 macOS 输出音量设为 15%
- 外接显示器时会覆盖所有屏幕；主屏幕显示确认按钮，其他屏幕同步显示视频和进度
- 沉浸式置顶全屏窗口
- 30 秒内不显示确认按钮，并拦截 Esc、Command+W 等普通关闭方式
- `Command + Q` 保留为紧急退出后门；如果提醒窗口异常卡住，可以直接退出程序
- 30 秒后启用“已饮水”按钮
- 必须点击“已饮水”3 次才能关闭
- 每次点击之间必须间隔至少 5 秒
- 支持“今日暂停”和“重新开启今日提醒”
- 可设置开机自动运行

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
chmod +x scripts/*.sh
./scripts/run.sh
```

脚本会先编译本地 Swift/AppKit 程序，然后启动它。可以通过菜单栏测试提醒窗口。

## 如何关闭

双击项目根目录里的：

```text
关闭 Drinking Project.command
```

这会关闭当前正在运行的 Drinking Project。如果之前安装过 LaunchAgent，它也会先停止本次登录会话中的后台启动项，避免刚关掉又被系统拉起。

## 如何设置开机启动

运行：

```zsh
cd "/path/to/Drinking Project"
chmod +x scripts/*.sh
./scripts/install_launch_agent.sh
```

这会构建 release 版本，并安装用户级 LaunchAgent：

```text
~/Library/LaunchAgents/com.local.drinkingproject.plist
```

如果以后想取消开机启动：

```zsh
cd "/path/to/Drinking Project"
./scripts/uninstall_launch_agent.sh
```

## 如何添加或替换视频

把新视频放进：

```text
视频/
```

支持格式：

```text
mp4, mov, m4v
```

程序每次提醒前都会重新扫描这个文件夹，所以后续新增视频后不需要改代码，也不需要重新告诉 Codex。只要文件格式支持，它就会自动进入随机播放池。

为了保护隐私，仓库里的 `.gitignore` 会默认排除 `视频/` 下的真实视频、图片和音频文件，只保留占位说明。

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

测试窗口和正式提醒窗口使用同一套规则：30 秒等待、3 次确认、每次间隔 5 秒。

## 提醒时间

每天按本地系统时间提醒：

```text
08:00, 08:30, 09:00, 09:30, ..., 21:30, 22:00
```

22:30 不会提醒。
