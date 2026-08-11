# Professor Cluckshot

Professor Cluckshot is a basketball-loving research chicken for the Codex desktop app. He animates as a Codex v2 pet and occasionally drops a random thesis pep talk, a useful reminder, or a light meme.

鸡哥现在有了英文艺名 `Professor Cluckshot`。它会在 Codex 桌面端活动，也会随机说一些论文鼓励、实验提醒、篮球梗和轻松调侃。

## What it includes

- A Codex v2 animated pet package with an 8 × 11, 1536 × 2288 WebP atlas
- 243 hand-written Chinese lines
- Dynamic sentence generation with more than 52,000 valid combinations
- Automatic speech every 3–7 minutes by default
- Click, hover, and drag reactions near the pet
- Recent-line avoidance so the same phrases do not repeat too often
- A compact click-through speech bubble that does not block the Codex controls
- No chat box and no external AI or API dependency

The dialogue style intentionally avoids colons and sentence-ending periods so the lines feel more like natural conversation.

## Requirements

- Windows 10 or 11
- Codex desktop app with custom pet support
- Windows PowerShell 5.1
- .NET Framework WPF support, included with normal Windows installations

The speech overlay currently uses WPF and Win32 window detection, so it is Windows-only. The pet artwork itself can still be used anywhere that supports the Codex v2 pet format.

## Install

Open Windows PowerShell and run:

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$petPath = Join-Path $codexHome 'pets\professor-cluckshot'
git clone https://github.com/MHZ-SUDO/professor-cluckshot.git $petPath
Set-Location $petPath
.\Start-PaperCheer.ps1
```

Restart or refresh Codex, then select **Professor Cluckshot** in the pet settings.

If the destination folder already exists, update it instead of cloning again:

```powershell
Set-Location $petPath
git pull
.\Stop-PaperCheer.ps1
.\Start-PaperCheer.ps1
```

## Use

Start the random dialogue overlay:

```powershell
.\Start-PaperCheer.ps1
```

Make Professor Cluckshot speak immediately:

```powershell
.\Show-PaperCheer.ps1 -VisibleSeconds 15
```

Trigger a particular mood:

```powershell
.\Show-PaperCheer.ps1 -Trigger reviewing -VisibleSeconds 15
.\Show-PaperCheer.ps1 -Trigger success -VisibleSeconds 15
.\Show-PaperCheer.ps1 -Trigger failure -VisibleSeconds 15
```

Supported triggers are `random`, `start`, `thinking`, `running`, `reviewing`, `waiting`, `success`, `failure`, `idle`, `click`, `hover`, and `drag`.

Stop the overlay:

```powershell
.\Stop-PaperCheer.ps1
```

Change the automatic interval, in seconds:

```powershell
.\Start-PaperCheer.ps1 -MinIntervalSeconds 120 -MaxIntervalSeconds 360
```

## Files

- `pet.json` defines the Codex v2 pet and optional animation chains
- `spritesheet.webp` contains the animation atlas
- `paper-cheer-dialogue.json` contains the fixed dialogue and generation templates
- `PaperCheerOverlay.ps1` provides the speech bubble and interaction detection
- `Start-PaperCheer.ps1`, `Stop-PaperCheer.ps1`, and `Show-PaperCheer.ps1` control the overlay
- `say-paper-cheer.ps1` and `watch-paper-cheer.ps1` are compatibility helpers for other local pet runtimes

## Notes

Codex currently reads the pet manifest and spritesheet, while the optional PowerShell sidecar supplies custom dialogue and interaction detection. The sidecar does not modify the Codex installation.

The overlay writes small runtime state files beside the scripts. They are ignored by Git.

## License

The source code, dialogue data, and documentation are released under the MIT License.

The included character artwork is not covered by the MIT License. See [ASSET_NOTICE.md](ASSET_NOTICE.md) before reusing or redistributing the spritesheet.

