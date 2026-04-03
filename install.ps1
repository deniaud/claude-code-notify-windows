# install.ps1 — Automated installer for claude-code-notify hooks (Windows).
# Downloads notification scripts and configures Claude Code settings.json.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# 1. Header
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Installing claude-code-notify-windows..." -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# 2. Create hooks directory
# ---------------------------------------------------------------------------
$hooksDir = Join-Path $env:USERPROFILE ".claude\hooks"

if (-not (Test-Path $hooksDir)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    Write-Host "[+] Created hooks directory: $hooksDir" -ForegroundColor Green
} else {
    Write-Host "[=] Hooks directory already exists: $hooksDir" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. Download hook scripts from GitHub
# ---------------------------------------------------------------------------
$baseUrl = "https://raw.githubusercontent.com/deniaud/claude-code-notify-windows/main"
$files = @(
    @{ Name = "notify.ps1";            Url = "$baseUrl/notify.ps1" },
    @{ Name = "notify-permission.ps1"; Url = "$baseUrl/notify-permission.ps1" }
)

foreach ($file in $files) {
    $dest = Join-Path $hooksDir $file.Name
    Write-Host "[*] Downloading $($file.Name)..." -ForegroundColor Yellow -NoNewline

    try {
        Invoke-WebRequest -Uri $file.Url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Installation aborted. Check your internet connection and try again." -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 4. Read or create settings.json
# ---------------------------------------------------------------------------
$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"

if (Test-Path $settingsPath) {
    $settingsRaw = Get-Content $settingsPath -Raw -Encoding UTF8
    # Handle empty file
    if ([string]::IsNullOrWhiteSpace($settingsRaw)) {
        $settings = @{}
    } else {
        $settings = $settingsRaw | ConvertFrom-Json
    }
    Write-Host "[=] Loaded existing settings: $settingsPath" -ForegroundColor DarkGray

    # Back up existing settings
    $backupPath = "$settingsPath.bak"
    Copy-Item -Path $settingsPath -Destination $backupPath -Force
    Write-Host "[+] Backed up settings to: $backupPath" -ForegroundColor Green
} else {
    $settings = @{}
    Write-Host "[+] No existing settings.json found; will create one." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 5. Build the hooks configuration to merge
# ---------------------------------------------------------------------------
$notifyCommand     = 'powershell -NoProfile -WindowStyle Hidden -File $HOME/.claude/hooks/notify.ps1'
$permissionCommand = 'powershell -NoProfile -File $HOME/.claude/hooks/notify-permission.ps1'

$notificationEntry = @{
    matcher = ""
    hooks   = @(
        @{ type = "command"; command = $notifyCommand }
    )
}

$permissionEntry = @{
    matcher = ""
    hooks   = @(
        @{ type = "command"; command = $permissionCommand }
    )
}

$stopEntry = @{
    matcher = ""
    hooks   = @(
        @{ type = "command"; command = $notifyCommand }
    )
}

# ---------------------------------------------------------------------------
# 6. Merge hooks into settings (preserve existing hooks)
# ---------------------------------------------------------------------------

# Convert PSCustomObject to hashtable if needed (ConvertFrom-Json returns PSCustomObject)
function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline)] $InputObject)
    if ($InputObject -is [System.Collections.Hashtable]) {
        return $InputObject
    }
    $ht = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $ht[$prop.Name] = $prop.Value
    }
    return $ht
}

$settings = $settings | ConvertTo-Hashtable

if (-not $settings.ContainsKey("hooks")) {
    $settings["hooks"] = @{}
}

$hooks = $settings["hooks"]
if ($hooks -isnot [System.Collections.Hashtable]) {
    $hooks = $hooks | ConvertTo-Hashtable
}

# Merge Notification hooks
if ($hooks.ContainsKey("Notification")) {
    $existing = @($hooks["Notification"])
    # Check if our entry already exists (same command)
    $alreadyPresent = $false
    foreach ($entry in $existing) {
        foreach ($h in @($entry.hooks)) {
            if ($h.command -eq $notifyCommand) {
                $alreadyPresent = $true
                break
            }
        }
        if ($alreadyPresent) { break }
    }
    if (-not $alreadyPresent) {
        $hooks["Notification"] = @($existing) + @($notificationEntry)
        Write-Host "[+] Added Notification hook (merged with existing)" -ForegroundColor Green
    } else {
        Write-Host "[=] Notification hook already configured" -ForegroundColor DarkGray
    }
} else {
    $hooks["Notification"] = @($notificationEntry)
    Write-Host "[+] Added Notification hook" -ForegroundColor Green
}

# Merge PermissionRequest hooks
if ($hooks.ContainsKey("PermissionRequest")) {
    $existing = @($hooks["PermissionRequest"])
    $alreadyPresent = $false
    foreach ($entry in $existing) {
        foreach ($h in @($entry.hooks)) {
            if ($h.command -eq $permissionCommand) {
                $alreadyPresent = $true
                break
            }
        }
        if ($alreadyPresent) { break }
    }
    if (-not $alreadyPresent) {
        $hooks["PermissionRequest"] = @($existing) + @($permissionEntry)
        Write-Host "[+] Added PermissionRequest hook (merged with existing)" -ForegroundColor Green
    } else {
        Write-Host "[=] PermissionRequest hook already configured" -ForegroundColor DarkGray
    }
} else {
    $hooks["PermissionRequest"] = @($permissionEntry)
    Write-Host "[+] Added PermissionRequest hook" -ForegroundColor Green
}

# Merge Stop hooks
if ($hooks.ContainsKey("Stop")) {
    $existing = @($hooks["Stop"])
    $alreadyPresent = $false
    foreach ($entry in $existing) {
        foreach ($h in @($entry.hooks)) {
            if ($h.command -eq $notifyCommand) {
                $alreadyPresent = $true
                break
            }
        }
        if ($alreadyPresent) { break }
    }
    if (-not $alreadyPresent) {
        $hooks["Stop"] = @($existing) + @($stopEntry)
        Write-Host "[+] Added Stop hook (merged with existing)" -ForegroundColor Green
    } else {
        Write-Host "[=] Stop hook already configured" -ForegroundColor DarkGray
    }
} else {
    $hooks["Stop"] = @($stopEntry)
    Write-Host "[+] Added Stop hook" -ForegroundColor Green
}

$settings["hooks"] = $hooks

# ---------------------------------------------------------------------------
# 7. Write updated settings.json (pretty-printed)
# ---------------------------------------------------------------------------
$settingsJson = $settings | ConvertTo-Json -Depth 10
$settingsJson | Out-File $settingsPath -Encoding UTF8 -Force
Write-Host "[+] Updated settings: $settingsPath" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 8. Success summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Scripts installed to:" -ForegroundColor White
Write-Host "    $hooksDir\notify.ps1" -ForegroundColor DarkGray
Write-Host "    $hooksDir\notify-permission.ps1" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Settings updated:" -ForegroundColor White
Write-Host "    $settingsPath" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Restart Claude Code to activate the hooks." -ForegroundColor Yellow
Write-Host ""
