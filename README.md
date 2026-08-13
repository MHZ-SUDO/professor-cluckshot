# Professor Cluckshot

Professor Cluckshot is a basketball-loving research chicken for the Codex desktop app. He animates as a Codex v2 pet and occasionally drops a random thesis pep talk, a useful reminder, or a light meme.

鸡哥现在有了英文艺名 `Professor Cluckshot`。它会在 Codex 桌面端活动，也会随机说一些论文鼓励、实验提醒、篮球梗和轻松调侃。

## What it includes

- A Codex v2 animated pet package with an 8 × 11, 1536 × 2288 WebP atlas
- 243 hand-written Chinese lines
- Dynamic sentence generation with more than 52,000 valid combinations
- Automatic speech every 3–7 minutes by default
- Click, hover, and drag reactions near the pet
- A Windows input bridge that restores clicks on the voice and collapse buttons when the Codex pet overlay is temporarily click-through
- Recent-line avoidance so the same phrases do not repeat too often
- A compact click-through speech bubble that does not block the Codex controls
- No chat box and no external AI or API dependency

The dialogue style intentionally avoids colons and sentence-ending periods so the lines feel more like natural conversation.

## Requirements

- Windows 10 or 11
- Codex desktop app with custom pet support
- Windows PowerShell 5.1
- .NET Framework WPF support, included with normal Windows installations

The speech overlay and input bridge use WPF and Win32 window detection, so those optional features are Windows-only. The pet artwork itself can still be used anywhere that supports the Codex v2 pet format.

## Install

Open Windows PowerShell and run:

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$petPath = Join-Path $codexHome 'pets\professor-cluckshot'
git clone https://github.com/MHZ-SUDO/professor-cluckshot.git $petPath
Set-Location $petPath
Get-ChildItem -Filter *.ps1 | Unblock-File
.\Start-PaperCheer.ps1
```

Refresh the Codex pet list, then select **Professor Cluckshot** in the pet settings. A Codex restart is normally unnecessary.

If the destination folder already exists, update it instead of cloning again:

```powershell
Set-Location $petPath
.\Stop-PaperCheer.ps1
git pull
Get-ChildItem -Filter *.ps1 | Unblock-File
.\Start-PaperCheer.ps1
```

The final command starts both required Windows helpers:

- `inputBridge` wakes the Codex pet overlay when the pointer reaches the pet, so the voice and collapse buttons can receive clicks.
- `speechOverlay` provides the random dialogue bubble and click, hover, and drag reactions.

Windows does not automatically execute PowerShell scripts downloaded from GitHub. Run `Start-PaperCheer.ps1` once after each Windows sign-in if you want the dialogue and input repair active for that session.

## Verify the repair

The start command returns JSON containing both `inputBridge.processId` and `speechOverlay.processId`. Then verify speech without waiting for the random timer:

```powershell
.\Show-PaperCheer.ps1 -Trigger click -VisibleSeconds 15
```

You should see a speech bubble above the pet. Move the pointer onto the two round controls and confirm that the voice button and downward arrow are clickable with a single click.

For a read-only bridge probe:

```powershell
.\CodexPetInputBridge.ps1 -ProbeOnly
```

`overlayFound` should be `true` while the Codex pet is visible. The bridge keeps searching if Codex is opened after the helper starts or if the pet overlay is recreated.

## Use

Start the input repair and random dialogue overlay:

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

Stop both helpers:

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
- `CodexPetInputBridge.ps1` repairs pointer delivery to the Codex pet overlay
- `PaperCheerOverlay.ps1` provides the speech bubble and interaction detection
- `Start-PaperCheer.ps1`, `Stop-PaperCheer.ps1`, and `Show-PaperCheer.ps1` control the helpers
- `say-paper-cheer.ps1` and `watch-paper-cheer.ps1` are compatibility helpers for other local pet runtimes

## Notes

Codex reads the pet manifest and spritesheet, while the optional PowerShell helpers supply custom dialogue, interaction detection, and the click-through workaround. They do not modify the Codex installation and do not restart Codex.

The helpers write small runtime state files beside the scripts. They are ignored by Git.

## License

The source code, dialogue data, and documentation are released under the MIT License.

The included character artwork is not covered by the MIT License. See [ASSET_NOTICE.md](ASSET_NOTICE.md) before reusing or redistributing the spritesheet.
