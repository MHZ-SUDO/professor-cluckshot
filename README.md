# 鸡哥 Professor Cluckshot

> 本页默认使用简体中文，安装与排障命令适用于 Windows。

## 中文简介

Professor Cluckshot（鸡哥）是 Codex 桌面端的陪伴宠物。它包含完整的 Codex v2 动画、中文随机台词、点击/悬停/拖动反馈，以及 Windows 下的圆形按钮点击修复。

<details>
<summary>English introduction</summary>

Professor Cluckshot is a basketball-loving companion for the Codex desktop app, with a v2 animation atlas, a varied collection of Chinese dialogue, and Windows runtime helpers.

</details>

## 功能

- Codex v2 宠物包：8 × 11、1536 × 2288、RGBA WebP
- 3,305 条中文台词，涵盖人生感悟、哲理、励志、幽默、温柔陪伴、淡淡惆怅、中外诗句和网络常见语
- 默认每 3–7 分钟随机说话
- 点击、悬停和拖动反馈
- 单击鸡哥触发说话；本地点击接收层避免把单击交给 Codex 主窗口
- 拖动超过原生阈值后，按实时鼠标位置持续更新鸡哥位置
- 修复语音按钮与收回箭头点击穿透
- 说话气泡使用原生屏幕坐标贴近宠物，适配缩放和多显示器
- 气泡始终位于鸡哥后方，不会遮住角色动画
- 一键安装、登录自启动、状态诊断和卸载
- 不依赖外部 AI、API 或聊天框

## 为什么按钮会点不了

问题不在 `pet.json` 或精灵图。部分 Windows Codex 版本把宠物放在同时具有 `WS_EX_TRANSPARENT` 和 `WS_EX_LAYERED` 的顶层窗口中。按钮虽然显示在最上层，Windows 却可能把点击交给后面的 Edge、桌面或其他窗口。

输入助手在鸡哥人物区域放置一个几乎不可见、不会激活的点击接收层。单击由它触发说话；拖拽越过阈值时，助手向鸡哥原生窗口交付按下和移动，随后按约 16 毫秒间隔转发最新鼠标位置，让后台窗口也能连续跟随。按钮区域保持原有点击方式。遇到覆盖鸡哥的截图选区等窗口，接收层会避让；助手不修改 Codex 安装文件。

## 当前版本：1.2.31

2026-10-26 更新台词库：保留古诗词原句，增加外国诗与哲理短句的中文自译或节译，并关闭旧的自动拼句。每条台词可以单独表达一种风格，也可以自然混合。可直接查看 [分类浏览版](鸡哥词库_分类浏览.txt)；作品作者、来源和译文说明保存在 `paper-cheer-dialogue.json` 的 `source` 字段中。

1.2.31 修正后台监听的线程模式及自动恢复参数，改进界面读取，并减少相同点击区域的重复重建，处理长时间运行时的内存增长。单击说话、拖动跟随和独立按钮的行为保持不变，运行助手仍保持独立后台启动。

已验证连续 6,000 次界面读取的内存稳定性、人物和按钮范围一致性，以及输入和说话逻辑回归。全天连续运行、跨屏切换与第三方截图软件配合仍需实际使用验证。具体变更见 [CHANGELOG.md](CHANGELOG.md)。

## 系统要求

- Windows 10 或 Windows 11
- 支持自定义宠物的 Codex 桌面端
- Windows PowerShell 5.1
- 系统自带的 .NET Framework/WPF

宠物精灵图本身可以用于任何支持 Codex v2 宠物格式的平台；说话和按钮修复助手目前仅支持 Windows。

## 推荐安装方式

克隆仓库或下载并解压 GitHub ZIP，然后在该文件夹打开 Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ProfessorCluckshot.ps1
```

安装器会自动：

1. 检测 `$env:CODEX_HOME`；未设置时使用 `$env:USERPROFILE\.codex`
2. 安装到 `pets\professor-cluckshot`
3. 解除 PowerShell 文件下载锁定
4. 启动输入桥和说话助手
5. 在当前用户启动文件夹注册登录自启动

不需要管理员权限，也不会重启 Codex。安装后刷新宠物列表并选择 **Professor Cluckshot**。

如果不希望登录自启动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ProfessorCluckshot.ps1 -NoStartup
```

## 更新

在仓库目录更新后重新运行安装器即可；安装器会先安全停止旧助手，再覆盖运行文件并重新启动：

仓库当前的助手版本为 1.2.31。如果本机安装了更新的助手版本，重新运行本仓库安装器会覆盖该版本；只更新台词时，可先备份并替换已安装目录中的 `paper-cheer-dialogue.json`，然后重启说话助手。

```powershell
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ProfessorCluckshot.ps1
```

## 状态诊断

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$petPath = Join-Path $codexHome 'pets\professor-cluckshot'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $petPath 'Get-PaperCheerStatus.ps1')
```

重点结果：

- `manifestValid: true`
- `spriteExists: true`
- `inputBridgeRunning: true`
- `speechOverlayRunning: true`
- `startupRegistered: true`
- 宠物可见时 `overlayProbe.overlayFound: true`

立即测试说话：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $petPath 'Show-PaperCheer.ps1') -Trigger click -VisibleSeconds 15
```

## 手动控制

```powershell
# 启动按钮修复和说话助手
.\Start-PaperCheer.ps1

# 停止两个助手
.\Stop-PaperCheer.ps1

# 自定义随机说话间隔
.\Start-PaperCheer.ps1 -MinIntervalSeconds 120 -MaxIntervalSeconds 360

# 只读检查宠物覆盖层
.\CodexPetInputBridge.ps1 -ProbeOnly
```

支持的说话触发器：`random`、`start`、`thinking`、`running`、`reviewing`、`waiting`、`success`、`failure`、`idle`、`click`、`hover` 和 `drag`。

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $petPath 'Uninstall-ProfessorCluckshot.ps1')
```

卸载器会停止两个助手、删除登录自启动入口并删除该独立宠物目录，不会影响其他宠物或 Codex。

仅取消自启动并保留文件时，可以重新运行安装器并传入 `-NoStartup`；或者运行卸载器时使用 `-KeepFiles`。

## 主要文件

- `pet.json`：Codex v2 宠物清单
- `spritesheet.webp`：8 × 11 动画图集
- `CodexPetInputBridge.ps1`：圆形按钮和宠物输入修复
- `PaperCheerOverlay.ps1`：说话气泡和交互检测
- `Install-ProfessorCluckshot.ps1`：安装、升级、自启动和启动
- `Get-PaperCheerStatus.ps1`：只读状态诊断
- `Uninstall-ProfessorCluckshot.ps1`：停止、取消自启动和卸载
- `Start-PaperCheer.ps1` / `Stop-PaperCheer.ps1`：运行控制
- `paper-cheer-dialogue.json`：分类台词及部分作品的来源记录
- `鸡哥词库_分类浏览.txt`：按风格整理的台词浏览版

## 说明

Codex 原生读取 `pet.json` 和 `spritesheet.webp`。说话与 Windows 点击修复由独立 PowerShell 助手提供；它们只修改宠物窗口的临时运行样式，不修改 Codex 安装文件。

运行时会在宠物目录写入少量 PID、状态和命令文件，这些文件已被 Git 忽略。

## License

代码和本项目原创内容使用 MIT License。引用的古诗、外国作品及网络短句的来源见台词库记录，相关原作或引用内容的权利应分别确认。角色图像不包含在 MIT 授权中；重用或再分发精灵图前请阅读 [ASSET_NOTICE.md](ASSET_NOTICE.md)。
