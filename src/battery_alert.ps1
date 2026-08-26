# ============================================
# 🔋 Battery Alert for Windows
# Simple battery monitoring with notifications
# ============================================

param(
    [int]$LowThreshold = 20,
    [int]$FullThreshold = 95,
    [int]$CheckInterval = 60,
    [switch]$Debug
)

function Get-BatteryInfo {
    try {
        $battery = Get-WmiObject -Class Win32_Battery -ErrorAction Stop
        
        # Get detailed status using WMI
        $status = Get-CimInstance -ClassName Win32_Battery
        
        $chargeStatus = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
        
        $percent = $status.EstimatedChargeRemaining
        $isCharging = ($status.BatteryStatus -eq 2) -or ($status.BatteryStatus -eq 6) -or ($status.BatteryStatus -eq 7)
        $isOnline = ($status.BatteryStatus -ne 1)
        
        return @{
            Percent = [int]$percent
            IsCharging = $isCharging
            IsOnline = $isOnline
            Status = $status.BatteryStatus
        }
    }
    catch {
        if ($Debug) { Write-Host "Error getting battery info: $_" }
        return $null
    }
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Type = "info"
    )
    
    try {
        # Load Windows Forms for notifications
        Add-Type -AssemblyName System.Windows.Forms
        
        # Create notification icon based on type
        $icon = switch($Type) {
            "warning" { [System.Windows.Forms.ToolTipIcon]::Warning }
            "error"   { [System.Windows.Forms.ToolTipIcon]::Error }
            default   { [System.Windows.Forms.ToolTipIcon]::Info }
        }
        
        # Use NotifyIcon for balloon tip
        $notification = New-Object System.Windows.Forms.NotifyIcon
        $notification.Icon = [System.Drawing.SystemIcons]::Information
        $notification.Visible = $true
        $notification.BalloonTipIcon = $icon
        $notification.BalloonTipTitle = $Title
        $notification.BalloonTipText = $Message
        $notification.ShowBalloonTip(5000)
        
        # Also play beep sound
        if ($Type -eq "warning") {
            [Console]::Beep(800, 300)
        }
        elseif ($Type -eq "full") {
            [Console]::Beep(1200, 200)
            Start-Sleep -Milliseconds 100
            [Console]::Beep(1500, 200)
        }
        
        # Cleanup after showing
        Start-Sleep -Seconds 6
        $notification.Dispose()
    }
    catch {
        # Fallback: show message box
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
    }
}

function Show-Message {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] $Text" -ForegroundColor $Color
}

# ============================================
# Main Loop
# ============================================

Clear-Host

Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     🔋 Battery Alert for Windows      ║" -ForegroundColor Cyan  
Write-Host "║                                       ║" -ForegroundColor Cyan
Write-Host "║  Low Threshold : $([string]$LowThreshold)%                          ║" -ForegroundColor Yellow
Write-Host "║  Full Threshold: $([string]$FullThreshold)%                          ║" -ForegroundColor Green
Write-Host "║  Check Interval: $([string]$CheckInterval)s                         ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# State variables
 $hasAlertedLow = $false
 $hasAlertedFull = $false
 $prevPercent = -1

Show-Message "✅ Started monitoring battery..." "Green"
Write-Host ""

while ($true) {
    $battery = Get-BatteryInfo
    
    if ($null -ne $battery) {
        $percent = $battery.Percent
        $isCharging = $battery.IsCharging
        
        # Show status bar
        $barLength = 20
        $filledBars = [math]::Floor(($percent / 100) * $barLength)
        $bar = ("█" * $filledBars) + ("░" * ($barLength - $filledBars))
        
        $statusText = if ($isCharging) { "⚡ Charging" } else { "🔌 Discharging" }
        $color = if ($isCharging) { "Cyan" } elseif ($percent -le $LowThreshold) { "Red" } elseif ($percent -ge $FullThreshold) { "Green" } else { "Yellow" }
        
        # Clear line and rewrite
        Write-Host "`r Battery: [" -NoNewline
        Write-Host $bar -NoNewline -ForegroundColor $color
        Write-Host "] $percent% $statusText" -ForegroundColor $color -NoNewline
        
        # Low battery warning
        if (-not $isCharging -and $percent -le $LowThreshold -and -not $hasAlertedLow) {
            Write-Host "" # newline
            Show-Notification `
                -Title "⚠️ Battery Low!" `
                -Message "Battery is at $percent%. Please plug in your charger!" `
                -Type "warning"
            
            Show-Message "⚠️  ALERT: Low battery! ($percent%)" "Red"
            $hasAlertedLow = $true
            
            # Beep multiple times
            for ($i = 0; $i -lt 3; $i++) {
                [Console]::Beep(600, 200)
                Start-Sleep -Milliseconds 150
                [Console]::Beep(800, 200)
                Start-Sleep -Milliseconds 500
            }
        }
        
        # Reset low alert flag when charging starts
        if ($isCharging -and $hasAlertedLow) {
            $hasAlertedLow = $false
            Show-Message "🔌 Charger connected - Low alert reset" "Green"
        }
        
        # Full battery notification
        if ($isCharging -and $percent -ge $FullThreshold -and -not $hasAlertedFull) {
            Write-Host "" # newline
            Show-Notification `
                -Title "✅ Battery Full!" `
                -Message "Battery is charged to $percent%. You can unplug the charger." `
                -Type "info"
            
            Show-Message "✅ ALERT: Battery full! ($percent%)" "Green"
            $hasAlertedFull = $true
        }
        
        # Reset full alert flag when not charging anymore
        if (-not $isCharging -and $hasAlertedFull) {
            $hasAlertedFull = $false
            Show-Message "🔌 Unplugged - Full alert reset" "Yellow"
        }
        
        # Reset full alert if charging dropped significantly
        if ($isCharging -and $percent -lt ($FullThreshold - 5)) {
            $hasAlertedFull = $false
        }
    }
    else {
        Write-Host "`r ⚠️ No battery detected or error reading battery info..." -NoNewline -ForegroundColor Red
    }
    
    Start-Sleep -Seconds $CheckInterval
}
