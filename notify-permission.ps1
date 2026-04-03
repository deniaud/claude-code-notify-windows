# notify-permission.ps1 — Claude Code PermissionRequest hook dialog
# Shows a WinForms Allow/Deny dialog for tool permission requests.
# For AskUserQuestion tool, shows option buttons instead.
# Reads JSON from stdin, writes JSON decision to stdout.

[Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Add-ButtonHover {
    param([System.Windows.Forms.Button]$Button, [System.Drawing.Color]$NormalColor, [System.Drawing.Color]$HoverColor)
    $n = $NormalColor; $h = $HoverColor
    $Button.Add_MouseEnter({ $this.BackColor = $h }.GetNewClosure())
    $Button.Add_MouseLeave({ $this.BackColor = $n }.GetNewClosure())
}

function New-FlatButton {
    param([string]$Text, [System.Drawing.Size]$Size, [System.Drawing.Point]$Location,
          [System.Drawing.Color]$BgColor, [System.Drawing.Color]$FgColor = [System.Drawing.Color]::White)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Size = $Size; $b.Location = $Location
    $b.BackColor = $BgColor; $b.ForeColor = $FgColor
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $b
}

$inputJson = [Console]::In.ReadToEnd() | ConvertFrom-Json
# Lockfile to suppress notification toast while permission dialog is open
$lockFile = "$env:TEMP\claude-permission.lock"
[IO.File]::WriteAllText($lockFile, [string](Get-Date))

# Extract tool name with fallback
$toolName = if ($inputJson.tool_name) { $inputJson.tool_name } else { "Unknown tool" }

# Extract project name from cwd
$projectName = if ($inputJson.cwd) { Split-Path $inputJson.cwd -Leaf } else { "" }

# Deterministic project color from name hash
$palette = @(
    @(120, 90, 255),   # purple (default/fallback)
    @(80, 160, 255),   # sky blue
    @(60, 170, 140),   # mint
    @(220, 120, 50),   # orange
    @(240, 100, 140),  # rose
    @(160, 130, 255),  # lavender
    @(80, 200, 220),   # cyan
    @(210, 160, 40),   # gold
    @(120, 200, 120),  # sage green
    @(200, 120, 255),  # orchid
    @(255, 130, 100),  # coral
    @(100, 180, 255)   # cornflower
)
if ($projectName) {
    $hash = 0
    foreach ($c in $projectName.ToCharArray()) { $hash = ($hash * 31 + [int]$c) -band 0x7FFFFFFF }
    $ci = $palette[$hash % $palette.Count]
} else {
    $ci = $palette[0]
}
$accentColor = [System.Drawing.Color]::FromArgb($ci[0], $ci[1], $ci[2])
$hoverColor = [System.Drawing.Color]::FromArgb(
    [Math]::Min(255, $ci[0] + 30),
    [Math]::Min(255, $ci[1] + 30),
    [Math]::Min(255, $ci[2] + 30)
)

$isAskUser  = $toolName -eq "AskUserQuestion"
$isExitPlan = $toolName -eq "ExitPlanMode"

# Parse AskUserQuestion data
$askQuestion = $null
$askOptions  = @()
if ($isAskUser -and $inputJson.tool_input) {
    $toolInput = $inputJson.tool_input
    # tool_input may be a string (JSON) or already parsed object
    if ($toolInput -is [string]) {
        try { $toolInput = $toolInput | ConvertFrom-Json } catch { $toolInput = $null }
    }
    if ($toolInput) {
        # Wrap questions in array — PowerShell may unwrap single-element arrays
        $questions = @($toolInput.questions)
        if ($questions.Length -gt 0) {
            $firstQ = $questions[0]
            $askQuestion = $firstQ.question
            $askOptions = @($firstQ.options)
        }
    }
}

# Extract tool input preview (for normal mode)
$inputPreview = ""
if (-not $isAskUser -and $inputJson.tool_input) {
    $ti = $inputJson.tool_input
    # Extract the most meaningful field per tool type
    $inputPreview = switch ($toolName) {
        'Bash'       { $ti.command }
        'Read'       { $ti.file_path }
        'Write'      { $ti.file_path }
        'Edit'       { $ti.file_path }
        'Glob'       { $ti.pattern }
        'Grep'       { $ti.pattern }
        'WebFetch'   { $ti.url }
        'WebSearch'  { $ti.query }
        'Agent'      { $ti.prompt }
        default      { $null }
    }
    if (-not $inputPreview) {
        $inputPreview = $ti | ConvertTo-Json -Depth 5 -Compress
    }
    if ($inputPreview.Length -gt 300) {
        $inputPreview = $inputPreview.Substring(0, 297) + "..."
    }
}

$script:decision      = "ask"
$script:denyMessage   = "Denied via notification"
$script:selectedLabel = $null

$formWidth = 380

if ($isExitPlan) {
    $formHeight = 150
} elseif ($isAskUser -and $askOptions.Length -gt 0) {
    # AskUserQuestion mode: need space for question + option buttons + Other btn
    $headerHeight   = 36
    $questionHeight = 60
    $btnHeight      = 34
    $btnSpacing     = 6
    $buttonCount    = $askOptions.Length + 1  # +1 for "Other..."
    $buttonsTotal   = ($btnHeight + $btnSpacing) * $buttonCount
    $padding        = 20
    $formHeight     = $headerHeight + $questionHeight + $buttonsTotal + $padding
    if ($formHeight -lt 180) { $formHeight = 180 }
} else {
    $formHeight = 220
}

$form = New-Object System.Windows.Forms.Form
$form.Text = ''
$form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
$form.StartPosition = 'Manual'
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($screen.Right - $formWidth - 10), ($screen.Bottom - $formHeight - 10))
$form.TopMost = $true
$form.FormBorderStyle = 'None'
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
$form.Opacity = 0.95
$form.ShowInTaskbar = $false

# Accent bar (left edge, 3px wide)
$accent = New-Object System.Windows.Forms.Panel
$accent.Size = New-Object System.Drawing.Size(3, $formHeight)
$accent.Location = New-Object System.Drawing.Point(0, 0)
$accent.BackColor = $accentColor
$form.Controls.Add($accent) | Out-Null

# X dismiss button
$closeBtn = New-Object System.Windows.Forms.Label
$closeBtn.Text = 'X'
$closeBtn.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 110)
$closeBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$closeBtn.AutoSize = $true
$closeBtn.Location = New-Object System.Drawing.Point(($formWidth - 22), 4)
$closeBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$closeBtn.Add_Click({
    $script:decision = "ask"
    $form.Close()
})
$closeBtn.Add_MouseEnter({ $this.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 210) })
$closeBtn.Add_MouseLeave({ $this.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 110) })
$form.Controls.Add($closeBtn) | Out-Null

# Header label
$headerText = if ($projectName) { "Permission Request - $projectName" } else { "Permission Request" }
$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Text = $headerText
$headerLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 190)
$headerLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$headerLabel.AutoSize = $true
$headerLabel.Location = New-Object System.Drawing.Point(14, 10)
$form.Controls.Add($headerLabel) | Out-Null

if ($isExitPlan) {
    $planLabel = New-Object System.Windows.Forms.Label
    $planLabel.Text = "Plan ready for review"
    $planLabel.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 245)
    $planLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $planLabel.AutoSize = $true
    $planLabel.Location = New-Object System.Drawing.Point(14, 32)
    $form.Controls.Add($planLabel) | Out-Null

    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Text = "Choose in terminal for full options"
    $hintLabel.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 140)
    $hintLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $hintLabel.AutoSize = $true
    $hintLabel.Location = New-Object System.Drawing.Point(14, 56)
    $form.Controls.Add($hintLabel) | Out-Null

    $askBtn = New-FlatButton 'Open in terminal' (New-Object System.Drawing.Size(($formWidth - 28), 32)) (New-Object System.Drawing.Point(14, ($formHeight - 45))) $accentColor
    $askBtn.Add_Click({
        $script:decision = "ask"
        $form.Close()
    })
    Add-ButtonHover $askBtn $accentColor $hoverColor
    $form.Controls.Add($askBtn) | Out-Null

} elseif ($isAskUser -and $askOptions.Length -gt 0) {
    # Question text as main label
    $qLabel = New-Object System.Windows.Forms.Label
    $qLabel.Text = if ($askQuestion) { $askQuestion } else { "Question" }
    $qLabel.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 245)
    $qLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $qLabel.AutoSize = $true
    $qLabel.MaximumSize = New-Object System.Drawing.Size(350, 60)
    $qLabel.Location = New-Object System.Drawing.Point(14, 32)
    $form.Controls.Add($qLabel) | Out-Null

    # Option buttons
    $btnTop = 92
    $btnW   = ($formWidth - 28)
    $btnH   = 34

    foreach ($opt in $askOptions) {
        $optBtn = New-FlatButton $opt.label (New-Object System.Drawing.Size($btnW, $btnH)) (New-Object System.Drawing.Point(14, $btnTop)) $accentColor
        $optBtn.TextAlign = 'MiddleCenter'
        $optBtn.Tag = $opt.label
        $optBtn.Add_Click({
            param($sender, $e)
            $script:selectedLabel = $sender.Tag
            $script:decision = "allow_with_answer"
            $form.Close()
        })
        Add-ButtonHover $optBtn $accentColor $hoverColor
        $form.Controls.Add($optBtn) | Out-Null
        $btnTop += ($btnH + 6)
    }

    # "Other..." button — muted style
    $otherBtn = New-FlatButton 'Other...' (New-Object System.Drawing.Size($btnW, $btnH)) (New-Object System.Drawing.Point(14, $btnTop)) ([System.Drawing.Color]::FromArgb(50, 50, 58)) ([System.Drawing.Color]::FromArgb(180, 180, 190))

    # Pre-create text input and send button (hidden until "Other..." clicked)
    $script:otherInput = New-Object System.Windows.Forms.TextBox
    $script:otherInput.Size = New-Object System.Drawing.Size(($formWidth - 28), 28)
    $script:otherInput.Location = New-Object System.Drawing.Point(14, $btnTop)
    $script:otherInput.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 48)
    $script:otherInput.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 245)
    $script:otherInput.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:otherInput.BorderStyle = 'FixedSingle'
    $script:otherInput.Visible = $false
    $form.Controls.Add($script:otherInput)

    $sendBtn = New-FlatButton 'Send' (New-Object System.Drawing.Size(($formWidth - 28), 30)) (New-Object System.Drawing.Point(14, ($btnTop + 34))) $accentColor
    $sendBtn.Visible = $false
    Add-ButtonHover $sendBtn $accentColor $hoverColor
    $form.Controls.Add($sendBtn)

    # Submit handler (shared by Send button click and Enter key)
    $submitOther = {
        $txt = $script:otherInput.Text
        if ($txt) {
            $script:selectedLabel = $txt
            $script:decision = "allow_with_answer"
        } else {
            $script:decision = "allow"
        }
        $form.Close()
    }

    $sendBtn.Add_Click($submitOther)
    $script:otherInput.Add_KeyDown({
        param($s, $ev)
        if ($ev.KeyCode -eq 'Return') {
            $ev.SuppressKeyPress = $true
            & $submitOther
        }
    })

    # "Other..." reveals text input
    $otherBtn.Add_Click({
        foreach ($c in @($form.Controls)) {
            if ($c -is [System.Windows.Forms.Button]) { $c.Visible = $false }
        }
        $script:otherInput.Visible = $true
        $sendBtn.Visible = $true
        $script:otherInput.Focus() | Out-Null
    })
    Add-ButtonHover $otherBtn ([System.Drawing.Color]::FromArgb(50, 50, 58)) ([System.Drawing.Color]::FromArgb(65, 65, 75))
    $form.Controls.Add($otherBtn) | Out-Null

} else {
    # Normal permission mode
    $toolLabel = New-Object System.Windows.Forms.Label
    $toolLabel.Text = $toolName
    $toolLabel.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 245)
    $toolLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $toolLabel.AutoSize = $true
    $toolLabel.Location = New-Object System.Drawing.Point(14, 32)
    $form.Controls.Add($toolLabel) | Out-Null

    $inputLabel = New-Object System.Windows.Forms.Label
    $inputLabel.Text = $inputPreview
    $inputLabel.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 140)
    $inputLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $inputLabel.AutoSize = $true
    $inputLabel.MaximumSize = New-Object System.Drawing.Size(350, 80)
    $inputLabel.Location = New-Object System.Drawing.Point(14, 58)
    $form.Controls.Add($inputLabel) | Out-Null

    $allowBtn = New-FlatButton 'Allow' (New-Object System.Drawing.Size(90, 32)) (New-Object System.Drawing.Point(($formWidth - 205), ($formHeight - 45))) ([System.Drawing.Color]::FromArgb(45, 140, 70))
    $allowBtn.Add_Click({ $script:decision = "allow"; $form.Close() })
    Add-ButtonHover $allowBtn ([System.Drawing.Color]::FromArgb(45, 140, 70)) ([System.Drawing.Color]::FromArgb(55, 170, 85))
    $form.Controls.Add($allowBtn) | Out-Null

    $denyBtn = New-FlatButton 'Deny' (New-Object System.Drawing.Size(90, 32)) (New-Object System.Drawing.Point(($formWidth - 105), ($formHeight - 45))) ([System.Drawing.Color]::FromArgb(170, 45, 45))
    $denyBtn.Add_Click({ $form.Close() })
    Add-ButtonHover $denyBtn ([System.Drawing.Color]::FromArgb(170, 45, 45)) ([System.Drawing.Color]::FromArgb(200, 55, 55))
    $form.Controls.Add($denyBtn) | Out-Null
}

# Keyboard shortcuts
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($sender, $e)
    if ($isExitPlan) {
        if ($e.KeyCode -eq 'Return') { $script:decision = "ask"; $form.Close() }
    } elseif ($isAskUser -and $askOptions.Length -gt 0) {
        # Number keys select options (1-9)
        $keyStr = $e.KeyCode.ToString()
        $num = 0
        if ($keyStr -match '^(D|NumPad)(\d)$') { $num = [int]$Matches[2] }
        if ($num -gt 0 -and $num -le $askOptions.Length) {
            $script:selectedLabel = $askOptions[$num - 1].label
            $script:decision = "allow_with_answer"
            $form.Close()
        }
    } else {
        if ($e.KeyCode -eq 'Return') { $script:decision = "allow"; $form.Close() }
    }
    if ($e.KeyCode -eq 'Escape') {
        $script:decision = "ask"
        $form.Close()
    }
})

# Show dialog (blocks until form closes)
$owner = New-Object System.Windows.Forms.Form -Property @{FormBorderStyle='FixedToolWindow'; ShowInTaskbar=$false; Size='0,0'}
$form.Owner = $owner
[System.Windows.Forms.Application]::Run($form) | Out-Null

# Remove lockfile so notification toasts resume
try { Remove-Item $lockFile -ErrorAction SilentlyContinue } catch {}

# Build and write JSON decision to stdout
$dec = @{ behavior = $script:decision }
if ($script:decision -eq "allow_with_answer") {
    $dec.behavior = "allow"
    $dec.updatedInput = @{ questions = @($toolInput.questions); answers = @{ $askQuestion = $script:selectedLabel } }
} elseif ($script:decision -eq "deny") {
    $dec.message = $script:denyMessage
}
$output = @{ hookSpecificOutput = @{ hookEventName = "PermissionRequest"; decision = $dec } }
[Console]::Out.Write(($output | ConvertTo-Json -Depth 10 -Compress))
