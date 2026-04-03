# notify.ps1 — Dark borderless toast for Claude Code (bottom-right, auto-close 4s).

[Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$inputJson   = [Console]::In.ReadToEnd() | ConvertFrom-Json
$msgText     = if ($inputJson.message) { $inputJson.message } else { "Done - waiting for input" }
$projectName = if ($inputJson.cwd) { Split-Path $inputJson.cwd -Leaf } else { "" }
$titleText   = if ($projectName) { "Claude Code - $projectName" } else { "Claude Code" }

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

if (Test-Path "$env:TEMP\claude-permission.lock") { exit 0 }

$form                   = New-Object System.Windows.Forms.Form
$form.Text              = ''
$form.Size              = New-Object System.Drawing.Size(360, 90)
$form.FormBorderStyle   = 'None'
$form.BackColor         = [System.Drawing.Color]::FromArgb(24, 24, 28)
$form.Opacity           = 0.95
$form.TopMost           = $true
$form.ShowInTaskbar     = $false
$form.StartPosition     = 'Manual'
$form.KeyPreview        = $true

$screen        = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($screen.Right - 370), ($screen.Bottom - 100))

# Purple accent bar (left edge)
$accent           = New-Object System.Windows.Forms.Panel
$accent.Size      = New-Object System.Drawing.Size(3, 90)
$accent.Location  = New-Object System.Drawing.Point(0, 0)
$accent.BackColor = $accentColor
$form.Controls.Add($accent)

# Close button
$closeBtn          = New-Object System.Windows.Forms.Label
$closeBtn.Text     = 'X'
$closeBtn.Font     = New-Object System.Drawing.Font('Segoe UI', 8)
$closeBtn.AutoSize = $true
$closeBtn.Location = New-Object System.Drawing.Point(340, 4)
$closeBtn.Cursor   = [System.Windows.Forms.Cursors]::Hand
$dimColor          = [System.Drawing.Color]::FromArgb(100, 100, 110)
$closeBtn.ForeColor = $dimColor
$closeBtn.Add_Click({ $form.Close() })
$closeBtn.Add_MouseEnter({ $this.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 210) })
$closeBtn.Add_MouseLeave({ $this.ForeColor = $dimColor })
$form.Controls.Add($closeBtn)

# Title
$title           = New-Object System.Windows.Forms.Label
$title.Text      = $titleText
$title.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 190)
$title.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
$title.AutoSize  = $true
$title.Location  = New-Object System.Drawing.Point(14, 10)
$form.Controls.Add($title)

# Message
$message             = New-Object System.Windows.Forms.Label
$message.Text        = $msgText
$message.ForeColor   = [System.Drawing.Color]::FromArgb(240, 240, 245)
$message.Font        = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$message.AutoSize    = $true
$message.MaximumSize = New-Object System.Drawing.Size(330, 0)
$message.Location    = New-Object System.Drawing.Point(14, 34)
$form.Controls.Add($message)

# Auto-close after 4 seconds
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 4000
$timer.Add_Tick({ $form.Close() })
$timer.Start()

# Click/key anywhere dismisses
$closeFn = { $form.Close() }
$form.Add_Click($closeFn); $title.Add_Click($closeFn); $message.Add_Click($closeFn)
$form.Add_KeyDown($closeFn)

$owner = New-Object System.Windows.Forms.Form -Property @{FormBorderStyle='FixedToolWindow'; ShowInTaskbar=$false; Size='0,0'}
$form.Owner = $owner
[System.Windows.Forms.Application]::Run($form)
