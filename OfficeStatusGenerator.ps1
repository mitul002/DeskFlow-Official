Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Runtime.WindowsRuntime, System.Windows.Forms, System.Drawing

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DeskFlowWin32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction SilentlyContinue
} catch {}

# ==============================================================================
# SINGLE INSTANCE ENFORCEMENT & FOCUS ENGINE
# ==============================================================================
$createdNew = $false
$global:DeskFlowSingleInstanceMutex = New-Object System.Threading.Mutex($true, "DeskFlowSingleInstanceMutex_Enterprise_8899", [ref]$createdNew)
if (-not $createdNew) {
    try {
        $ws = New-Object -ComObject WScript.Shell
        [void]$ws.AppActivate("DeskFlow")

        $myPid = [System.Diagnostics.Process]::GetCurrentProcess().Id
        $proc = Get-Process -Name "DeskFlow", "OfficeStatusGenerator" -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $myPid -and $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        if ($null -ne $proc) {
            [void][DeskFlowWin32]::ShowWindow($proc.MainWindowHandle, 9)
            [void][DeskFlowWin32]::SetForegroundWindow($proc.MainWindowHandle)
        }
    } catch {}
    [System.Environment]::Exit(0)
}

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptDir) -and $MyInvocation.MyCommand.Path) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue }
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = [System.AppDomain]::CurrentDomain.BaseDirectory }
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = Get-Location }

$global:DataDir = Join-Path $env:LOCALAPPDATA "DeskFlow"
$global:AppVersion = "1.0.3"
$global:LunchEmoji = [char]::ConvertFromUtf32(0x1F371)
$global:PrayerEmoji = [char]::ConvertFromUtf32(0x1F54C)

# ==============================================================================
# DESKFLOW ENTERPRISE LICENSE & SECURITY ENGINE
# ==============================================================================
$global:DeskFlowSecretSalt  = "DeskFlow_P5#wR9!kL2@qM7`$zX_S3cr3t"
$global:DeskFlowValidateUrl = "https://cross-tech-admin.vercel.app/api/validate"
$global:DeskFlowSoftwareId  = "deskflow"
$global:DeskFlowTrialDays   = 30

function Get-DeskFlowMachineId {
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        $machineGuid = (Get-ItemProperty -Path $regPath -Name "MachineGuid" -ErrorAction SilentlyContinue).MachineGuid
        if ([string]::IsNullOrEmpty($machineGuid)) {
            $machineGuid = [System.Environment]::MachineName
        }
        $rawId = "DESKFLOW_" + $machineGuid + "_" + [System.Environment]::MachineName
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($rawId)
        $hashBytes = $sha256.ComputeHash($bytes)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) { [void]$sb.Append($b.ToString("x2")) }
        return $sb.ToString().Substring(0, 32).ToLower()
    } catch {
        return "deskflow_default_hwid_9999"
    }
}

function Protect-DeskFlowData {
    param([string]$plainText)
    if ([string]::IsNullOrEmpty($plainText)) { return "" }
    try {
        $passKey = Get-DeskFlowMachineId
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($passKey)
        $textBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
        $outBytes = New-Object byte[] $textBytes.Length
        for ($i = 0; $i -lt $textBytes.Length; $i++) {
            $outBytes[$i] = $textBytes[$i] -bxor $keyBytes[$i % $keyBytes.Length]
        }
        return [Convert]::ToBase64String($outBytes)
    } catch { return "" }
}

function Unprotect-DeskFlowData {
    param([string]$cipherText)
    if ([string]::IsNullOrEmpty($cipherText)) { return "" }
    try {
        $passKey = Get-DeskFlowMachineId
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($passKey)
        $textBytes = [Convert]::FromBase64String($cipherText)
        $outBytes = New-Object byte[] $textBytes.Length
        for ($i = 0; $i -lt $textBytes.Length; $i++) {
            $outBytes[$i] = $textBytes[$i] -bxor $keyBytes[$i % $keyBytes.Length]
        }
        return [System.Text.Encoding]::UTF8.GetString($outBytes)
    } catch { return "" }
}

# 4-Layer Stealth Mirror Storage for Trial Start Date
function Get-StealthTrialDate {
    $candidates = @()
    
    # Layer 1: HKCU\Software\DeskFlow\TrialStart
    try {
        $v1 = (Get-ItemProperty -Path "HKCU:\Software\DeskFlow" -Name "TrialStart" -ErrorAction SilentlyContinue).TrialStart
        $d1 = Unprotect-DeskFlowData $v1
        if ([DateTime]::TryParse($d1, [ref]([DateTime]::MinValue))) { $candidates += [DateTime]::Parse($d1) }
    } catch {}

    # Layer 2: HKCU\Software\Classes\CLSID\{B54F3741-5B07-4214-BE35-A43A6B64C005}\SysState
    try {
        $v2 = (Get-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{B54F3741-5B07-4214-BE35-A43A6B64C005}" -Name "SysState" -ErrorAction SilentlyContinue).SysState
        $d2 = Unprotect-DeskFlowData $v2
        if ([DateTime]::TryParse($d2, [ref]([DateTime]::MinValue))) { $candidates += [DateTime]::Parse($d2) }
    } catch {}

    # Layer 3: %APPDATA%\Microsoft\Protect\sys_info.db
    try {
        $f3 = Join-Path $env:APPDATA "Microsoft\Protect\sys_info.db"
        if (Test-Path $f3) {
            $v3 = Get-Content -Path $f3 -Raw -ErrorAction SilentlyContinue
            $d3 = Unprotect-DeskFlowData $v3
            if ([DateTime]::TryParse($d3, [ref]([DateTime]::MinValue))) { $candidates += [DateTime]::Parse($d3) }
        }
    } catch {}

    # Layer 4: %LOCALAPPDATA%\DeskFlow\trial.dat
    try {
        $f4 = Join-Path $env:LOCALAPPDATA "DeskFlow\trial.dat"
        if (Test-Path $f4) {
            $v4 = Get-Content -Path $f4 -Raw -ErrorAction SilentlyContinue
            $d4 = Unprotect-DeskFlowData $v4
            if ([DateTime]::TryParse($d4, [ref]([DateTime]::MinValue))) { $candidates += [DateTime]::Parse($d4) }
        }
    } catch {}

    if ($candidates.Count -gt 0) {
        # Sort ascending, pick the oldest date (anti-tamper)
        $oldest = ($candidates | Sort-Object)[0]
        # Self-heal missing/tampered locations
        Save-StealthTrialDate $oldest
        return $oldest
    }
    
    # First run: initialize trial date
    $now = Get-Date
    Save-StealthTrialDate $now
    return $now
}

function Save-StealthTrialDate {
    param([DateTime]$date)
    $dateStr = $date.ToString("o")
    $enc = Protect-DeskFlowData $dateStr

    # Layer 1
    try {
        if (-not (Test-Path "HKCU:\Software\DeskFlow")) { New-Item -Path "HKCU:\Software\DeskFlow" -Force | Out-Null }
        Set-ItemProperty -Path "HKCU:\Software\DeskFlow" -Name "TrialStart" -Value $enc -Force
    } catch {}

    # Layer 2
    try {
        $clsid = "HKCU:\Software\Classes\CLSID\{B54F3741-5B07-4214-BE35-A43A6B64C005}"
        if (-not (Test-Path $clsid)) { New-Item -Path $clsid -Force | Out-Null }
        Set-ItemProperty -Path $clsid -Name "SysState" -Value $enc -Force
    } catch {}

    # Layer 3
    try {
        $dir3 = Join-Path $env:APPDATA "Microsoft\Protect"
        if (-not (Test-Path $dir3)) { New-Item -Path $dir3 -ItemType Directory -Force | Out-Null }
        $f3 = Join-Path $dir3 "sys_info.db"
        Set-Content -Path $f3 -Value $enc -Force
        if (Test-Path $f3) { (Get-Item $f3 -ErrorAction SilentlyContinue).Attributes = 'Hidden', 'System' }
    } catch {}

    # Layer 4
    try {
        $dir4 = Join-Path $env:LOCALAPPDATA "DeskFlow"
        if (-not (Test-Path $dir4)) { New-Item -Path $dir4 -ItemType Directory -Force | Out-Null }
        $f4 = Join-Path $dir4 "trial.dat"
        Set-Content -Path $f4 -Value $enc -Force
    } catch {}
}

# License Payload Local Storage
function Get-StealthLicensePayload {
    try {
        $f = Join-Path $env:LOCALAPPDATA "DeskFlow\lic.dat"
        if (Test-Path $f) {
            $enc = Get-Content -Path $f -Raw -ErrorAction SilentlyContinue
            $jsonStr = Unprotect-DeskFlowData $enc
            if (-not [string]::IsNullOrEmpty($jsonStr)) {
                return $jsonStr | ConvertFrom-Json
            }
        }
    } catch {}
    return $null
}

function Save-StealthLicensePayload {
    param($payloadObj)
    try {
        $dir = Join-Path $env:LOCALAPPDATA "DeskFlow"
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $jsonStr = ConvertTo-Json $payloadObj -Depth 5
        $enc = Protect-DeskFlowData $jsonStr
        Set-Content -Path (Join-Path $dir "lic.dat") -Value $enc -Force
        Clear-StealthLicenseExpiredMarker
    } catch {}
}

function Mark-StealthLicenseExpired {
    param([string]$reason = "LicenseRevoked")
    try {
        $dir = Join-Path $env:LOCALAPPDATA "DeskFlow"
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $enc = Protect-DeskFlowData $reason
        Set-Content -Path (Join-Path $dir "lic_expired.dat") -Value $enc -Force
        
        $clsid = "HKCU:\Software\Classes\CLSID\{B54F3741-5B07-4214-BE35-A43A6B64C005}"
        if (-not (Test-Path $clsid)) { New-Item -Path $clsid -Force | Out-Null }
        Set-ItemProperty -Path $clsid -Name "LicExpired" -Value $enc -Force
    } catch {}
}

function Get-StealthLicenseExpiredReason {
    try {
        $f = Join-Path $env:LOCALAPPDATA "DeskFlow\lic_expired.dat"
        if (Test-Path $f) {
            $enc = Get-Content -Path $f -Raw -ErrorAction SilentlyContinue
            $reason = Unprotect-DeskFlowData $enc
            if (-not [string]::IsNullOrEmpty($reason)) { return $reason }
        }
        $clsid = "HKCU:\Software\Classes\CLSID\{B54F3741-5B07-4214-BE35-A43A6B64C005}"
        if (Test-Path $clsid) {
            $enc = (Get-ItemProperty -Path $clsid -Name "LicExpired" -ErrorAction SilentlyContinue).LicExpired
            $reason = Unprotect-DeskFlowData $enc
            if (-not [string]::IsNullOrEmpty($reason)) { return $reason }
        }
    } catch {}
    return $null
}

function Clear-StealthLicenseExpiredMarker {
    try {
        $f = Join-Path $env:LOCALAPPDATA "DeskFlow\lic_expired.dat"
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        
        $clsid = "HKCU:\Software\Classes\CLSID\{B54F3741-5B07-4214-BE35-A43A6B64C005}"
        if (Test-Path $clsid) { Remove-ItemProperty -Path $clsid -Name "LicExpired" -ErrorAction SilentlyContinue }
    } catch {}
}

function Clear-StealthLicensePayload {
    try {
        $f = Join-Path $env:LOCALAPPDATA "DeskFlow\lic.dat"
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    } catch {}
}

# HMAC SHA-256 Signature Verification
function Test-DeskFlowSignature {
    param(
        [string]$key,
        [string]$machineId,
        [string]$licenseType,
        [string]$serverSignature
    )
    if ([string]::IsNullOrEmpty($serverSignature)) { return $false }
    try {
        $msg = "True:" + $key + ":" + $machineId + ":" + $licenseType
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($global:DeskFlowSecretSalt)
        $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($msg))
        
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) { [void]$sb.Append($b.ToString("x2")) }
        $expectedSig = $sb.ToString().ToLower()
        
        return ($expectedSig -eq $serverSignature.ToLower())
    } catch {
        return $false
    }
}

# Online Validation Gateway Call
function Invoke-DeskFlowValidation {
    param(
        [string]$key,
        [string]$email,
        [bool]$requestTransfer = $false
    )
    $machineId = Get-DeskFlowMachineId
    $body = @{
        key              = $key
        email            = $email
        machine_id       = $machineId
        software_id      = $global:DeskFlowSoftwareId
        request_transfer = $requestTransfer
    } | ConvertTo-Json

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $response = Invoke-RestMethod -Uri $global:DeskFlowValidateUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10
        return $response
    } catch {
        return @{ valid = $false; message = "Network error. Please check your internet connection." }
    }
}

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptDir) -and $MyInvocation.MyCommand.Path) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue }
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = [System.AppDomain]::CurrentDomain.BaseDirectory }
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = Get-Location }

$global:DataDir = Join-Path $env:LOCALAPPDATA "DeskFlow"
$global:LunchEmoji = [char]::ConvertFromUtf32(0x1F371)
$global:PrayerEmoji = [char]::ConvertFromUtf32(0x1F54C)

# Win32 Inactivity/Idle API definition
$idleSignature = @"
using System;
using System.Runtime.InteropServices;

public class Win32Idle {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    
    public static uint GetIdleTime() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (GetLastInputInfo(ref lii)) {
            return (uint)Environment.TickCount - lii.dwTime;
        }
        return 0;
    }
}
"@
try {
    Add-Type -TypeDefinition $idleSignature
} catch {
    # If already defined (e.g. running in same ISE session)
}

# 1. Load Settings and Configuration
$global:Settings = $null
$global:OfficeStarted = $false
$global:OfficeStartTime = $null
$global:TotalBreakDurationSeconds = 0
$global:ActiveBreakType = $null
$global:BreakStartTime = $null
$global:ActiveBreakElapsedSeconds = 0
$global:LoadedHistory = @()
$global:ToastTimer = $null
$global:IsExiting = $false
$global:WorkDayTargetAchieved = $false
$global:WasIdle = $false
$global:TaskList = New-Object System.Collections.Generic.List[PSCustomObject]
$global:LastFocusedDetailsTextBox = $null
$global:LastActiveTaskBeforeBreak = $null
$global:EntryTime = $null
$global:IdleStartTime = $null
$global:AwayDurationMinutes = 0
$global:AwayStartTime = $null

function Load-Settings {
    $dataDir = $global:DataDir
    if (-not (Test-Path $dataDir)) {
        New-Item -Path $dataDir -ItemType "Directory" -Force | Out-Null
    }
    
    $settingsFile = Join-Path $dataDir "settings.json"
    if (Test-Path $settingsFile) {
        try {
            $global:Settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
            if ($null -eq $global:Settings.always_on_top) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "always_on_top" -Value $false -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.start_with_windows) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "start_with_windows" -Value $true -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.auto_detect_session) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "auto_detect_session" -Value $true -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.webhook_enabled) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "webhook_enabled" -Value $true -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.webhook_display_name) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "webhook_display_name" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.webhook_avatar_url) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "webhook_avatar_url" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.webhook_avatar_emoji) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "webhook_avatar_emoji" -Value "None" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.webhook_url) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "webhook_url" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.break_alerts_enabled) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "break_alerts_enabled" -Value $false -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.lunch_limit_minutes) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "lunch_limit_minutes" -Value 60 -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.prayer_limit_minutes) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "prayer_limit_minutes" -Value 20 -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.workday_target_hours) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "workday_target_hours" -Value 8.0 -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.idle_tracker_enabled) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "idle_tracker_enabled" -Value $false -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.idle_timeout_minutes) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "idle_timeout_minutes" -Value 5 -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.minimize_to_tray) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "minimize_to_tray" -Value $true -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.close_to_tray) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "close_to_tray" -Value $false -ErrorAction SilentlyContinue
            }
                        if ($null -eq $global:Settings.off_days_weekly) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "off_days_weekly" -Value @("Sunday") -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.off_days_occurrences) {
                $defaultOccurrences = @()
                if ($global:Settings.off_days_second_sat -eq $true) {
                    $defaultOccurrences += @{ day = "Saturday"; weeks = @("2nd") }
                }
                if ($global:Settings.off_days_fourth_sat -eq $true) {
                    $defaultOccurrences += @{ day = "Saturday"; weeks = @("4th") }
                }
                if ($defaultOccurrences.Count -eq 0) {
                    $defaultOccurrences = @(
                        @{ day = "Saturday"; weeks = @("2nd", "4th") }
                    )
                }
                $global:Settings | Add-Member -MemberType NoteProperty -Name "off_days_occurrences" -Value $defaultOccurrences -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.off_days_custom) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "off_days_custom" -Value @() -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.quick_tasks) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "quick_tasks" -Value @("A+ Content Design", "Listing Image Design", "Code Review", "Bug Fixing", "Client Meeting") -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.custom_breaks) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "custom_breaks" -Value @() -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.templates.task_update) {
                if ($null -ne $global:Settings.templates.end_of_day) {
                    $cleaned = $global:Settings.templates.end_of_day -replace '(?s)\r?\n\r?\nLeaving from office\.', ''
                    $global:Settings.templates | Add-Member -MemberType NoteProperty -Name "task_update" -Value $cleaned -ErrorAction SilentlyContinue
                } else {
                    $global:Settings.templates | Add-Member -MemberType NoteProperty -Name "task_update" -Value "Dear Sir/Madam,`n`nToday, I have worked {working_hours} hrs on the following task:`n`nTask update:`n{task_update}" -ErrorAction SilentlyContinue
                }
            }
            if ($null -eq $global:Settings.templates.leaving_office) {
                $global:Settings.templates | Add-Member -MemberType NoteProperty -Name "leaving_office" -Value "Leaving from office." -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.user_name) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "user_name" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.user_role) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "user_role" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.google_script_url) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "google_script_url" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.google_sheet_url) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "google_sheet_url" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.gmail_address) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "gmail_address" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.gmail_app_password) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "gmail_app_password" -Value "" -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.email_sets) {
                $defaultSets = @()
                if ($null -ne $global:Settings.recipient_emails -and $global:Settings.recipient_emails -ne "") {
                    $defaultSets += [PSCustomObject]@{ name = "Default"; emails = $global:Settings.recipient_emails; is_default = $true }
                }
                $global:Settings | Add-Member -MemberType NoteProperty -Name "email_sets" -Value $defaultSets -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.hubstaff_accounts) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "hubstaff_accounts" -Value @() -ErrorAction SilentlyContinue
            }
            if ($null -eq $global:Settings.table_body_color) {
                $global:Settings | Add-Member -MemberType NoteProperty -Name "table_body_color" -Value "#e0a3c1" -ErrorAction SilentlyContinue
            }
        } catch {
            $global:Settings = $null
        }
    }
    
    # Fallback to defaults
    if ($null -eq $global:Settings) {
        $global:Settings = [PSCustomObject]@{
            templates = [PSCustomObject]@{
                good_morning = "Assalamualaikum, Good morning."
                lunch_start = "Leaving for lunch at {current_time}"
                lunch_return = "Back from lunch at {current_time} ({duration} min)"
                prayer_start = "Leaving for prayer break at {current_time}"
                prayer_return = "Back from prayer break at {current_time} ({duration} min)"
                combo_start = "Leaving for lunch & prayer break at {current_time}"
                combo_return = "Back from lunch & prayer break at {current_time} ({duration} min)"
                task_update = "Hello Sir/Mam,`r`n`r`nToday, I have worked {working_hours} hrs on the following task:`r`n`r`n{{TASK_TABLE}}"
                leaving_office = "Leaving from office."
            }
            always_on_top = $false
            start_with_windows = $true
            auto_detect_session = $true
            webhook_enabled = $true
            webhook_display_name = ""
            webhook_avatar_url = ""
            webhook_avatar_emoji = "None"
            webhook_url = ""
            break_alerts_enabled = $false
            lunch_limit_minutes = 60
            prayer_limit_minutes = 20
            workday_target_hours = 8.0
            idle_tracker_enabled = $false
            idle_timeout_minutes = 5
            minimize_to_tray = $true
            close_to_tray = $false
            off_days_weekly = @("Sunday")
            off_days_occurrences = @(
                @{ day = "Saturday"; weeks = @("2nd", "4th") }
            )
            off_days_custom = @()
            quick_tasks = @("A+ Content Design", "Listing Image Design", "Code Review", "Bug Fixing", "Client Meeting")
            custom_breaks = @()
            user_name = ""
            user_role = ""
            google_script_url = ""
            google_sheet_url = ""
            gmail_address = ""
            gmail_app_password = ""
            email_sets = @()
            hubstaff_accounts = @()
            table_body_color = "#e0a3c1"
        }
        
        # Write default file
        $json = ConvertTo-Json $global:Settings -Depth 10
        Set-Content -Path $settingsFile -Value $json -Force
    }
}

# 2. XAML GUI Definition (Fluent Dark Theme)
$infoEmoji = [char]0x2139 + [char]0xFE0F
$lightningEmoji = [char]0x26A1
$calendarEmoji = [char]::ConvertFromUtf32(0x1F4C5)
$msgEmoji = [char]::ConvertFromUtf32(0x1F4DD)
$emailEmoji = [char]0x2709 + [char]0xFE0F
$folderEmoji = [char]::ConvertFromUtf32(0x1F4C1)
$warningEmoji = [char]0x26A0 + [char]0xFE0F
$waitEmoji = [char]0x23F3
$checkEmoji = [char]0x2713
$crossEmoji = [char]0x274C
$gearEmoji = [char]::ConvertFromUtf32(0x2699) + [char]0xFE0F
$plugEmoji = [char]::ConvertFromUtf32(0x1F50C)
$logoPath = Join-Path $scriptDir "image\logo.png"
$logoUri = (New-Object System.Uri($logoPath)).AbsoluteUri
$logoIcoPath = Join-Path $scriptDir "image\logo.ico"
$logoIcoUri = (New-Object System.Uri($logoIcoPath)).AbsoluteUri

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DeskFlow" Icon="$logoIcoUri" Height="740" Width="1200"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="Transparent" AllowsTransparency="True" WindowStyle="None">
    
    <Window.Resources>
        <!-- Custom Button Style -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#6C5CE7"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="15,10"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.4"/>
                                <Setter TargetName="border" Property="Background" Value="#4E4E5A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Copy Line Button Style -->
        <Style x:Key="CopyLineButton" TargetType="Button">
            <Setter Property="Background" Value="#20202A"/>
            <Setter Property="BorderBrush" Value="#2D2D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Width" Value="28"/>
            <Setter Property="Height" Value="28"/>
            <Setter Property="ToolTip" Value="Copy this line"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#6C5CE7"/>
                    <Setter Property="BorderBrush" Value="#6C5CE7"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Sidebar Navigation Button Style -->
        <Style x:Key="SidebarButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#8F8F9D"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="Height" Value="42"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="6" Padding="15,0">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#252530"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Dashboard Cards Style -->
        <Style x:Key="CardBorder" TargetType="Border">
            <Setter Property="Background" Value="#1E1E26"/>
            <Setter Property="BorderBrush" Value="#2A2A35"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,16"/>
        </Style>

        <!-- Custom TextBox Style -->
        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#15151B"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#2D2D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,4"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ScrollViewer Name="PART_ContentHost" Padding="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#6C5CE7"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="1.2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#1E1E24"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#2D2D35"/>
                                <Setter Property="Foreground" Value="#6F6F7D"/>
                                <Setter TargetName="border" Property="Opacity" Value="0.6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ModernPasswordBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#15151B"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#2D2D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="PasswordBox">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ScrollViewer Name="PART_ContentHost" Padding="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#6C5CE7"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="1.2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#1E1E24"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#2D2D35"/>
                                <Setter Property="Foreground" Value="#6F6F7D"/>
                                <Setter TargetName="border" Property="Opacity" Value="0.6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Style for DatePickerTextBox to fix white-on-white text issues -->
        <Style TargetType="DatePickerTextBox">
            <Setter Property="Background" Value="#15151B"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="4,4,4,4"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>

        <Style TargetType="DatePicker">
            <Setter Property="Background" Value="#15151B"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#2D2D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Style for Calendar popup in DatePicker to match dark mode -->
        <Style TargetType="Calendar">
            <Setter Property="Background" Value="#1E1E26"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#2A2A35"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>

        <!-- Toggle Button Template for ComboBox -->
        <ControlTemplate x:Key="ComboBoxToggleButton" TargetType="ToggleButton">
            <Border Name="Border" Background="#15151B" BorderBrush="#2D2D37" BorderThickness="1" CornerRadius="6">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition />
                        <ColumnDefinition Width="30" />
                    </Grid.ColumnDefinitions>
                    <Path Name="Arrow" Grid.Column="1" Fill="#8F8F9D" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M 0 0 L 4 4 L 8 0 Z"/>
                </Grid>
            </Border>
            <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="true">
                    <Setter TargetName="Border" Property="Background" Value="#20202A"/>
                    <Setter TargetName="Border" Property="BorderBrush" Value="#6C5CE7"/>
                </Trigger>
                <Trigger Property="IsChecked" Value="true">
                    <Setter TargetName="Border" Property="Background" Value="#20202A"/>
                    <Setter TargetName="Border" Property="BorderBrush" Value="#6C5CE7"/>
                </Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>

        <!-- Custom ComboBox Styles -->
        <Style x:Key="ModernComboBox" TargetType="ComboBox">
            <Setter Property="Background" Value="#15151B"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#2D2D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton Name="ToggleButton" Template="{StaticResource ComboBoxToggleButton}" Focusable="false" IsChecked="{Binding Path=IsDropDownOpen,Mode=TwoWay,RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press"/>
                            <ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" Margin="10,3,30,3" VerticalAlignment="Center" HorizontalAlignment="Left" />
                            <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Grid Name="DropDown" SnapsToDevicePixels="True" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <Border Name="DropDownBorder" Background="#15151B" BorderBrush="#2D2D37" BorderThickness="1" CornerRadius="6" Margin="0,2,0,0">
                                        <ScrollViewer Margin="4,6,4,6" SnapsToDevicePixels="True">
                                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained" />
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="HasItems" Value="false">
                                <Setter TargetName="DropDownBorder" Property="Height" Value="95"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="#15151B"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="8,5"/>
            <Style.Resources>
                <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#2D2D37"/>
                <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="White"/>
            </Style.Resources>
        </Style>

        <!-- Custom TabControl and TabItem Styles -->
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="0"/>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="HeaderTemplate">
                <Setter.Value>
                    <DataTemplate>
                        <ContentPresenter Content="{TemplateBinding Content}"/>
                    </DataTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" CornerRadius="6" Background="Transparent" Padding="16,8" Margin="0,0,8,10" BorderThickness="0" Cursor="Hand">
                            <ContentPresenter Name="ContentSite" ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#2A2A38"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="False">
                                <Setter Property="Foreground" Value="#8F8F9D"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="White"/>
                                <Setter TargetName="Border" Property="Background" Value="#20202A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Quick Task Button Style -->
        <Style x:Key="QuickTaskButton" TargetType="Button">
            <Setter Property="Background" Value="#252530"/>
            <Setter Property="Foreground" Value="#B0B0C0"/>
            <Setter Property="BorderBrush" Value="#2D2D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#1E90FF"/>
                                <Setter Property="Foreground" Value="White"/>
                                <Setter Property="BorderBrush" Value="#1E90FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Custom ScrollBar Style for Sleek Narrow Modern Look -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="MinWidth" Value="0"/>
            <Setter Property="MinHeight" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Name="Bg" Background="Transparent" SnapsToDevicePixels="true">
                            <Track Name="PART_Track" Orientation="{TemplateBinding Orientation}" IsEnabled="{TemplateBinding IsEnabled}">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageUpCommand">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Background="Transparent" />
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageDownCommand">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Background="Transparent" />
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb x:Name="ScrollThumb">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border Background="#5A5A6E" CornerRadius="3" />
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Orientation" Value="Vertical">
                                <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="true" />
                                <Setter TargetName="ScrollThumb" Property="MinHeight" Value="50" />
                                <Setter TargetName="ScrollThumb" Property="MinWidth" Value="0" />
                            </Trigger>
                            <Trigger Property="Orientation" Value="Horizontal">
                                <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="false" />
                                <Setter TargetName="ScrollThumb" Property="MinWidth" Value="50" />
                                <Setter TargetName="ScrollThumb" Property="MinHeight" Value="0" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Vertical">
                    <Setter Property="Width" Value="6"/>
                    <Setter Property="Height" Value="Auto"/>
                </Trigger>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="Height" Value="6"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Custom ScrollViewer Style to enforce custom ScrollBars -->
        <Style TargetType="ScrollViewer">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollViewer">
                        <Grid x:Name="Grid" Background="{TemplateBinding Background}">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <ScrollContentPresenter x:Name="PART_ScrollContentPresenter" CanContentScroll="{TemplateBinding CanContentScroll}" ContentTemplate="{TemplateBinding ContentTemplate}" Content="{TemplateBinding Content}" Grid.Column="0" Margin="{TemplateBinding Padding}" Grid.Row="0"/>
                            <ScrollBar x:Name="PART_VerticalScrollBar" Orientation="Vertical" AutomationProperties.AutomationId="VerticalScrollBar" Cursor="Arrow" Grid.Column="1" Maximum="{TemplateBinding ScrollableHeight}" Minimum="0" ViewportSize="{TemplateBinding ViewportHeight}" Grid.Row="0" Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}" Value="{TemplateBinding VerticalOffset}"/>
                            <ScrollBar x:Name="PART_HorizontalScrollBar" Orientation="Horizontal" AutomationProperties.AutomationId="HorizontalScrollBar" Cursor="Arrow" Grid.Column="0" Maximum="{TemplateBinding ScrollableWidth}" Minimum="0" ViewportSize="{TemplateBinding ViewportWidth}" Grid.Row="1" Visibility="{TemplateBinding ComputedHorizontalScrollBarVisibility}" Value="{TemplateBinding HorizontalOffset}"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    
    <Border Name="WindowBorder" CornerRadius="12" Background="#121216" BorderBrush="#2A2A35" BorderThickness="1.5">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="45"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            
            <!-- Title Bar -->
            <Grid Name="TitleBar" Grid.Row="0" Background="#16161D">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="15,0,0,0">
                    <Image Source="$logoIcoUri" Width="25" Height="25" Margin="0,3,8,0" VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality" Stretch="Uniform" UseLayoutRounding="True"/>
                    <TextBlock Text="DESKFLOW" FontSize="11" FontWeight="Bold" FontFamily="Segoe UI" Foreground="#E0E0EB" VerticalAlignment="Center"/>
                </StackPanel>
                
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,10,0">
                    <!-- Always on Top toggle icon button -->
                    <Button Name="BtnAlwaysOnTop" Content="📌" Width="32" Height="32" Background="Transparent" BorderBrush="Transparent" Foreground="#8F8F9D" FontSize="12" Margin="0,0,5,0" Cursor="Hand" ToolTip="Toggle Always on Top">
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="16">
                                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="border" Property="Background" Value="#2A2A38"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <!-- Minimize Button -->
                    <Button Name="BtnMinimize" Content="―" Width="32" Height="32" Background="Transparent" BorderBrush="Transparent" Foreground="#8F8F9D" FontSize="10" Margin="0,0,5,0" Cursor="Hand">
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="16">
                                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="border" Property="Background" Value="#2A2A38"/>
                                                    <Setter Property="Foreground" Value="White"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <!-- Close Button -->
                    <Button Name="BtnClose" Content="✕" Width="32" Height="32" Background="Transparent" BorderBrush="Transparent" Foreground="#8F8F9D" FontSize="12" Cursor="Hand">
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="16">
                                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="border" Property="Background" Value="#FF4D4D"/>
                                                    <Setter Property="Foreground" Value="White"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </Button.Style>
                    </Button>
                </StackPanel>
            </Grid>
            
            <!-- Main Content Area -->
            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="200"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                
                <!-- Sidebar -->
                <Border Grid.Column="0" Background="#16161D" BorderBrush="#2A2A35" BorderThickness="0,0,1,0">
                    <Grid Margin="10,20,10,20">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        
                        <!-- Nav Items -->
                        <StackPanel Grid.Row="0">
                            <Button Name="BtnNavDashboard" Style="{StaticResource SidebarButton}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="⚡" FontSize="14" Margin="0,0,12,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Dashboard" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="BtnNavTaskUpdate" Style="{StaticResource SidebarButton}">
                                <StackPanel Orientation="Horizontal">
                                     <TextBlock Text="$emailEmoji" FontSize="14" Margin="0,0,12,0" VerticalAlignment="Center"/>
                                     <TextBlock Text="Task Update" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="BtnNavHistory" Style="{StaticResource SidebarButton}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="🕒" FontSize="14" Margin="0,0,12,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="History Log" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="BtnNavAnalytics" Style="{StaticResource SidebarButton}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="📊" FontSize="14" Margin="0,0,12,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Analytics" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="BtnNavSettings" Style="{StaticResource SidebarButton}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="⚙️" FontSize="14" Margin="0,0,12,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Settings" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="BtnNavLicense" Style="{StaticResource SidebarButton}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="🔑" FontSize="14" Margin="0,0,12,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="License" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="BtnNavAbout" Style="{StaticResource SidebarButton}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="ℹ️" FontSize="14" Margin="0,0,12,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="About" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                        </StackPanel>
                        
                        <!-- Sidebar Footer -->
                        <StackPanel Grid.Row="1" Margin="5,0,5,0">
                            <Border BorderBrush="#2A2A35" BorderThickness="0,1,0,0" Padding="0,15,0,0">
                                <StackPanel>
                                    <TextBlock Name="TxtOfficeStatus" Text="Office Session: Inactive" Foreground="#8F8F9D" FontSize="11" FontWeight="SemiBold"/>
                                    <Grid Margin="0,5,0,0">
                                        <TextBlock Text="Worked Today:" Foreground="#8F8F9D" FontSize="10" VerticalAlignment="Center"/>
                                        <TextBlock Name="TxtWorkedTime" Text="00:00:00" Foreground="White" FontSize="14" FontWeight="Bold" HorizontalAlignment="Right"/>
                                    </Grid>
                                    <Grid Margin="0,5,0,0">
                                        <TextBlock Text="Total Break:" Foreground="#8F8F9D" FontSize="10" VerticalAlignment="Center"/>
                                        <TextBlock Name="TxtTotalBreak" Text="00:00:00" Foreground="#E15F41" FontSize="14" FontWeight="Bold" HorizontalAlignment="Right"/>
                                    </Grid>
                                    <Grid Margin="0,5,0,0">
                                        <TextBlock Text="Entry Time:" Foreground="#8F8F9D" FontSize="10" VerticalAlignment="Center"/>
                                        <TextBox Name="TxtEntryTime" Text="--:--:--" Foreground="#0984E3" FontSize="14" FontWeight="Bold" HorizontalAlignment="Right" Background="Transparent" BorderThickness="0" IsReadOnly="True" Cursor="Hand" ToolTip="Triple-click to edit entry time"/>
                                    </Grid>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </Grid>
                </Border>
                
                <!-- Content Area Tabs container -->
                <Grid Grid.Column="1" Margin="10">
                            <Grid Name="GridDashboard" Visibility="Visible">
                                <!-- 3-Column Symmetrical Layout -->
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>   <!-- Col 0: Clock / Break -->
                                        <ColumnDefinition Width="12"/>  <!-- Col 1: Spacing -->
                                        <ColumnDefinition Width="*"/>   <!-- Col 2: Calendar / Preview -->
                                        <ColumnDefinition Width="12"/>  <!-- Col 3: Spacing -->
                                        <ColumnDefinition Width="*"/>   <!-- Col 4: Timeline -->
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/> <!-- Top row for Clock and Calendar -->
                                        <RowDefinition Height="12"/>   <!-- Spacing -->
                                        <RowDefinition Height="*"/>    <!-- Bottom row for Break, Preview, Timeline -->
                                        <RowDefinition Height="12"/>   <!-- Spacing -->
                                        <RowDefinition Height="Auto"/> <!-- Multitasking Sessions -->
                                    </Grid.RowDefinitions>
                                    
                                    <!-- ROW 0 -->
                                                                        <!-- Clock & State Card -->
                                    <Border Grid.Row="0" Grid.Column="0" Style="{StaticResource CardBorder}" Margin="0" VerticalAlignment="Stretch" Padding="15">
                                            <StackPanel>
                                                <TextBlock Name="TxtDate" Text="Friday, July 10, 2026" Foreground="#8F8F9D" FontSize="13" FontWeight="SemiBold"/>
                                                <TextBlock Name="TxtClock" Text="12:18:39 PM" Foreground="White" FontSize="34" FontWeight="ExtraBold" Margin="0,4,0,12"/>
                                                
                                                <!-- Session Button -->
                                                <Button Name="BtnStartOffice" Content="Start Office" Height="42" Style="{StaticResource ModernButton}" Background="#3B82F6"/>
                                            </StackPanel>
                                        </Border>
                                    
                                                                        <!-- 30-day Calendar Card -->
                                    <Border Grid.Row="0" Grid.Column="2" Grid.ColumnSpan="3" Style="{StaticResource CardBorder}" Padding="15" Margin="0" VerticalAlignment="Stretch">
                                        <Grid>
                                            <Grid.RowDefinitions>
                                                <RowDefinition Height="Auto"/>
                                                <RowDefinition Height="Auto"/>
                                            </Grid.RowDefinitions>
                                            <TextBlock Name="TxtCalendarTitle" Grid.Row="0" Text="ATTENDANCE &amp; WORK HISTORY (CURRENT MONTH)" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="4,0,0,6"/>
                                            <ScrollViewer Name="CalendarScrollViewer" Grid.Row="1" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled">
                                                <StackPanel Name="CalendarContainer" Orientation="Horizontal" Margin="0,2,0,2">
                                                    <!-- Populated dynamically in script -->
                                                </StackPanel>
                                            </ScrollViewer>
                                        </Grid>
                                    </Border>
                                    
                                    <!-- ROW 2 -->
                                                                        <!-- Break Manager Card -->
                                    <Border Grid.Row="2" Grid.Column="0" Style="{StaticResource CardBorder}" Margin="0">
                                            <Grid>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="*"/>
                                                </Grid.RowDefinitions>
                                                
                                                <!-- Header Row with Add Button -->
                                                <Grid Grid.Row="0" Margin="0,0,0,12">
                                                    <TextBlock Text="BREAK MANAGER" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                                    <Button Name="BtnAddCustomBreak" Content="➕" Background="Transparent" Foreground="#89B4FA" BorderThickness="0" FontSize="12" HorizontalAlignment="Right" Cursor="Hand" ToolTip="Add Custom Status Button"/>
                                                </Grid>
                                                
                                                <!-- Scrollable area for all buttons -->
                                                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                                    <StackPanel>
                                                        <!-- Hidden elements to preserve script references -->
                                                        <Border Name="BorderLunchBadge" Visibility="Collapsed"/>
                                                        <TextBlock Name="TxtLunchTimer" Visibility="Collapsed"/>
                                                        <Border Name="BorderPrayerBadge" Visibility="Collapsed"/>
                                                        <TextBlock Name="TxtPrayerTimer" Visibility="Collapsed"/>
                                                        <Border Name="BorderComboBadge" Visibility="Collapsed"/>
                                                        <TextBlock Name="TxtComboTimer" Visibility="Collapsed"/>
                                                        
                                                        <!-- Grid Layout for Compact Buttons -->
                                                        <Grid Margin="0,0,0,8">
                                                            <Grid.RowDefinitions>
                                                                <RowDefinition Height="Auto"/>
                                                                <RowDefinition Height="Auto"/>
                                                            </Grid.RowDefinitions>
                                                            <Grid.ColumnDefinitions>
                                                                <ColumnDefinition Width="*"/>
                                                                <ColumnDefinition Width="10"/>
                                                                <ColumnDefinition Width="*"/>
                                                            </Grid.ColumnDefinitions>
                                                            
                                                            <!-- Lunch Button -->
                                                            <Button Name="BtnLunch" Grid.Row="0" Grid.Column="0" Content="🍽 Lunch" Style="{StaticResource ModernButton}" Height="36"/>
                                                            
                                                            <!-- Prayer Button -->
                                                            <Button Name="BtnPrayer" Grid.Row="0" Grid.Column="2" Content="🕌 Prayer" Style="{StaticResource ModernButton}" Height="36"/>
                                                            
                                                            <!-- Combo Button -->
                                                            <Button Name="BtnCombo" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="3" Content="🍽+🕌 Prayer + Lunch" Style="{StaticResource ModernButton}" Height="36" Margin="0,10,0,0"/>
                                                        </Grid>
                                                        
                                                        <!-- Dynamic custom buttons -->
                                                        <StackPanel Name="CustomBreaksPanel"/>
                                                    </StackPanel>
                                                </ScrollViewer>
                                            </Grid>
                                        </Border>
                                    
                                                                        <!-- Status Preview Card -->
                                    <Border Grid.Row="2" Grid.Column="2" Style="{StaticResource CardBorder}" Margin="0" Padding="15">
                                            <Grid>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="*"/>
                                                    <RowDefinition Height="Auto"/>
                                                </Grid.RowDefinitions>
                                                <TextBlock Grid.Row="0" Text="STATUS PREVIEW" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,8"/>
                                                <ListBox Name="ListPreview" Grid.Row="1" Background="#15151B" BorderThickness="1" BorderBrush="#2D2D37" Margin="0,0,0,10" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Auto">
                                                    <ListBox.ItemContainerStyle>
                                                        <Style TargetType="ListBoxItem">
                                                            <Setter Property="Background" Value="Transparent"/>
                                                            <Setter Property="BorderThickness" Value="0,0,0,1"/>
                                                            <Setter Property="BorderBrush" Value="#252530"/>
                                                            <Setter Property="Padding" Value="8,6"/>
                                                            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                                                            <Setter Property="Template">
                                                                <Setter.Value>
                                                                    <ControlTemplate TargetType="ListBoxItem">
                                                                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}">
                                                                            <ContentPresenter/>
                                                                        </Border>
                                                                    </ControlTemplate>
                                                                </Setter.Value>
                                                            </Setter>
                                                        </Style>
                                                    </ListBox.ItemContainerStyle>
                                                    <ListBox.ItemTemplate>
                                                        <DataTemplate>
                                                            <Grid>
                                                                <Grid.ColumnDefinitions>
                                                                    <ColumnDefinition Width="*"/>
                                                                    <ColumnDefinition Width="Auto"/>
                                                                </Grid.ColumnDefinitions>
                                                                <TextBlock Text="{Binding}" Foreground="White" FontSize="11" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                                                <Button Grid.Column="1" Tag="CopyBtn" Content="📋" Style="{StaticResource CopyLineButton}" VerticalAlignment="Center"/>
                                                            </Grid>
                                                        </DataTemplate>
                                                    </ListBox.ItemTemplate>
                                                </ListBox>
                                                <Grid Grid.Row="2">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Grid.Column="0" Text="Copy or clear preview" Foreground="#8F8F9D" FontSize="9" VerticalAlignment="Center"/>
                                                    <StackPanel Grid.Column="1" Orientation="Horizontal" Margin="6,0,0,0">
                                                        <Button Name="BtnCopyPreview" Content="Copy All" Padding="10,0" Height="28" Style="{StaticResource ModernButton}" Background="#252530" Foreground="White" BorderBrush="#2D2D37" BorderThickness="1"/>
                                                        <Button Name="BtnClearPreview" Content="Clear" Padding="10,0" Height="28" Margin="4,0,0,0" Style="{StaticResource ModernButton}" Background="#D63031"/>
                                                    </StackPanel>
                                                </Grid>
                                            </Grid>
                                        </Border>
                                    
                                                                        <!-- Today's Timeline Card -->
                                    <Border Grid.Row="2" Grid.Column="4" Style="{StaticResource CardBorder}" Margin="0" Padding="15">
                                            <Grid>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="*"/>
                                                </Grid.RowDefinitions>
                                                <TextBlock Grid.Row="0" Text="TODAY'S TIMELINE" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,8"/>
                                                <ListBox Name="ListTimeline" Grid.Row="1" Background="#15151B" BorderThickness="0" Foreground="#B0B0C0" FontSize="11" VerticalAlignment="Stretch">
                                                    <ListBox.ItemContainerStyle>
                                                        <Style TargetType="ListBoxItem">
                                                            <Setter Property="Padding" Value="4,2"/>
                                                            <Setter Property="Background" Value="Transparent"/>
                                                            <Setter Property="BorderThickness" Value="0"/>
                                                            <Setter Property="Foreground" Value="#B0B0C0"/>
                                                        </Style>
                                                    </ListBox.ItemContainerStyle>
                                                </ListBox>
                                            </Grid>
                                        </Border>
                                    
                                    <!-- ROW 4 -->
                                    <!-- Multitasking Sessions Card -->
                                    <Border Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="5" Style="{StaticResource CardBorder}" Margin="0">
                                        <Grid>
                                            <Grid.RowDefinitions>
                                                <RowDefinition Height="Auto"/>
                                                <RowDefinition Height="10"/>
                                                <RowDefinition Height="Auto"/>
                                                <RowDefinition Height="Auto"/>
                                            </Grid.RowDefinitions>
                                            
                                            <!-- Header Row with Buttons -->
                                            <Grid Grid.Row="0">
                                                <TextBlock Text="MULTITASKING SESSIONS" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                            <Button Name="BtnGenerateTaskUpdate" Content="&#x270F; Generate Update (Ctrl+E)" Background="#10AC84" Foreground="White" BorderThickness="0" Padding="12,5" FontSize="11" FontWeight="Bold" Cursor="Hand" Margin="0,0,10,0">
                                                <Button.Resources>
                                                    <Style TargetType="Border">
                                                        <Setter Property="CornerRadius" Value="4"/>
                                                    </Style>
                                                </Button.Resources>
                                            </Button>
                                                    <Button Name="BtnAddTaskRow" Content="&#x2795; Add Task Row" Background="#6C5CE7" Foreground="White" BorderThickness="0" Padding="12,5" FontSize="11" FontWeight="Bold" Cursor="Hand">
                                                        <Button.Resources>
                                                            <Style TargetType="Border">
                                                                <Setter Property="CornerRadius" Value="4"/>
                                                            </Style>
                                                        </Button.Resources>
                                                    </Button>
                                                </StackPanel>
                                            </Grid>
                                            
                                            
                                            <!-- Dynamic Tasks List -->
                                            <ScrollViewer Grid.Row="2" Height="130" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                                <StackPanel VerticalAlignment="Top">
                                                    <!-- Headers -->
                                                    <Grid Margin="0,0,0,0" Height="15">
                                                        <Grid.ColumnDefinitions>
                                                            <ColumnDefinition Width="105"/>
                                                            <ColumnDefinition Width="6"/>
                                                            <ColumnDefinition Width="80"/> 
                                                            <ColumnDefinition Width="6"/>
                                                            <ColumnDefinition Width="*"/>  
                                                            <ColumnDefinition Width="6"/>
                                                            <ColumnDefinition Width="150"/>
                                                            <ColumnDefinition Width="6"/>
                                                            <ColumnDefinition Width="120"/>
                                                            <ColumnDefinition Width="6"/>
                                                            <ColumnDefinition Width="90"/> 
                                                            <ColumnDefinition Width="6"/>
                                                            <ColumnDefinition Width="80"/> 
                                                        </Grid.ColumnDefinitions>
                                                        <TextBlock Grid.Column="0" Text="#" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" HorizontalAlignment="Center"/>
                                                        <TextBlock Grid.Column="2" Text="PROJECT" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" HorizontalAlignment="Left" Margin="4,0,0,0"/>
                                                        <TextBlock Grid.Column="4" Text="TASK DETAILS" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" HorizontalAlignment="Left" Margin="4,0,0,0"/>
                                                        <TextBlock Grid.Column="6" Text="LINK / URL" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" HorizontalAlignment="Left" Margin="4,0,0,0"/>
                                                        <TextBlock Grid.Column="8" Text="STATUS" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" HorizontalAlignment="Left" Margin="4,0,0,0"/>
                                                        <TextBlock Grid.Column="10" Text="TRACKED TIME" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" HorizontalAlignment="Center"/>
                                                        <TextBlock Grid.Column="12" Text="SYNC" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" HorizontalAlignment="Center"/>
                                                    </Grid>
                                                    <!-- Separator line under column headers -->
                                                    <Rectangle Height="1" Fill="#2A2A35" Margin="0,5,0,6"/>
                                                    <StackPanel Name="TasksContainer"/>
                                                </StackPanel>
                                            </ScrollViewer>
                                            
                                            <!-- Quick Tasks -->
                                            <ScrollViewer Grid.Row="3" MaxHeight="62" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="0,5,0,0">
                                                <WrapPanel Name="PanelQuickTasks" Margin="0">
                                                    <!-- Quick task buttons will be generated dynamically -->
                                                </WrapPanel>
                                            </ScrollViewer>
                                        </Grid>
                                    </Border>
                                </Grid>
                            </Grid>
                    
                    <!-- Overlay Grid for Idle Prompt -->
                        <Grid Name="GridIdlePrompt" Visibility="Collapsed" Background="#E60B0B0F" Grid.ColumnSpan="5">
                            <Border Style="{StaticResource CardBorder}" Width="380" Height="250" VerticalAlignment="Center" HorizontalAlignment="Center" Background="#1E1E26" BorderBrush="#6C5CE7" BorderThickness="2" CornerRadius="12">
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Margin="15">
                                    <TextBlock Text="⏰ Auto Idle Detection" Foreground="#6C5CE7" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,10"/>
                                    <TextBlock Name="TxtIdleMessage" Text="You were away for 12 minutes." Foreground="White" FontSize="14" HorizontalAlignment="Center" TextAlignment="Center" Margin="0,0,0,20" TextWrapping="Wrap"/>
                                    <TextBlock Text="Would you like to log this period as a break?" Foreground="#8F8F9D" FontSize="11" HorizontalAlignment="Center" Margin="0,0,0,15"/>
                                    <UniformGrid Columns="2" Rows="2" Height="80" Width="300">
                                        <Button Name="BtnIdleLunch" Content="🍽 Lunch Break" Style="{StaticResource ModernButton}" Background="#10AC84" Margin="4"/>
                                        <Button Name="BtnIdlePrayer" Content="🕌 Prayer Break" Style="{StaticResource ModernButton}" Background="#10AC84" Margin="4"/>
                                        <Button Name="BtnIdleCombo" Content="🍽+🕌 Combo Break" Style="{StaticResource ModernButton}" Background="#10AC84" Margin="4"/>
                                        <Button Name="BtnIdleIgnore" Content="❌ Ignore" Style="{StaticResource ModernButton}" Background="#D63031" Margin="4"/>
                                    </UniformGrid>
                                </StackPanel>
                            </Border>
                        </Grid>
                
                <!-- TAB 2: HISTORY LOG VIEW -->
                    <Grid Name="GridHistory" Visibility="Collapsed">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="280"/>
                            <ColumnDefinition Width="20"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        
                        <!-- Left Column: list of days -->
                        <Border Grid.Column="0" Style="{StaticResource CardBorder}" Margin="0">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <TextBlock Grid.Row="0" Text="SELECT HISTORY DAY" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,10"/>
                                <ListBox Name="ListHistoryDays" Grid.Row="1" Background="#15151B" BorderThickness="1" BorderBrush="#2D2D37" Foreground="White" FontSize="12">
                                    <ListBox.ItemContainerStyle>
                                        <Style TargetType="ListBoxItem">
                                            <Setter Property="Padding" Value="10,8"/>
                                            <Setter Property="Cursor" Value="Hand"/>
                                        </Style>
                                    </ListBox.ItemContainerStyle>
                                </ListBox>
                                <Button Name="BtnExportHistory" Grid.Row="2" Content="Export Selected (TXT)" Margin="0,10,0,0" Height="38" Style="{StaticResource ModernButton}" Background="#3B82F6"/>
                            </Grid>
                        </Border>
                        
                        <!-- Right Column: details of selected day -->
                        <Border Grid.Column="2" Style="{StaticResource CardBorder}" Margin="0">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                
                                <Grid Grid.Row="0" Margin="0,0,0,15">
                                    <TextBlock Text="DAY SUMMARY DETAILS" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                        <TextBlock Name="TxtHistoryWorked" Text="Worked: 00:00:00" Foreground="#10AC84" FontSize="14" FontWeight="Bold" Margin="0,0,15,0"/>
                                        <TextBlock Name="TxtHistoryBreak" Text="Break: 00:00:00" Foreground="#E15F41" FontSize="14" FontWeight="Bold"/>
                                    </StackPanel>
                                </Grid>
                                
                                <StackPanel Grid.Row="1" Margin="0,0,0,15">
                                    <TextBlock Text="TASK UPDATE" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" Margin="0,0,0,5"/>
                                    <TextBox Name="TxtHistoryTasks" Style="{StaticResource ModernTextBox}" Height="80" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                                </StackPanel>
                                
                                <Grid Grid.Row="2">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="20"/>
                                        <ColumnDefinition Width="240"/>
                                    </Grid.ColumnDefinitions>
                                    
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="GENERATED STATUS PREVIEW" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" Margin="0,0,0,5"/>
                                        <TextBox Name="TxtHistoryPreview" Style="{StaticResource ModernTextBox}" Height="280" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                                    </StackPanel>
                                    
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="DAY TIMELINE" Foreground="#8F8F9D" FontSize="9" FontWeight="Bold" Margin="0,0,0,5"/>
                                        <ListBox Name="ListHistoryTimeline" Height="280" Background="#15151B" BorderBrush="#2D2D37" BorderThickness="1" Foreground="#B0B0C0" FontSize="11"/>
                                    </StackPanel>
                                </Grid>
                            </Grid>
                        </Border>
                    </Grid>
                    
                    <!-- TAB: ANALYTICS VIEW -->
                    <Grid Name="GridAnalytics" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="20"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <!-- Summary Cards Row -->
                        <Grid Grid.Row="0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="20"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="20"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            
                            <Border Grid.Column="0" Style="{StaticResource CardBorder}" Padding="15" Margin="0">
                                <StackPanel>
                                    <TextBlock Text="AVERAGE WORK HOURS" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                    <TextBlock Name="TxtAvgWorkHours" Text="0.0 hrs" Foreground="#3B82F6" FontSize="26" FontWeight="ExtraBold"/>
                                </StackPanel>
                            </Border>
                            <Border Grid.Column="2" Style="{StaticResource CardBorder}" Padding="15" Margin="0">
                                <StackPanel>
                                    <TextBlock Text="AVERAGE BREAK TIME" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                    <TextBlock Name="TxtAvgBreakTime" Text="0m" Foreground="#E15F41" FontSize="26" FontWeight="ExtraBold"/>
                                </StackPanel>
                            </Border>
                            <Border Grid.Column="4" Style="{StaticResource CardBorder}" Padding="15" Margin="0">
                                <StackPanel>
                                    <TextBlock Text="DAYS LOGGED" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                    <TextBlock Name="TxtDaysLogged" Text="0 days" Foreground="#10AC84" FontSize="26" FontWeight="ExtraBold"/>
                                </StackPanel>
                            </Border>
                        </Grid>
                        
                        <!-- Chart Card -->
                        <Border Grid.Row="2" Style="{StaticResource CardBorder}" Padding="20" Margin="0">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <TextBlock Grid.Row="0" Text="WORK HOURS HISTORY (LAST 7 SESSIONS)" Foreground="#8F8F9D" FontSize="11" FontWeight="Bold" Margin="0,0,0,20"/>
                                
                                <Grid Grid.Row="1" Height="220" VerticalAlignment="Bottom">
                                    <!-- Grid Lines -->
                                    <StackPanel VerticalAlignment="Stretch">
                                        <Border BorderBrush="#1F1F27" BorderThickness="0,0,0,1" Height="55"/>
                                        <Border BorderBrush="#1F1F27" BorderThickness="0,0,0,1" Height="55"/>
                                        <Border BorderBrush="#1F1F27" BorderThickness="0,0,0,1" Height="55"/>
                                        <Border BorderBrush="#1F1F27" BorderThickness="0,0,0,1" Height="55"/>
                                    </StackPanel>
                                    
                                    <!-- Bars UniformGrid -->
                                    <UniformGrid Name="GridBarChart" Columns="7" Rows="1" VerticalAlignment="Bottom" Height="200" Margin="10,0,10,0">
                                        <!-- Bars will be generated dynamically -->
                                    </UniformGrid>
                                </Grid>
                            </Grid>
                        </Border>
                    </Grid>
                    
                    <!-- TAB 3: SETTINGS VIEW -->
                    <Grid Name="GridSettings" Visibility="Collapsed">
                        <Border Style="{StaticResource CardBorder}" Margin="0">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                
                                <TabControl Grid.Row="0">
                                    <!-- TAB 1: App Settings -->
                                    <TabItem Header="$gearEmoji Application Settings">
                                        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,10,0,0">
                                            <StackPanel Margin="5">
                                                <TextBlock Text="APPLICATION CONFIGURATIONS" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,15"/>
                                                
                                                <CheckBox Name="ChkSetMinimizeToTray" IsChecked="True" Content="Close button minimizes to system tray" Foreground="White" FontSize="12" Margin="0,0,0,12" Cursor="Hand"/>
                                                <CheckBox Name="ChkSetStartWithWindows" IsChecked="True" Content="Start application automatically when Windows signs in" Foreground="White" FontSize="12" Margin="0,0,0,12" Cursor="Hand"/>
                                                <CheckBox Name="ChkSetAutoDetectSession" IsChecked="True" Content="Auto start/stop office session (Start on Good Morning, Stop on Leaving from office)" Foreground="White" FontSize="12" Margin="0,0,0,20" Cursor="Hand"/>
                                                
                                                <TextBlock Text="QUICK TASKS TEMPLATES" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,5,0,5"/>
                                                <TextBlock Text="Enter quick tasks separated by comma (,) to show on Dashboard:" Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                <TextBox Name="TxtSetQuickTasks" Style="{StaticResource ModernTextBox}" Height="60" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="0,0,0,20"/>
                                            </StackPanel>
                                        </ScrollViewer>
                                    </TabItem>
                                    
                                    <!-- TAB 2: Off-Days Configuration -->
                                    <TabItem Header="$calendarEmoji Off-Days">
                                        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,10,0,0">
                                            <StackPanel Margin="5">
                                                <TextBlock Text="OFF-DAYS CONFIGURATION" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,8"/>
                                                <TextBlock Text="Highlight weekends and holidays on the calendar strip. Select weekly off-days:" Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                <WrapPanel Margin="0,0,0,12">
                                                    <CheckBox Name="ChkOffSun" Content="Sunday" Foreground="White" Margin="0,0,15,5" Cursor="Hand"/>
                                                    <CheckBox Name="ChkOffMon" Content="Monday" Foreground="White" Margin="0,0,15,5" Cursor="Hand"/>
                                                    <CheckBox Name="ChkOffTue" Content="Tuesday" Foreground="White" Margin="0,0,15,5" Cursor="Hand"/>
                                                    <CheckBox Name="ChkOffWed" Content="Wednesday" Foreground="White" Margin="0,0,15,5" Cursor="Hand"/>
                                                    <CheckBox Name="ChkOffThu" Content="Thursday" Foreground="White" Margin="0,0,15,5" Cursor="Hand"/>
                                                    <CheckBox Name="ChkOffFri" Content="Friday" Foreground="White" Margin="0,0,15,5" Cursor="Hand"/>
                                                    <CheckBox Name="ChkOffSat" Content="Saturday" Foreground="White" Margin="0,0,15,5" Cursor="Hand"/>
                                                </WrapPanel>
                                                
                                                <!-- Dynamic Off-Day Rules (Occurrence Rules) -->
                                                <TextBlock Text="RECURRING OFF-DAY RULES" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,15,0,5"/>
                                                <TextBlock Text="Configure complex off-day rules (e.g. 2nd and 4th Saturday). Select day, check weeks and click Add." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                <Grid Margin="0,0,0,8">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="120"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <ComboBox Name="CmbOffRuleDay" Style="{StaticResource ModernComboBox}" Height="30" Grid.Column="0">
                                                        <ComboBoxItem Content="Saturday" IsSelected="True"/>
                                                        <ComboBoxItem Content="Sunday"/>
                                                        <ComboBoxItem Content="Monday"/>
                                                        <ComboBoxItem Content="Tuesday"/>
                                                        <ComboBoxItem Content="Wednesday"/>
                                                        <ComboBoxItem Content="Thursday"/>
                                                        <ComboBoxItem Content="Friday"/>
                                                    </ComboBox>
                                                    <WrapPanel Grid.Column="1" VerticalAlignment="Center" Margin="10,0,10,0">
                                                        <CheckBox Name="ChkOffWeek1" Content="1st" Foreground="White" Margin="0,0,8,0" Cursor="Hand"/>
                                                        <CheckBox Name="ChkOffWeek2" Content="2nd" Foreground="White" Margin="0,0,8,0" Cursor="Hand"/>
                                                        <CheckBox Name="ChkOffWeek3" Content="3rd" Foreground="White" Margin="0,0,8,0" Cursor="Hand"/>
                                                        <CheckBox Name="ChkOffWeek4" Content="4th" Foreground="White" Margin="0,0,8,0" Cursor="Hand"/>
                                                        <CheckBox Name="ChkOffWeek5" Content="Last" Foreground="White" Cursor="Hand"/>
                                                    </WrapPanel>
                                                    <Button Name="BtnAddOffRule" Grid.Column="2" Content="+ Add" Background="#2E2E38" Foreground="#89B4FA" BorderThickness="0" Padding="8,4" FontSize="11" FontWeight="Bold" Cursor="Hand" Height="30"/>
                                                </Grid>
                                                <StackPanel Name="OffRulesPanel" Margin="0,0,0,15"/>

                                                <!-- Custom Specific Holidays Picker -->
                                                <TextBlock Text="SPECIFIC HOLIDAYS / CUSTOM OFF-DAYS" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,5,0,5"/>
                                                <TextBlock Text="Pick a custom holiday date from calendar, write a label (e.g. 'Eid' or 'Christmas') and click Add." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                <Grid Margin="0,0,0,8">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="130"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <DatePicker Name="DpOffHoliday" Height="30" Grid.Column="0" BorderThickness="1" BorderBrush="#2D2D37" Background="#15151B" Foreground="White"/>
                                                    <TextBox Name="TxtOffHolidayLabel" Style="{StaticResource ModernTextBox}" Height="30" Grid.Column="1" Margin="10,0,10,0" Tag="HolidayLabel" Padding="5,4"/>
                                                    <Button Name="BtnAddOffHoliday" Grid.Column="2" Content="+ Add" Background="#2E2E38" Foreground="#89B4FA" BorderThickness="0" Padding="8,4" FontSize="11" FontWeight="Bold" Cursor="Hand" Height="30"/>
                                                </Grid>
                                                <StackPanel Name="OffHolidaysPanel" Margin="0,0,0,15"/>
                                            </StackPanel>
                                        </ScrollViewer>
                                    </TabItem>

                                    <!-- TAB 3: Message Templates -->
                                    <TabItem Header="$msgEmoji Message Templates">
                                        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,10,0,0">
                                            <StackPanel Margin="5">
                                                <TextBlock Text="STATUS MESSAGE TEMPLATES" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Customize templates using tags: {current_time} for timestamps and {duration} for break minutes." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,20"/>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Good Morning:" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetGoodMorning" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Lunch Break (Start):" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetLunchStart" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Lunch Break (Return):" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetLunchReturn" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Prayer Break (Start):" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetPrayerStart" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Prayer Break (Return):" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetPrayerReturn" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Lunch &amp; Prayer (Start):" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetComboStart" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Lunch &amp; Prayer (Return):" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetComboReturn" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>
                                                
                                                <Border BorderBrush="#2A2A35" BorderThickness="0,1,0,0" Margin="0,10,0,15"/>
                                                
                                                <TextBlock Text="TASK UPDATE TEMPLATE" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Customize task update template using tags: {working_hours} and {task_update}." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                <TextBox Name="TxtSetTaskUpdateTemplate" Style="{StaticResource ModernTextBox}" Height="150" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="0,0,0,20"/>
                                                
                                                <TextBlock Text="LEAVING FROM OFFICE TEMPLATE" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Customize leaving from office template (e.g. using {current_time} tag)." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                <TextBox Name="TxtSetLeavingOfficeTemplate" Style="{StaticResource ModernTextBox}" Height="120" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                                            </StackPanel>
                                        </ScrollViewer>
                                    </TabItem>
                                    
                                    <!-- TAB 4: Webhook Integrations (Teams, Slack, Discord) -->
                                    <TabItem Header="$plugEmoji Webhook Integrations">
                                        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,10,0,0">
                                            <StackPanel Margin="5">
                                                <TextBlock Text="WEBHOOK INTEGRATION" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Automatically send status updates to Teams, Slack, or Discord." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,12"/>
                                                
                                                <CheckBox Name="ChkSetWebhookEnabled" IsChecked="True" Content="Enable Webhook Integration" Foreground="White" FontSize="12" Margin="0,0,0,15" Cursor="Hand"/>
                                                
                                                <TextBlock Text="DISPLAY NAME" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Your name as it will appear in Slack/Discord messages (instead of 'incoming-webhook'):" Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                <TextBox Name="TxtSetWebhookDisplayName" Style="{StaticResource ModernTextBox}" Height="35" Margin="0,0,0,15"/>
                                                
                                                <Grid Margin="0,0,0,15">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="150"/>
                                                    </Grid.ColumnDefinitions>
                                                    
                                                    <StackPanel Margin="0,0,10,0">
                                                        <TextBlock Text="AVATAR ICON URL (OPTIONAL)" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                        <TextBlock Text="URL to an image (.png/.jpg) to use as avatar icon:" Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                        <TextBox Name="TxtSetWebhookAvatarUrl" Style="{StaticResource ModernTextBox}" Height="35"/>
                                                    </StackPanel>
                                                    
                                                    <StackPanel Grid.Column="1">
                                                        <TextBlock Text="OR SELECT EMOJI" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                        <TextBlock Text="Quick emoji picker:" Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,8"/>
                                                        <ComboBox Name="CmbSetWebhookEmoji" Style="{StaticResource ModernComboBox}" Height="35">
                                                            <ComboBoxItem Content="None" IsSelected="True"/>
                                                            <ComboBoxItem Content="Sunny ☀️"/>
                                                            <ComboBoxItem Content="Smile 😊"/>
                                                            <ComboBoxItem Content="Work 💻"/>
                                                            <ComboBoxItem Content="Briefcase 💼"/>
                                                            <ComboBoxItem Content="Ghost 👻"/>
                                                            <ComboBoxItem Content="Coffee ☕"/>
                                                            <ComboBoxItem Content="Rocket 🚀"/>
                                                            <ComboBoxItem Content="Wizard 🧙"/>
                                                            <ComboBoxItem Content="Calendar 📅"/>
                                                            <ComboBoxItem Content="Alert ⚠️"/>
                                                        </ComboBox>
                                                    </StackPanel>
                                                </Grid>
                                                
                                                <Grid Margin="0,0,0,5">
                                                     <Grid.ColumnDefinitions>
                                                         <ColumnDefinition Width="*"/>
                                                         <ColumnDefinition Width="Auto"/>
                                                     </Grid.ColumnDefinitions>
                                                     <TextBlock Text="WEBHOOK URL(S)" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                                                     <Button Name="BtnAddWebhookUrl" Grid.Column="1" Content="➕ Add URL" Background="#2E2E38" Foreground="#89B4FA" BorderThickness="0" Padding="8,4" FontSize="11" FontWeight="Bold" Cursor="Hand">
                                                         <Button.Resources>
                                                             <Style TargetType="Border">
                                                                 <Setter Property="CornerRadius" Value="4"/>
                                                             </Style>
                                                         </Button.Resources>
                                                     </Button>
                                                 </Grid>
                                                
                                                <ScrollViewer MaxHeight="200" VerticalScrollBarVisibility="Auto" Margin="0,0,0,20">
                                                     <StackPanel Name="WebhookUrlsPanel"/>
                                                 </ScrollViewer>
                                                
                                                <Border BorderBrush="#2A2A35" BorderThickness="1" CornerRadius="6" Padding="12" Background="#16161D">
                                                    <StackPanel>
                                                        <TextBlock Text="💡 Quick Guide:" Foreground="#89B4FA" FontSize="11" FontWeight="Bold" Margin="0,0,0,6"/>
                                                        <TextBlock Text="• Slack: Create an Incoming Webhook in your Slack Workspace and paste it." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,4"/>
                                                        <TextBlock Text="• Discord: Create a Webhook in Channel Settings and paste it (auto-configured)." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,4"/>
                                                        <TextBlock Text="• MS Teams: Configure an Incoming Webhook workflow on your channel." Foreground="#8F8F9D" FontSize="11"/>
                                                    </StackPanel>
                                                </Border>
                                            </StackPanel>
                                        </ScrollViewer>
                                    </TabItem>
                                    
                                    <!-- TAB 5: Google Sheets Integration -->
                                    <TabItem Header="📊 Google Sheets">
                                        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,10,0,0">
                                            <StackPanel Margin="5">
                                                <TextBlock Text="GOOGLE SHEETS AUTOSYNC CONFIGURATION" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Set up your Google Sheets WebApp integration for automated background session tracking." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,20"/>
                                                
                                                <!-- User Name -->
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="User Name:" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetUserName" Grid.Column="1" Style="{StaticResource ModernTextBox}" Height="30"/>
                                                </Grid>
                                                
                                                <!-- User Role -->
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="User Role:" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetUserRole" Grid.Column="1" Style="{StaticResource ModernTextBox}" Height="30"/>
                                                </Grid>
                                                
                                                <!-- WebApp Script URL -->
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Google WebApp URL:" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetGoogleScriptUrl" Grid.Column="1" Style="{StaticResource ModernTextBox}" Height="30"/>
                                                </Grid>
                                                
                                                <!-- Google Sheet URL -->
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Google Sheet URL:" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetGoogleSheetUrl" Grid.Column="1" Style="{StaticResource ModernTextBox}" Height="30"/>
                                                </Grid>
                                            </StackPanel>
                                        </ScrollViewer>
                                    </TabItem>

                                    <!-- TAB 6: Email & Authentication -->
                                    <TabItem Header="$emailEmoji Email &amp; Authentication">
                                        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,10,0,0">
                                            <StackPanel Margin="5">
                                                <TextBlock Text="GMAIL CONFIGURATION" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Enter your Gmail address and 16-character App Password to send automated emails." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,20"/>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                     </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Gmail Address:" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtSetGmailAddress" Grid.Column="1" Style="{StaticResource ModernTextBox}"/>
                                                </Grid>
                                                
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Gmail App Password:" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <PasswordBox Name="PwdSetGmailAppPassword" Grid.Column="1" Background="#1A1A24" Foreground="White" BorderBrush="#2A2A35" BorderThickness="1.5" Padding="12,8" FontSize="13">
                                                        <PasswordBox.Resources>
                                                            <Style TargetType="Border">
                                                                <Setter Property="CornerRadius" Value="6"/>
                                                            </Style>
                                                        </PasswordBox.Resources>
                                                    </PasswordBox>
                                                </Grid>

                                                <Border BorderBrush="#2A2A35" BorderThickness="0,1,0,0" Margin="0,10,0,15"/>

                                                <TextBlock Text="RECIPIENT EMAIL" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Where should the daily task updates be sent? (Comma separate multiple emails)" Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,20"/>
                                                
                                                <Grid Margin="0,0,0,3">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="30"/>
                                                        <ColumnDefinition Width="150"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="70"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Set Name" Grid.Column="1" Foreground="#8F8F9D" FontSize="10" Margin="0,0,5,5"/>
                                                    <TextBlock Text="Recipient Emails (Comma separated)" Grid.Column="2" Foreground="#8F8F9D" FontSize="10" Margin="0,0,5,5"/>
                                                </Grid>
                                                <Grid Margin="0,0,0,12">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="30"/>
                                                        <ColumnDefinition Width="150"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="70"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBox Name="TxtSetEmailSetName" Grid.Column="1" Margin="0,0,5,0" Style="{StaticResource ModernTextBox}" ToolTip="e.g. Boss"/>
                                                    <TextBox Name="TxtSetEmailSetEmails" Grid.Column="2" Margin="0,0,5,0" Style="{StaticResource ModernTextBox}" ToolTip="Email(s)"/>
                                                    <Button Name="BtnAddEmailSet" Grid.Column="3" Content="+ Add" Background="#2E2E38" Foreground="#89B4FA" BorderThickness="0" Padding="8,4" FontSize="11" FontWeight="Bold" Cursor="Hand" Height="30"/>
                                                </Grid>
                                                <StackPanel Name="EmailSetsPanel" Margin="0,0,0,15"/>

                                                <Border BorderBrush="#2A2A35" BorderThickness="0,1,0,0" Margin="0,10,0,15"/>

                                                <!-- EMAIL TABLE COLOR -->
                                                <TextBlock Text="EMAIL TABLE COLOR" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Choose the background color for the email task table rows. Default is the classic pink tone (#e0a3c1)." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,15" TextWrapping="Wrap"/>
                                                <Grid Margin="0,0,0,5">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="180"/>
                                                        <ColumnDefinition Width="115"/>
                                                        <ColumnDefinition Width="38"/>
                                                        <ColumnDefinition Width="*"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Text="Table Row Color:" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                                    <TextBox Name="TxtTableBodyColor" Grid.Column="1" Style="{StaticResource ModernTextBox}" ToolTip="Enter hex color e.g. #e0a3c1" MaxLength="9" Margin="0,0,6,0"/>
                                                    <Border Name="BdrTableBodyColorPreview" Grid.Column="2" Width="32" Height="32" CornerRadius="5" Background="#e0a3c1" BorderBrush="#555" BorderThickness="1" VerticalAlignment="Center" Margin="0,0,6,0"/>
                                                    <Button Name="BtnPickTableBodyColor" Grid.Column="3" Content="&#x1F3A8; Pick Color" Background="#2E2E38" Foreground="#89B4FA" BorderThickness="0" Padding="10,6" FontSize="11" FontWeight="Bold" Cursor="Hand" HorizontalAlignment="Left" Height="30"/>
                                                </Grid>

                                                <Border BorderBrush="#2A2A35" BorderThickness="0,1,0,0" Margin="0,15,0,15"/>

                                                <TextBlock Text="HUBSTAFF ACCOUNTS" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                                <TextBlock Text="Add multiple Hubstaff accounts to use in your daily reports." Foreground="#8F8F9D" FontSize="11" Margin="0,0,0,15"/>

                                                <Grid Margin="0,0,0,3">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="30"/>
                                                        <ColumnDefinition Width="100"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="60"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBlock Grid.Column="1" Text="Account Name" Foreground="#5E5E6E" FontSize="10" Margin="2,0,0,0"/>
                                                    <TextBlock Grid.Column="2" Text="Hubstaff Email" Foreground="#5E5E6E" FontSize="10" Margin="2,0,0,0"/>
                                                    <TextBlock Grid.Column="3" Text="Hubstaff Password" Foreground="#5E5E6E" FontSize="10" Margin="2,0,0,0"/>
                                                </Grid>
                                                <Grid Margin="0,0,0,8">
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="30"/>
                                                        <ColumnDefinition Width="100"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="60"/>
                                                    </Grid.ColumnDefinitions>
                                                    <TextBox Name="TxtSetHubstaffName" Grid.Column="1" Margin="0,0,5,0" Style="{StaticResource ModernTextBox}" ToolTip="e.g. Work"/>
                                                    <TextBox Name="TxtSetHubstaffEmailList" Grid.Column="2" Margin="0,0,5,0" Style="{StaticResource ModernTextBox}" ToolTip="Email"/>
                                                    <PasswordBox Name="TxtSetHubstaffPassList" Grid.Column="3" Margin="0,0,5,0" Background="#15151B" Foreground="White" BorderBrush="#2D2D37" BorderThickness="1" Padding="10,4" VerticalContentAlignment="Center" FontSize="11" CaretBrush="White" ToolTip="Password"/>
                                                    <Button Name="BtnAddHubstaffAccount" Grid.Column="4" Content="+ Add" Background="#2E2E38" Foreground="#89B4FA" BorderThickness="0" Padding="8,4" FontSize="11" FontWeight="Bold" Cursor="Hand" Height="30"/>
                                                </Grid>
                                                <StackPanel Name="HubstaffAccountsPanel" Margin="0,0,0,15"/>
                                            </StackPanel>
                                        </ScrollViewer>
                                    </TabItem>
                                    
                                 </TabControl>
                                
                            </Grid>
                        </Border>
                    </Grid>
                    
                                        <!-- Grid Task Update -->
                    <Grid Name="GridTaskUpdate" Visibility="Collapsed">
                        <Border Style="{StaticResource CardBorder}" Margin="0">
                            <Grid Margin="15">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <!-- Header -->
                                <StackPanel Grid.Row="0" Margin="0,0,0,15">
                                    <TextBlock Text="AUTOMATED DAILY TASK REPORT" Foreground="White" FontSize="16" FontWeight="Bold"/>
                                    <TextBlock Text="Compose and send your daily task updates directly to email." Foreground="#8F8F9D" FontSize="11" Margin="0,3,0,0"/>
                                </StackPanel>

                                <!-- Hubstaff Controls -->
                                <Grid Grid.Row="1" Margin="0,0,0,15">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="20"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="150"/>
                                        <ColumnDefinition Width="20"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="150"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>

                                    <!-- Screenshot Attachment -->
                                    <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                                        <Button Name="BtnTaskUpdateBrowseSS" Content="$folderEmoji Attach Hubstaff Screenshot" Style="{StaticResource ModernButton}" Width="210" Height="30" FontSize="10" Padding="15,0" Background="#2E2E38"/>
                                        <TextBlock Name="TxtTaskUpdateSSPath" Text="No screenshot attached" Foreground="#8F8F9D" FontSize="11" Margin="10,0,0,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="150"/>
                                        <Button Name="BtnTaskUpdateRemoveSS" Content="✖" Style="{StaticResource ModernButton}" Width="24" Height="24" Padding="0" Margin="5,0,0,0" Background="Transparent" Foreground="#FF4D4D" Visibility="Collapsed" ToolTip="Remove Screenshot"/>
                                    </StackPanel>

                                    <!-- Hubstaff Account Selection -->
                                    <TextBlock Grid.Column="2" Text="Hubstaff Account: " Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                    <ComboBox Name="CmbTaskUpdateHubstaffAccount" Grid.Column="3" Style="{StaticResource ModernComboBox}" Height="30" FontSize="12"/>
                                    
                                    <!-- Email Set Selection -->
                                    <TextBlock Grid.Column="5" Text="To: " Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                    <ComboBox Name="CmbTaskUpdateEmailSet" Grid.Column="6" Style="{StaticResource ModernComboBox}" Height="30" FontSize="12"/>
                                </Grid>

                                <!-- Template Content Text Box -->
                                <Grid Grid.Row="2" Margin="0,0,0,15">
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="*"/>
                                    </Grid.RowDefinitions>
                                    <!-- Subject Field -->
                                    <TextBlock Grid.Row="0" Text="EMAIL SUBJECT (EDITABLE)" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                    <TextBox Name="TxtTaskUpdateSubject" Grid.Row="1" Style="{StaticResource ModernTextBox}" FontSize="13" FontFamily="Consolas" Margin="0,0,0,10"/>
                                    <!-- Body Field -->
                                    <TextBlock Grid.Row="2" Text="EMAIL CONTENT (EDITABLE)" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                                    <TextBox Name="TxtTaskUpdateEmailContent" Grid.Row="3" Style="{StaticResource ModernTextBox}" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontSize="13" FontFamily="Consolas" VerticalContentAlignment="Top" Padding="10,10"/>
                                </Grid>

                                <!-- Actions -->
                                <Grid Grid.Row="3">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <Button Name="BtnTaskUpdateSend" Grid.Column="1" Content="$emailEmoji SEND EMAIL UPDATE" Style="{StaticResource ModernButton}" Background="#D33A6A" Width="200" Height="40" FontSize="12" FontWeight="Bold"/>
                                </Grid>
                            </Grid>
                        </Border>
                    </Grid>
                    
                    <!-- Grid License & Activation View -->
                    <Grid Name="GridLicense" Visibility="Collapsed">
                        <Border Style="{StaticResource CardBorder}" Margin="0">
                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                <StackPanel Margin="24">
                                    <!-- Header -->
                                    <StackPanel Margin="0,0,0,20">
                                        <TextBlock Text="DeskFlow Activation" FontSize="18" FontWeight="Bold" Foreground="White"/>
                                        <TextBlock Text="Smart Office Activity Manager — License, Fingerprinting &amp; Pro Access" FontSize="12" Foreground="#8F8F9D" Margin="0,4,0,0"/>
                                    </StackPanel>

                                    <!-- License Status Banner with Trial ProgressBar & Masked Key Badge -->
                                    <Border Background="#1E1E2A" BorderBrush="#2D2D3F" BorderThickness="1" CornerRadius="12" Padding="20" Margin="0,0,0,20">
                                        <StackPanel>
                                            <Grid Margin="0,0,0,16">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="Auto"/>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                </Grid.ColumnDefinitions>
                                                <Border Grid.Column="0" Width="44" Height="44" CornerRadius="12" Background="#10AC84" Margin="0,0,16,0">
                                                    <TextBlock Name="TxtLicStatusIcon" Text="🛡️" FontSize="22" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                                </Border>
                                                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                                    <TextBlock Name="TxtLicStatusTitle" Text="30-Day Free Trial Active" FontSize="16" FontWeight="Bold" Foreground="#38BDF8"/>
                                                    <TextBlock Name="TxtLicStatusDesc" Text="Activate your DeskFlow Pro license key to unlock unlimited access and priority updates." FontSize="12" Foreground="#C5C5D3" Margin="0,4,0,0"/>
                                                </StackPanel>
                                                <Border Name="BorderLicMaskedKey" Grid.Column="2" Background="#153322" BorderBrush="#10AC84" BorderThickness="1" CornerRadius="8" Padding="12,6" VerticalAlignment="Center" Visibility="Collapsed">
                                                    <TextBlock Name="TxtLicMaskedKey" Text="DESK-****-****-8888" FontSize="12" FontFamily="Consolas, Monospace" FontWeight="Bold" Foreground="#A3E635"/>
                                                </Border>
                                            </Grid>

                                            <!-- Trial Progress Bar Container -->
                                            <StackPanel Name="PanelLicProgress" Margin="0,4,0,0">
                                                <Grid Margin="0,0,0,8">
                                                    <TextBlock Text="TRIAL PERIOD PROGRESS" FontSize="10" FontWeight="Bold" Foreground="#8F8F9D"/>
                                                    <TextBlock Name="TxtLicProgressValue" Text="30 Days Remaining (100%)" FontSize="11" FontWeight="Bold" Foreground="#38BDF8" HorizontalAlignment="Right"/>
                                                </Grid>
                                                <ProgressBar Name="ProgLicTrial" Height="8" Minimum="0" Maximum="100" Value="100" Background="#14141E" BorderThickness="0">
                                                    <ProgressBar.Resources>
                                                        <Style TargetType="Border">
                                                            <Setter Property="CornerRadius" Value="4"/>
                                                        </Style>
                                                    </ProgressBar.Resources>
                                                    <ProgressBar.Foreground>
                                                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                                            <GradientStop Color="#38BDF8" Offset="0"/>
                                                            <GradientStop Color="#8B5CF6" Offset="1"/>
                                                        </LinearGradientBrush>
                                                    </ProgressBar.Foreground>
                                                </ProgressBar>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Hardware Fingerprint Card -->
                                    <Border Background="#16161D" BorderBrush="#2A2A35" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,0,0,20">
                                        <Grid>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <StackPanel Grid.Column="0">
                                                <TextBlock Text="MACHINE IDENTIFIER (HWID)" FontSize="10" FontWeight="Bold" Foreground="#8F8F9D" Margin="0,0,0,4"/>
                                                <TextBlock Name="TxtLicMachineId" Text="GEN-00000000000000000000000000000000" FontSize="12" FontFamily="Consolas, Monospace" Foreground="#A78BFA" FontWeight="SemiBold"/>
                                            </StackPanel>
                                            <Button Name="BtnLicCopyHwid" Content="📋 COPY ID" Grid.Column="1" Height="32" Padding="12,0" Background="#262636" Foreground="#E0E0EB" FontSize="11" FontWeight="Bold" BorderThickness="0" Cursor="Hand" VerticalAlignment="Center"/>
                                        </Grid>
                                    </Border>

                                    <!-- Activation Input Form -->
                                    <StackPanel Name="PanelActivationInput">
                                        <Border Background="#16161D" BorderBrush="#2A2A35" BorderThickness="1" CornerRadius="12" Padding="20">
                                            <StackPanel>
                                                <TextBlock Text="ACTIVATE PRO LICENSE" FontSize="14" FontWeight="Bold" Foreground="White" Margin="0,0,0,16"/>

                                                <TextBlock Text="LICENSE KEY" FontSize="11" FontWeight="SemiBold" Foreground="#8F8F9D" Margin="0,0,0,6"/>
                                                <TextBox Name="TxtLicKey" Height="40" Background="#1A1A24" Foreground="White" BorderBrush="#2D2D3F" BorderThickness="1" Padding="12,8" FontSize="13" FontFamily="Consolas, Monospace" Margin="0,0,0,16" VerticalContentAlignment="Center"/>

                                                <TextBlock Text="REGISTERED EMAIL ADDRESS" FontSize="11" FontWeight="SemiBold" Foreground="#8F8F9D" Margin="0,0,0,6"/>
                                                <TextBox Name="TxtLicEmail" Height="40" Background="#1A1A24" Foreground="White" BorderBrush="#2D2D3F" BorderThickness="1" Padding="12,8" FontSize="13" Margin="0,0,0,16" VerticalContentAlignment="Center"/>

                                                <Border Name="BorderLicToast" Background="#261A1A" BorderBrush="#FF4D4D" BorderThickness="1" CornerRadius="8" Padding="12" Visibility="Collapsed" Margin="0,0,0,16">
                                                    <TextBlock Name="TxtLicToast" Text="Status notification" FontSize="12" Foreground="#FF8080" TextWrapping="Wrap" HorizontalAlignment="Center"/>
                                                </Border>

                                                <StackPanel Orientation="Horizontal">
                                                    <Button Name="BtnLicActivate" Content="ACTIVATE PRO" Height="40" Padding="24,0" Background="#10AC84" Foreground="White" FontWeight="Bold" BorderThickness="0" Cursor="Hand" Margin="0,0,12,0"/>
                                                    <Button Name="BtnLicTransfer" Content="⚡ REQUEST SHIFT" Height="40" Padding="16,0" Background="#8B5CF6" Foreground="White" FontWeight="Bold" BorderThickness="0" Cursor="Hand" Visibility="Collapsed" Margin="0,0,12,0"/>
                                                    <Button Name="BtnLicRefresh" Content="🔄 REFRESH STATUS" Height="40" Padding="16,0" Background="#10AC84" Foreground="White" FontWeight="Bold" BorderThickness="0" Cursor="Hand" Visibility="Collapsed"/>
                                                </StackPanel>
                                            </StackPanel>
                                        </Border>
                                    </StackPanel>

                                    <!-- Deactivation Area (Shown when Pro License is Active) -->
                                    <StackPanel Name="PanelDeactivation" Visibility="Collapsed">
                                        <Border Background="#16161D" BorderBrush="#2A2A35" BorderThickness="1" CornerRadius="12" Padding="20">
                                            <StackPanel>
                                                <TextBlock Text="MANAGE LICENSE KEY" FontSize="14" FontWeight="Bold" Foreground="White" Margin="0,0,0,8"/>
                                                <TextBlock Text="Your device is permanently licensed. Click deactivate to transfer this license to another PC." FontSize="12" Foreground="#8F8F9D" Margin="0,0,0,16"/>
                                                <Button Name="BtnLicDeactivate" Content="⚠️  DEACTIVATE LICENSE" Height="40" Padding="20,0" Background="#EF4444" Foreground="White" FontWeight="Bold" BorderThickness="0" Cursor="Hand" HorizontalAlignment="Left"/>
                                            </StackPanel>
                                        </Border>
                                    </StackPanel>
                                </StackPanel>
                            </ScrollViewer>
                        </Border>
                    </Grid>
                    
                    <!-- Grid About View -->
                    <Grid Name="GridAbout" Visibility="Collapsed">
                        <Border Style="{StaticResource CardBorder}" Margin="0">
                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                <Grid VerticalAlignment="Center" HorizontalAlignment="Center" Margin="0,40,0,40">
                                    <Border Background="#16161D" BorderBrush="#2A2A35" BorderThickness="1.5" CornerRadius="12" Width="360" Padding="30">
                                        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                                            <Image Source="$logoUri" Width="64" Height="64" HorizontalAlignment="Center" Margin="0,0,0,15" RenderOptions.BitmapScalingMode="HighQuality"/>
                                            <TextBlock Text="DeskFlow" FontSize="20" FontWeight="Bold" FontFamily="Segoe UI" Foreground="White" HorizontalAlignment="Center" Margin="0,0,0,3"/>
                                            <TextBlock Text="Smart Office Activity Manager" FontSize="11" FontWeight="Normal" Foreground="White" HorizontalAlignment="Center" Margin="0,0,0,6"/>
                                            <TextBlock Name="TxtAppVersion" Text="Version 1.0.3" FontSize="11" Foreground="#8F8F9D" HorizontalAlignment="Center" Margin="0,0,0,20"/>
                                            <Rectangle Height="1" Fill="#2A2A35" Margin="0,0,0,20"/>
                                            <TextBlock FontSize="12" FontWeight="SemiBold" Foreground="#8F8F9D" HorizontalAlignment="Center" Margin="0,0,0,4">
                                                Developed by <Hyperlink Name="LnkCrossTech" NavigateUri="https://crosstech.lemonsqueezy.com/" Foreground="White" TextDecorations="None" Cursor="Hand">Cross Tech</Hyperlink>
                                            </TextBlock>
                                            <TextBlock Text="by Magnetieght EU" FontSize="10" Foreground="#6b7280" HorizontalAlignment="Center" Margin="0,0,0,15"/>
                                            <Button Name="BtnCheckUpdate" Content="Check for updates" Foreground="#8F8F9D" FontSize="12" FontWeight="SemiBold" Background="Transparent" BorderThickness="0" Cursor="Hand" HorizontalAlignment="Center">
                                                <Button.Template>
                                                    <ControlTemplate TargetType="Button">
                                                        <TextBlock Name="txt" Text="{TemplateBinding Content}" Foreground="{TemplateBinding Foreground}" FontSize="{TemplateBinding FontSize}" FontWeight="{TemplateBinding FontWeight}" HorizontalAlignment="Center"/>
                                                        <ControlTemplate.Triggers>
                                                            <Trigger Property="IsMouseOver" Value="True">
                                                                <Setter TargetName="txt" Property="Foreground" Value="#82AAFF"/>
                                                                <Setter TargetName="txt" Property="TextDecorations" Value="Underline"/>
                                                            </Trigger>
                                                        </ControlTemplate.Triggers>
                                                    </ControlTemplate>
                                                </Button.Template>
                                            </Button>
                                        </StackPanel>
                                    </Border>
                                </Grid>
                            </ScrollViewer>
                        </Border>
                    </Grid>
                    
                </Grid>
            </Grid>
            
            <!-- Toast Notification Overlay -->
            <Border Name="BorderToast" Grid.Row="1" CornerRadius="8" Background="#10AC84" BorderBrush="#155724" BorderThickness="1" 
                    VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,25" Padding="18,10" 
                    Visibility="Collapsed" Panel.ZIndex="999" MaxWidth="350">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Name="TxtToastIcon" Text="✓" Foreground="White" FontSize="14" FontWeight="Bold" Margin="0,0,8,0" VerticalAlignment="Center"/>
                    <TextBlock Name="TxtToastMessage" Text="Copied to Clipboard" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                </StackPanel>
            </Border>
            
        </Grid>
    </Border>
</Window>
"@

# 3. Load XAML Window
$reader = New-Object System.Xml.XmlReaderSettings
$reader.ConformanceLevel = [System.Xml.ConformanceLevel]::Fragment
$xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
$global:Window = $window  # Store globally for access inside function closures/timer ticks

# Get Controls References
$btnClose = $window.FindName("BtnClose")
$btnMinimize = $window.FindName("BtnMinimize")
$btnAlwaysOnTop = $window.FindName("BtnAlwaysOnTop")

$btnNavDashboard = $window.FindName("BtnNavDashboard")
$btnNavHistory = $window.FindName("BtnNavHistory")
$btnNavAnalytics = $window.FindName("BtnNavAnalytics")
$btnNavSettings = $window.FindName("BtnNavSettings")

$gridDashboard = $window.FindName("GridDashboard")
$gridHistory = $window.FindName("GridHistory")
$gridAnalytics = $window.FindName("GridAnalytics")
$gridSettings = $window.FindName("GridSettings")

# Analytics controls
$txtAvgWorkHours = $window.FindName("TxtAvgWorkHours")
$txtAvgBreakTime = $window.FindName("TxtAvgBreakTime")
$txtDaysLogged = $window.FindName("TxtDaysLogged")
$gridBarChart = $window.FindName("GridBarChart")

$txtClock = $window.FindName("TxtClock")
$txtDate = $window.FindName("TxtDate")
$btnStartOffice = $window.FindName("BtnStartOffice")
$txtOfficeStatus = $window.FindName("TxtOfficeStatus")
$txtWorkedTime = $window.FindName("TxtWorkedTime")
$txtTotalBreak = $window.FindName("TxtTotalBreak")

$btnLunch = $window.FindName("BtnLunch")
$borderLunchBadge = $window.FindName("BorderLunchBadge")
$txtLunchTimer = $window.FindName("TxtLunchTimer")

$btnPrayer = $window.FindName("BtnPrayer")
$borderPrayerBadge = $window.FindName("BorderPrayerBadge")
$txtPrayerTimer = $window.FindName("TxtPrayerTimer")

$btnCombo = $window.FindName("BtnCombo")
    $btnLunch.Content = "$global:LunchEmoji Lunch"
    $btnPrayer.Content = "$global:PrayerEmoji Prayer"
    $btnCombo.Content = "$global:LunchEmoji+$global:PrayerEmoji Prayer + Lunch"
    $lnkCrossTech = $window.FindName("LnkCrossTech")
    if ($null -ne $lnkCrossTech) {
        $lnkCrossTech.Add_Click({
            [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo("https://crosstech.lemonsqueezy.com/") -Property @{ UseShellExecute = $true }))
        })
    }
    $txtAppVersion = $window.FindName("TxtAppVersion")
    if ($null -ne $txtAppVersion) { $txtAppVersion.Text = "Version $global:AppVersion" }
    $global:BtnCheckUpdate = $window.FindName("BtnCheckUpdate")
    if ($null -ne $global:BtnCheckUpdate) {
        $global:BtnCheckUpdate.Add_Click({
            if (-not [string]::IsNullOrEmpty($global:PendingDownloadUrl)) {
                Start-DownloadAndInstallUpdate -url $global:PendingDownloadUrl
            } else {
                Check-ForUpdates -IsManual $true
            }
        })
    }
$borderComboBadge = $window.FindName("BorderComboBadge")
$txtComboTimer = $window.FindName("TxtComboTimer")
$btnAddCustomBreak = $window.FindName("BtnAddCustomBreak")
$panelCustomBreaks = $window.FindName("CustomBreaksPanel")

$txtTaskUpdate = $window.FindName("TxtTaskUpdate")
$panelQuickTasks = $window.FindName("PanelQuickTasks")
$listPreview = $window.FindName("ListPreview")
$btnGenerateTaskUpdate = $window.FindName("BtnGenerateTaskUpdate")
$btnCopyPreview = $window.FindName("BtnCopyPreview")
$btnClearPreview = $window.FindName("BtnClearPreview")
$listTimeline = $window.FindName("ListTimeline")

$btnNavLicense = $window.FindName("BtnNavLicense")
$gridLicense = $window.FindName("GridLicense")
$btnNavAbout = $window.FindName("BtnNavAbout")
$gridAbout = $window.FindName("GridAbout")
$txtLicStatusIcon = $window.FindName("TxtLicStatusIcon")
$txtLicStatusTitle = $window.FindName("TxtLicStatusTitle")
$txtLicStatusDesc = $window.FindName("TxtLicStatusDesc")
$panelLicProgress = $window.FindName("PanelLicProgress")
$progLicTrial = $window.FindName("ProgLicTrial")
$txtLicProgressValue = $window.FindName("TxtLicProgressValue")
$txtLicMachineId = $window.FindName("TxtLicMachineId")
$btnLicCopyHwid = $window.FindName("BtnLicCopyHwid")
$txtLicKey = $window.FindName("TxtLicKey")
$txtLicEmail = $window.FindName("TxtLicEmail")
$borderLicToast = $window.FindName("BorderLicToast")
$txtLicToast = $window.FindName("TxtLicToast")
$btnLicActivate = $window.FindName("BtnLicActivate")
$btnLicTransfer = $window.FindName("BtnLicTransfer")
$btnLicRefresh = $window.FindName("BtnLicRefresh")
$panelActivationInput = $window.FindName("PanelActivationInput")
$panelDeactivation = $window.FindName("PanelDeactivation")
$btnLicDeactivate = $window.FindName("BtnLicDeactivate")
$borderLicMaskedKey = $window.FindName("BorderLicMaskedKey")
$txtLicMaskedKey = $window.FindName("TxtLicMaskedKey")

# Calendar & off-days control bindings
$calendarContainer = $window.FindName("CalendarContainer")
$global:CalendarContainer = $calendarContainer
$calendarScrollViewer = $window.FindName("CalendarScrollViewer")
$global:CalendarScrollViewer = $calendarScrollViewer
$txtCalendarTitle = $window.FindName("TxtCalendarTitle")
$global:TxtCalendarTitle = $txtCalendarTitle
$chkOffSun = $window.FindName("ChkOffSun")
$chkOffMon = $window.FindName("ChkOffMon")
$chkOffTue = $window.FindName("ChkOffTue")
$chkOffWed = $window.FindName("ChkOffWed")
$chkOffThu = $window.FindName("ChkOffThu")
$chkOffFri = $window.FindName("ChkOffFri")
$chkOffSat = $window.FindName("ChkOffSat")
$offRulesPanel = $window.FindName("OffRulesPanel")
$offHolidaysPanel = $window.FindName("OffHolidaysPanel")
$cmbOffRuleDay = $window.FindName("CmbOffRuleDay")
$chkOffWeek1 = $window.FindName("ChkOffWeek1")
$chkOffWeek2 = $window.FindName("ChkOffWeek2")
$chkOffWeek3 = $window.FindName("ChkOffWeek3")
$chkOffWeek4 = $window.FindName("ChkOffWeek4")
$chkOffWeek5 = $window.FindName("ChkOffWeek5")
$btnAddOffRule = $window.FindName("BtnAddOffRule")
$dpOffHoliday = $window.FindName("DpOffHoliday")
$txtOffHolidayLabel = $window.FindName("TxtOffHolidayLabel")
$btnAddOffHoliday = $window.FindName("BtnAddOffHoliday")

# Calendar mouse wheel: redirect to horizontal scroll (no vertical in calendar strip)
if ($null -ne $global:CalendarScrollViewer) {
    $global:CalendarScrollViewer.Add_PreviewMouseWheel({
        param($sv, $e)
        $newOffset = $sv.HorizontalOffset - ($e.Delta * 0.5)
        $sv.ScrollToHorizontalOffset($newOffset)
        $e.Handled = $true
    })
}

$borderToast = $window.FindName("BorderToast")
$txtToastIcon = $window.FindName("TxtToastIcon")
$txtToastMessage = $window.FindName("TxtToastMessage")

# Idle prompt controls
$gridIdlePrompt = $window.FindName("GridIdlePrompt")
$txtIdleMessage = $window.FindName("TxtIdleMessage")
$btnIdleLunch = $window.FindName("BtnIdleLunch")
$btnIdlePrayer = $window.FindName("BtnIdlePrayer")
$btnIdleCombo = $window.FindName("BtnIdleCombo")
$btnIdleIgnore = $window.FindName("BtnIdleIgnore")

$listHistoryDays = $window.FindName("ListHistoryDays")
$btnExportHistory = $window.FindName("BtnExportHistory")
$txtHistoryWorked = $window.FindName("TxtHistoryWorked")
$txtHistoryBreak = $window.FindName("TxtHistoryBreak")
$txtHistoryTasks = $window.FindName("TxtHistoryTasks")
$txtHistoryPreview = $window.FindName("TxtHistoryPreview")
$listHistoryTimeline = $window.FindName("ListHistoryTimeline")

$txtSetGoodMorning = $window.FindName("TxtSetGoodMorning")
$txtSetLunchStart = $window.FindName("TxtSetLunchStart")
$txtSetLunchReturn = $window.FindName("TxtSetLunchReturn")
$txtSetPrayerStart = $window.FindName("TxtSetPrayerStart")
$txtSetPrayerReturn = $window.FindName("TxtSetPrayerReturn")
$txtSetComboStart = $window.FindName("TxtSetComboStart")
$txtSetComboReturn = $window.FindName("TxtSetComboReturn")
$txtSetTaskUpdateTemplate = $window.FindName("TxtSetTaskUpdateTemplate")
$txtSetLeavingOfficeTemplate = $window.FindName("TxtSetLeavingOfficeTemplate")
$chkSetMinimizeToTray = $window.FindName("ChkSetMinimizeToTray")
$chkSetStartWithWindows = $window.FindName("ChkSetStartWithWindows")
$chkSetAutoDetectSession = $window.FindName("ChkSetAutoDetectSession")
$txtSetQuickTasks = $window.FindName("TxtSetQuickTasks")
$chkSetWebhookEnabled = $window.FindName("ChkSetWebhookEnabled")
$txtSetWebhookDisplayName = $window.FindName("TxtSetWebhookDisplayName")
$txtSetWebhookAvatarUrl = $window.FindName("TxtSetWebhookAvatarUrl")
$cmbSetWebhookEmoji = $window.FindName("CmbSetWebhookEmoji")
$webhookUrlsPanel = $window.FindName("WebhookUrlsPanel")
$btnAddWebhookUrl = $window.FindName("BtnAddWebhookUrl")
$btnNavTaskUpdate = $window.FindName("BtnNavTaskUpdate")
$gridTaskUpdate = $window.FindName("GridTaskUpdate")
$btnTaskUpdateBrowseSS = $window.FindName("BtnTaskUpdateBrowseSS")
$btnTaskUpdateRemoveSS = $window.FindName("BtnTaskUpdateRemoveSS")
$txtTaskUpdateSSPath = $window.FindName("TxtTaskUpdateSSPath")
$cmbTaskUpdateHubstaffAccount = $window.FindName("CmbTaskUpdateHubstaffAccount")
$cmbTaskUpdateEmailSet = $window.FindName("CmbTaskUpdateEmailSet")
$txtTaskUpdateSubject = $window.FindName("TxtTaskUpdateSubject")
$txtTaskUpdateEmailContent = $window.FindName("TxtTaskUpdateEmailContent")
$btnTaskUpdateSend = $window.FindName("BtnTaskUpdateSend")

# Settings Gmail and Hubstaff Bindings
$txtSetGmailAddress = $window.FindName("TxtSetGmailAddress")
$pwdSetGmailAppPassword = $window.FindName("PwdSetGmailAppPassword")
$txtSetEmailSetName = $window.FindName("TxtSetEmailSetName")
$txtSetEmailSetEmails = $window.FindName("TxtSetEmailSetEmails")
$btnAddEmailSet = $window.FindName("BtnAddEmailSet")
$emailSetsPanel = $window.FindName("EmailSetsPanel")
$txtSetHubstaffName = $window.FindName("TxtSetHubstaffName")
$txtSetHubstaffEmailList = $window.FindName("TxtSetHubstaffEmailList")
$txtSetHubstaffPassList = $window.FindName("TxtSetHubstaffPassList")
$btnAddHubstaffAccount = $window.FindName("BtnAddHubstaffAccount")
$hubstaffAccountsPanel = $window.FindName("HubstaffAccountsPanel")
$txtTableBodyColor = $window.FindName("TxtTableBodyColor")
$bdrTableBodyColorPreview = $window.FindName("BdrTableBodyColorPreview")
$btnPickTableBodyColor = $window.FindName("BtnPickTableBodyColor")

# Multitasking & Google Sheets UI Bindings
$txtSetUserName = $window.FindName("TxtSetUserName")
$txtSetUserRole = $window.FindName("TxtSetUserRole")
$txtSetGoogleScriptUrl = $window.FindName("TxtSetGoogleScriptUrl")
$txtSetGoogleSheetUrl = $window.FindName("TxtSetGoogleSheetUrl")
$txtEntryTime = $window.FindName("TxtEntryTime")

if ($null -ne $txtEntryTime) {
    # Triple-Click Secret Entry Time Editor
    $txtEntryTime.Add_PreviewMouseDown({
        param($src, $ev)
        if ($ev.ClickCount -eq 3) {
            $ev.Handled = $true
            $ctrl = $src
            # Secret unlock for edit
            $ctrl.IsReadOnly = $false
            $ctrl.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D2D37")
            $ctrl.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0984E3")
            $ctrl.BorderThickness = New-Object System.Windows.Thickness(1)
            $ctrl.SelectAll()
            $ctrl.Focus()
        }
    })

    $txtEntryTime.Add_KeyDown({
        param($src, $ev)
        if ($ev.Key -eq [System.Windows.Input.Key]::Enter) {
            $ev.Handled = $true
            $src.MoveFocus((New-Object System.Windows.Input.TraversalRequest([System.Windows.Input.FocusNavigationDirection]::Next)))
        }
    })

    $txtEntryTime.Add_LostFocus({
        $ctrl = $this
        if (-not $ctrl.IsReadOnly) {
            # Lock control back
            $ctrl.IsReadOnly = $true
            $ctrl.Background = [System.Windows.Media.Brushes]::Transparent
            $ctrl.BorderThickness = New-Object System.Windows.Thickness(0)
            
            $text = $ctrl.Text.Trim()
            $parsedDt = [DateTime]::MinValue
            $success = [DateTime]::TryParse($text, [ref]$parsedDt)
            
            if (-not $success) {
                if ($text -match '^\s*(\d{1,2}):(\d{2})\s*(AM|PM)?\s*$' -or $text -match '^\s*(\d{1,2}):(\d{2})\s*(am|pm)?\s*$') {
                    $h = [int]$matches[1]
                    $m = [int]$matches[2]
                    $ampm = $matches[3]
                    if ($null -ne $ampm -and $ampm -ne "") {
                        if ($ampm.ToUpper() -eq "PM" -and $h -lt 12) { $h += 12 }
                        if ($ampm.ToUpper() -eq "AM" -and $h -eq 12) { $h = 0 }
                    }
                    $today = Get-Date
                    try {
                        $parsedDt = New-Object DateTime($today.Year, $today.Month, $today.Day, $h, $m, 0)
                        $success = $true
                    } catch {}
                }
            } else {
                $today = Get-Date
                $parsedDt = New-Object DateTime($today.Year, $today.Month, $today.Day, $parsedDt.Hour, $parsedDt.Minute, 0)
            }
            
            if ($success) {
                $global:EntryTime = $parsedDt
                if ($global:OfficeStarted) {
                    $global:OfficeStartTime = $parsedDt
                }
                if ($null -ne $global:SavedEntryTime) {
                    $global:SavedEntryTime = $parsedDt
                }
                
                $formattedStr = $parsedDt.ToString("hh:mm tt")
                $ctrl.Text = $formattedStr
                
                try { Update-TaskUpdatePreview } catch {}
                Show-Toast "✅ Entry time updated to $formattedStr" "#0984E3" "#0B4F8A"
            } else {
                if ($null -ne $global:EntryTime) {
                    $ctrl.Text = $global:EntryTime.ToString("hh:mm tt")
                } elseif ($null -ne $global:SavedEntryTime) {
                    $ctrl.Text = $global:SavedEntryTime.ToString("hh:mm tt")
                } else {
                    $ctrl.Text = "--:--:--"
                }
                Show-Toast "⚠️ Invalid time format! Use e.g. 09:30 AM" "#FF4D4D" "#8B0000"
            }
        }
    })
}

$tasksContainer = $window.FindName("TasksContainer")
$btnAddTaskRow = $window.FindName("BtnAddTaskRow")

$btnAddTaskRow.Add_Click({
    if (-not $global:OfficeStarted) {
        Show-Toast "⚠ Please start office session first" "#FF9F43" "#A04000"
        return
    }
    Add-TaskRow -ProjectCode "" -Details "" -Link "" -Status "In Progress" -Duration "00:00:00" -Synced $false
})



$btnAddOffRule.Add_Click({
    if ($cmbOffRuleDay.SelectedItem -ne $null) {
        $day = $cmbOffRuleDay.SelectedItem.Content.ToString()
        $weeks = @()
        if ($chkOffWeek1.IsChecked) { $weeks += "1st" }
        if ($chkOffWeek2.IsChecked) { $weeks += "2nd" }
        if ($chkOffWeek3.IsChecked) { $weeks += "3rd" }
        if ($chkOffWeek4.IsChecked) { $weeks += "4th" }
        if ($chkOffWeek5.IsChecked) { $weeks += "Last" }
        
        if ($weeks.Count -gt 0) {
            Add-OffRuleUI -day $day -weeks $weeks
            # Reset
            $chkOffWeek1.IsChecked = $false
            $chkOffWeek2.IsChecked = $false
            $chkOffWeek3.IsChecked = $false
            $chkOffWeek4.IsChecked = $false
            $chkOffWeek5.IsChecked = $false
        } else {
            [System.Windows.MessageBox]::Show($window, "Please select at least one week occurrence (1st, 2nd, etc.).", "Selection Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    }
})

$btnAddOffHoliday.Add_Click({
    if ($dpOffHoliday.SelectedDate -ne $null) {
        $dateStr = $dpOffHoliday.SelectedDate.ToString("yyyy-MM-dd")
        $label = $txtOffHolidayLabel.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = "Holiday"
        }
        
        $exists = $false
        foreach ($child in $offHolidaysPanel.Children) {
            if ($child.Tag -ne $null -and $child.Tag.date -eq $dateStr) {
                $exists = $true
                break
            }
        }
        
        if (-not $exists) {
            Add-OffHolidayUI -dateStr $dateStr -label $label
            $txtOffHolidayLabel.Text = ""
            $dpOffHoliday.SelectedDate = $null
        } else {
            [System.Windows.MessageBox]::Show($window, "This date is already added as a holiday.", "Duplicate Date", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    } else {
        [System.Windows.MessageBox]::Show($window, "Please select a date from the calendar.", "Selection Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
})

$btnAddWebhookUrl.Add_Click({
    Add-WebhookUrlInput
})

$cmbSetWebhookEmoji.Add_SelectionChanged({
    if ($cmbSetWebhookEmoji.SelectedItem -ne $null) {
        $selText = $cmbSetWebhookEmoji.SelectedItem.Content.ToString()
        if ($selText -like "None*") {
            $txtSetWebhookAvatarUrl.IsEnabled = $true
        } else {
            $txtSetWebhookAvatarUrl.IsEnabled = $false
        }
    }
})

# Setup Brushes
$brushConv = New-Object System.Windows.Media.BrushConverter
$purpleBrush = $brushConv.ConvertFromString("#6C5CE7")
$redBrush = $brushConv.ConvertFromString("#D63031")
$greenBrush = $brushConv.ConvertFromString("#10AC84")
$blueBrush = $brushConv.ConvertFromString("#3B82F6")
$greyBrush = $brushConv.ConvertFromString("#8F8F9D")
$navActiveBrush = $brushConv.ConvertFromString("#22222D")
$whiteBrush = [System.Windows.Media.Brushes]::White
$transparentBrush = [System.Windows.Media.Brushes]::Transparent

# Title Bar Drag
$titleBar = $window.FindName("TitleBar")
$titleBar.Add_MouseLeftButtonDown({
    $window.DragMove()
})

# Close and Minimize
$btnClose.Add_Click({
    $window.Close()
})
$btnMinimize.Add_Click({
    $window.WindowState = [System.Windows.WindowState]::Minimized
})

# 4. Helper Logic Functions

# Toast notification system
function Show-Toast {
    param(
        [string]$message,
        [string]$backgroundHex = "#10AC84",
        [string]$borderHex = "#155724"
    )
    
    $window.Dispatcher.Invoke({
        $borderToast.Background = $brushConv.ConvertFromString($backgroundHex)
        $borderToast.BorderBrush = $brushConv.ConvertFromString($borderHex)
        $cleanMsg = if ([string]::IsNullOrWhiteSpace($message)) { "" } else { $message.Trim() }
        
        # Determine appropriate single icon
        $icon = "✓"
        if ($cleanMsg -like "*Error*" -or $cleanMsg -like "*Failed*" -or $cleanMsg -like "*Deactivated*" -or $cleanMsg -like "*Reset*" -or $cleanMsg -like "*Unauthorized*") {
            $icon = "⚠️"
        } elseif ($cleanMsg -like "*📌*") {
            $icon = "📌"
        } elseif ($cleanMsg -like "*⚡*") {
            $icon = "⚡"
        } elseif ($cleanMsg -like "*🎉*") {
            $icon = "🎉"
        } elseif ($cleanMsg -like "*⚠️*" -or $cleanMsg -like "*⚠*") {
            $icon = "⚠️"
        } elseif ($cleanMsg -like "*✓*" -or $cleanMsg -like "*✔*") {
            $icon = "✓"
        }

        # Strip any leading duplicate icons/symbols from cleanMsg string so only TxtToastIcon displays it once
        $cleanText = [System.Text.RegularExpressions.Regex]::Replace($cleanMsg, '^[^\w\d\(\)]+', '').Trim()
        if ([string]::IsNullOrWhiteSpace($cleanText)) { $cleanText = $cleanMsg }

        $txtToastIcon.Text = $icon
        $txtToastIcon.Foreground = $whiteBrush
        $txtToastMessage.Text = $cleanText
        
        $borderToast.Visibility = [System.Windows.Visibility]::Visible
        
        if ($null -ne $global:ToastTimer) {
            $global:ToastTimer.Stop()
        }
        
        $global:ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:ToastTimer.Interval = [TimeSpan]::FromSeconds(3.5)
        $global:ToastTimer.Add_Tick({
            $borderToast.Visibility = [System.Windows.Visibility]::Collapsed
            $global:ToastTimer.Stop()
            $global:ToastTimer = $null
        })
        $global:ToastTimer.Start()
    })
}

# Custom Sleek Dark-Themed Modal Dialog Box
function Show-DeskFlowDialog {
    param(
        [string]$title = "Confirmation",
        [string]$message = "Are you sure you want to proceed?",
        [string]$confirmText = "CONFIRM",
        [string]$cancelText = "CANCEL",
        [string]$icon = "⚠️",
        [string]$confirmColor = "#EF4444",
        [bool]$showCancel = $true
    )

    $iconBgColor = if ($confirmColor -like "#EF*" -or $confirmColor -like "#FF*") { "#3A1B1B" }
                   elseif ($confirmColor -like "#8B*" -or $confirmColor -like "#7C*") { "#281B3A" }
                   elseif ($confirmColor -like "#10*" -or $confirmColor -like "#05*") { "#1B3A28" }
                   else { "#262636" }

    $cancelButtonXaml = if ($showCancel) {
        "<Button Name='btnDialogCancel' Content='$cancelText' Height='38' Padding='20,0' Background='#262636' Foreground='#8F8F9D' FontWeight='Bold' BorderThickness='0' Cursor='Hand' Margin='0,0,10,0'>
            <Button.Resources><Style TargetType='Border'><Setter Property='CornerRadius' Value='8'/></Style></Button.Resources>
        </Button>"
    } else { "" }

    $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$title" Height="220" Width="450" WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True">
    <Border Background="#16161D" BorderBrush="#2D2D3F" BorderThickness="1.5" CornerRadius="16" Padding="24">
        <Border.Effect>
            <DropShadowEffect BlurRadius="25" ShadowDepth="8" Color="#000000" Opacity="0.6"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <Grid Grid.Row="0" Margin="0,0,0,14">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <!-- Icon Badge -->
                <Border Width="38" Height="38" CornerRadius="10" Background="$iconBgColor" BorderBrush="$confirmColor" BorderThickness="1" Grid.Column="0" Margin="0,0,12,0">
                    <TextBlock Text="$icon" FontSize="18" FontFamily="Segoe UI Emoji, Segoe UI Symbol" Foreground="$confirmColor" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>

                <TextBlock Text="$title" FontSize="15" FontWeight="Bold" Foreground="#FFFFFF" Grid.Column="1" VerticalAlignment="Center"/>
                <Button Name="btnDialogClose" Content="✕" Width="28" Height="28" Grid.Column="2" Background="Transparent" Foreground="#8F8F9D" BorderThickness="0" FontSize="13" Cursor="Hand"/>
            </Grid>

            <!-- Message Body -->
            <TextBlock Grid.Row="1" Text="$message" FontSize="12.5" Foreground="#C5C5D3" TextWrapping="Wrap" LineHeight="19" Margin="0,0,0,16"/>

            <!-- Buttons -->
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
                $cancelButtonXaml
                <Button Name="btnDialogConfirm" Content="$confirmText" Height="38" Padding="22,0" Background="$confirmColor" Foreground="#FFFFFF" FontWeight="Bold" BorderThickness="0" Cursor="Hand">
                    <Button.Resources><Style TargetType='Border'><Setter Property='CornerRadius' Value='8'/></Style></Button.Resources>
                </Button>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

    try {
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($dialogXaml))
        $winDlg = [System.Windows.Markup.XamlReader]::Load($reader)
        if ($null -ne $window) {
            $winDlg.Owner = $window
            $winDlg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        }

        $btnConfirm = $winDlg.FindName("btnDialogConfirm")
        $btnCancel  = $winDlg.FindName("btnDialogCancel")
        $btnClose   = $winDlg.FindName("btnDialogClose")

        $winDlg.Add_MouseLeftButtonDown({ $winDlg.DragMove() })
        if ($null -ne $btnConfirm) { $btnConfirm.Add_Click({ $winDlg.DialogResult = $true; $winDlg.Close() }) }
        if ($null -ne $btnCancel)  { $btnCancel.Add_Click({ $winDlg.DialogResult = $false; $winDlg.Close() }) }
        if ($null -ne $btnClose)   { $btnClose.Add_Click({ $winDlg.DialogResult = $false; $winDlg.Close() }) }

        $winDlg.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                $winDlg.DialogResult = $false
                $winDlg.Close()
            }
        })

        $res = $winDlg.ShowDialog()
        return ($res -eq $true)
    } catch {
        $mbRes = [System.Windows.MessageBox]::Show($message, $title, [System.Windows.MessageBoxButton]::OKCancel)
        return ($mbRes -eq [System.Windows.MessageBoxResult]::OK)
    }
}

# String Template Formatter
function Format-Template {
    param(
        [string]$template,
        [string]$currentTime = (Get-Date).ToString("h:mm tt"),
        [string]$duration = "",
        [string]$workingHours = "",
        [string]$taskUpdate = ""
    )
    
    $result = $template
    $result = $result.Replace("{current_time}", $currentTime)
    if ($duration -ne "") {
        $result = $result.Replace("{duration}", $duration)
    }
    if ($workingHours -ne "") {
        $result = $result.Replace("{working_hours}", $workingHours)
    }
    if ($taskUpdate -ne "") {
        $result = $result.Replace("{task_update}", $taskUpdate)
    }
    return $result
}

# Clipboard copies
function Copy-ToClipboard {
    param([string]$text)
    try {
        [System.Windows.Clipboard]::SetText($text)
    } catch {
        # Fallback in case clipboard is temporarily locked by another app
        try { Set-Clipboard -Value $text -ErrorAction SilentlyContinue } catch {}
    }
}

function Send-WebhookMessage {
    param([string]$message)
    if (-not $global:Settings.webhook_enabled -or [string]::IsNullOrWhiteSpace($global:Settings.webhook_url)) {
        return
    }
    
    # Split multiple URLs by comma, newline or carriage return
    $urls = $global:Settings.webhook_url -split '[\r\n,]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    
    foreach ($url in $urls) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $webhookUrl = $url
            if ($webhookUrl.Contains("discord.com/api/webhooks") -and -not $webhookUrl.EndsWith("/slack")) {
                $webhookUrl = $webhookUrl.TrimEnd('/') + "/slack"
            }
            $msgText = $message
            if (-not [string]::IsNullOrWhiteSpace($global:Settings.webhook_display_name)) {
                $isSlackOrDiscord = $webhookUrl.Contains("slack.com") -or $webhookUrl.Contains("discord.com")
                if (-not $isSlackOrDiscord) {
                    $msgText = "👤 **$($global:Settings.webhook_display_name)**: $message"
                }
            }
            $payloadObj = @{ text = $msgText }
            if (-not [string]::IsNullOrWhiteSpace($global:Settings.webhook_display_name)) {
                $payloadObj.username = $global:Settings.webhook_display_name
            }
            $hasEmoji = $false
            if (-not [string]::IsNullOrWhiteSpace($global:Settings.webhook_avatar_emoji) -and $global:Settings.webhook_avatar_emoji -ne "None") {
                $emojiTag = switch ($global:Settings.webhook_avatar_emoji) {
                    "Sunny" { ":sunny:" }
                    "Smile" { ":smile:" }
                    "Work" { ":computer:" }
                    "Briefcase" { ":briefcase:" }
                    "Ghost" { ":ghost:" }
                    "Coffee" { ":coffee:" }
                    "Rocket" { ":rocket:" }
                    "Wizard" { ":mage:" }
                    "Calendar" { ":calendar:" }
                    "Alert" { ":warning:" }
                    default { $null }
                }
                if ($null -ne $emojiTag) {
                    $payloadObj.icon_emoji = $emojiTag
                    $hasEmoji = $true
                }
            }
            if (-not $hasEmoji -and -not [string]::IsNullOrWhiteSpace($global:Settings.webhook_avatar_url)) {
                $avatar = $global:Settings.webhook_avatar_url.Trim()
                if ($avatar.StartsWith(":") -and $avatar.EndsWith(":")) {
                    $payloadObj.icon_emoji = $avatar
                } else {
                    $payloadObj.icon_url = $avatar
                }
            }
            $payload = $payloadObj | ConvertTo-Json -Compress
            $body = [System.Text.Encoding]::UTF8.GetBytes($payload)
            [void](Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec 10)
        } catch {
            # Fail silently per URL so other webhooks are not blocked
        }
    }
}

function Copy-PreviewToClipboard {
    if ($listPreview.Items.Count -gt 0) {
        $allText = @()
        foreach ($item in $listPreview.Items) {
            $allText += $item
        }
        $combinedText = [string]::Join("`r`n`r`n", $allText)
        Copy-ToClipboard $combinedText
        Show-Toast "✓ Copied All to Clipboard" "#10AC84" "#155724"
    } else {
        Show-Toast "⚠️ Preview is empty!" "#FF4D4D" "#8B0000"
    }
}

function Append-Preview {
    param([string]$text)
    
    $listPreview.Items.Add($text)
    if ($listPreview.Items.Count -gt 0) {
        $listPreview.ScrollIntoView($listPreview.Items[$listPreview.Items.Count - 1])
    }
}

function Log-Activity {
    param([string]$activity)
    
    $timeStr = (Get-Date).ToString("HH:mm")
    $logItem = "$timeStr - $activity"
    
    $window.Dispatcher.Invoke({
        $listTimeline.Items.Add($logItem)
        if ($listTimeline.Items.Count -gt 0) {
            $listTimeline.ScrollIntoView($listTimeline.Items[$listTimeline.Items.Count - 1])
        }
    })
}

# Tab navigation toggles
function Show-Tab {
    param([string]$tabName)
    
    if ($gridSettings.Visibility -eq [System.Windows.Visibility]::Visible -and $tabName -ne "Settings") {
        Save-Settings
    }
    
    $gridDashboard.Visibility = [System.Windows.Visibility]::Collapsed
    $gridHistory.Visibility = [System.Windows.Visibility]::Collapsed
    $gridAnalytics.Visibility = [System.Windows.Visibility]::Collapsed
    $gridSettings.Visibility = [System.Windows.Visibility]::Collapsed
    $gridTaskUpdate.Visibility = [System.Windows.Visibility]::Collapsed
    if ($null -ne $gridLicense) { $gridLicense.Visibility = [System.Windows.Visibility]::Collapsed }
    if ($null -ne $gridAbout) { $gridAbout.Visibility = [System.Windows.Visibility]::Collapsed }
    
    $btnNavDashboard.Background = $transparentBrush
    $btnNavDashboard.Foreground = $greyBrush
    $btnNavHistory.Background = $transparentBrush
    $btnNavHistory.Foreground = $greyBrush
    $btnNavAnalytics.Background = $transparentBrush
    $btnNavAnalytics.Foreground = $greyBrush
    $btnNavSettings.Background = $transparentBrush
    $btnNavSettings.Foreground = $greyBrush
    $btnNavTaskUpdate.Background = $transparentBrush
    $btnNavTaskUpdate.Foreground = $greyBrush
    if ($null -ne $btnNavLicense) {
        $btnNavLicense.Background = $transparentBrush
        $btnNavLicense.Foreground = $greyBrush
    }
    if ($null -ne $btnNavAbout) {
        $btnNavAbout.Background = $transparentBrush
        $btnNavAbout.Foreground = $greyBrush
    }
    
    switch ($tabName) {
        "Dashboard" {
            $gridDashboard.Visibility = [System.Windows.Visibility]::Visible
            $btnNavDashboard.Background = $navActiveBrush
            $btnNavDashboard.Foreground = $whiteBrush
        }
        "History" {
            $gridHistory.Visibility = [System.Windows.Visibility]::Visible
            $btnNavHistory.Background = $navActiveBrush
            $btnNavHistory.Foreground = $whiteBrush
            Load-HistoryView
        }
        "Analytics" {
            $gridAnalytics.Visibility = [System.Windows.Visibility]::Visible
            $btnNavAnalytics.Background = $navActiveBrush
            $btnNavAnalytics.Foreground = $whiteBrush
            Load-AnalyticsView
        }
        "Settings" {
            $gridSettings.Visibility = [System.Windows.Visibility]::Visible
            $btnNavSettings.Background = $navActiveBrush
            $btnNavSettings.Foreground = $whiteBrush
            Load-SettingsView
        }
        "TaskUpdate" {
            $gridTaskUpdate.Visibility = [System.Windows.Visibility]::Visible
            $btnNavTaskUpdate.Background = $navActiveBrush
            $btnNavTaskUpdate.Foreground = $whiteBrush
            Load-TaskUpdateView
        }
        "License" {
            if ($null -ne $gridLicense) { $gridLicense.Visibility = [System.Windows.Visibility]::Visible }
            if ($null -ne $btnNavLicense) {
                $btnNavLicense.Background = $navActiveBrush
                $btnNavLicense.Foreground = $whiteBrush
            }
            Load-LicenseView
        }
        "About" {
            if ($null -ne $gridAbout) { $gridAbout.Visibility = [System.Windows.Visibility]::Visible }
            if ($null -ne $btnNavAbout) {
                $btnNavAbout.Background = $navActiveBrush
                $btnNavAbout.Foreground = $whiteBrush
            }
        }
    }
}

function Get-MaskedLicenseKey ($rawKey) {
    if ([string]::IsNullOrEmpty($rawKey) -or $rawKey.Length -lt 8) {
        return "****-****-****-****"
    }
    $clean = $rawKey.Trim()
    $prefix = $clean.Substring(0, [Math]::Min(4, $clean.Length))
    $suffix = $clean.Substring([Math]::Max(0, $clean.Length - 4))
    return "$prefix-****-****-$suffix"
}

function Update-DeskFlowLicenseBadge {
    $lic = Get-StealthLicensePayload
    if ($global:IsLicenseValid) {
        if ($null -ne $txtLicStatusTitle) {
            $txtLicStatusTitle.Text = "Pro License Active — Pro"
            $txtLicStatusTitle.Foreground = $brushConv.ConvertFromString("#A3E635")
            $licType = "Lifetime License"
            if ($lic) {
                if ($lic.license_type -eq "annual" -or $lic.plan -eq "annual" -or $lic.license_type -eq "1year") {
                    $licType = "1 Year License"
                } elseif (-not [string]::IsNullOrEmpty($lic.license_type) -and $lic.license_type -ne "Pro") {
                    $licType = "$($lic.license_type.Substring(0,1).ToUpper())$($lic.license_type.Substring(1)) License"
                } elseif (-not [string]::IsNullOrEmpty($lic.plan) -and $lic.plan -ne "Pro") {
                    $licType = "$($lic.plan) License"
                }
            }
            $licEmail = if ($lic -and $lic.email) { $lic.email } else { "" }
            if ([string]::IsNullOrEmpty($licEmail)) {
                $txtLicStatusDesc.Text = $licType
            } else {
                $txtLicStatusDesc.Text = "$licType · $licEmail"
            }
        }
        if ($null -ne $txtLicStatusIcon) {
            $txtLicStatusIcon.Text = "✅"
        }
        if ($null -ne $borderLicMaskedKey -and $null -ne $txtLicMaskedKey) {
            if ($lic -and -not [string]::IsNullOrEmpty($lic.key)) {
                $txtLicMaskedKey.Text = Get-MaskedLicenseKey $lic.key
                $borderLicMaskedKey.Visibility = [System.Windows.Visibility]::Visible
            }
        }
        if ($null -ne $panelLicProgress) {
            $panelLicProgress.Visibility = [System.Windows.Visibility]::Collapsed
        }
        if ($null -ne $panelActivationInput) {
            $panelActivationInput.Visibility = [System.Windows.Visibility]::Collapsed
        }
        if ($null -ne $panelDeactivation) {
            $panelDeactivation.Visibility = [System.Windows.Visibility]::Visible
        }
    } else {
        $trialStart = Get-StealthTrialDate
        $daysUsed = ((Get-Date) - $trialStart).TotalDays
        $daysLeft = [Math]::Max(0, [Math]::Ceiling($global:DeskFlowTrialDays - $daysUsed))
        $pct = [Math]::Max(0, [Math]::Min(100, [Math]::Round(($daysLeft / $global:DeskFlowTrialDays) * 100)))

        if ($null -ne $txtLicStatusTitle) {
            $txtLicStatusTitle.Text = "30-Day Free Trial ($daysLeft Days Remaining)"
            $txtLicStatusTitle.Foreground = $brushConv.ConvertFromString("#38BDF8")
            $txtLicStatusDesc.Text = "Activate your DeskFlow Pro license key to unlock unlimited access and priority updates."
        }
        if ($null -ne $txtLicStatusIcon) {
            $txtLicStatusIcon.Text = "🛡️"
        }
        if ($null -ne $borderLicMaskedKey) {
            $borderLicMaskedKey.Visibility = [System.Windows.Visibility]::Collapsed
        }
        if ($null -ne $panelLicProgress) {
            $panelLicProgress.Visibility = [System.Windows.Visibility]::Visible
        }
        if ($null -ne $progLicTrial) {
            $progLicTrial.Value = $pct
        }
        if ($null -ne $txtLicProgressValue) {
            $txtLicProgressValue.Text = "$daysLeft Days Remaining ($pct%)"
        }
        if ($null -ne $panelActivationInput) {
            $panelActivationInput.Visibility = [System.Windows.Visibility]::Visible
        }
        if ($null -ne $panelDeactivation) {
            $panelDeactivation.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
}

function Load-LicenseView {
    if ($null -ne $txtLicMachineId) {
        $txtLicMachineId.Text = Get-DeskFlowMachineId
    }
    $lic = Get-StealthLicensePayload
    if ($null -ne $lic) {
        if (-not [string]::IsNullOrEmpty($lic.key) -and $null -ne $txtLicKey) { $txtLicKey.Text = $lic.key }
        if (-not [string]::IsNullOrEmpty($lic.email) -and $null -ne $txtLicEmail) { $txtLicEmail.Text = $lic.email }
    }
    Update-DeskFlowLicenseBadge
}

# 5. Core Session and Break Handlers

# Check if a date is configured as an off-day (weekend/holiday)
function Is-OffDay {
    param([DateTime]$date)
    
    if ($null -eq $global:Settings) {
        return ($date.DayOfWeek -eq [System.DayOfWeek]::Sunday)
    }
    
    $dayOfWeek = $date.DayOfWeek.ToString()
    
    # 1. Check weekly off days list
    if ($null -ne $global:Settings.off_days_weekly -and $global:Settings.off_days_weekly -contains $dayOfWeek) {
        return $true
    }
    
    # 2. Check dynamic recurrence rules
    if ($null -ne $global:Settings.off_days_occurrences) {
        foreach ($rule in $global:Settings.off_days_occurrences) {
            if ($rule.day -eq $dayOfWeek) {
                $dayNum = $date.Day
                $weekName = ""
                if ($dayNum -ge 1 -and $dayNum -le 7) { $weekName = "1st" }
                elseif ($dayNum -ge 8 -and $dayNum -le 14) { $weekName = "2nd" }
                elseif ($dayNum -ge 15 -and $dayNum -le 21) { $weekName = "3rd" }
                elseif ($dayNum -ge 22 -and $dayNum -le 28) { $weekName = "4th" }
                elseif ($dayNum -ge 29) { $weekName = "5th" }
                
                $isLast = $date.AddDays(7).Month -ne $date.Month
                
                if ($rule.weeks -contains $weekName -or ($isLast -and $rule.weeks -contains "Last")) {
                    return $true
                }
            }
        }
    }
    
    # 3. Check custom specific holidays
    if ($null -ne $global:Settings.off_days_custom) {
        $dateStr = $date.ToString("yyyy-MM-dd")
        foreach ($holiday in $global:Settings.off_days_custom) {
            if ($holiday.date -eq $dateStr) {
                return $true
            }
        }
    }
    
    return $false
}

# Update the rolling monthly attendance calendar strip
function Update-CalendarView {
    if ($null -eq $global:CalendarContainer) { return }
    
    # Run WPF updates on dispatcher thread if called asynchronously
    $global:CalendarContainer.Dispatcher.Invoke([Action]{
        $global:CalendarContainer.Children.Clear()
        
        # Load history dates for quick lookup
        $historyFile = Join-Path $global:DataDir "history.json"
        $historyDates = @{}
        if (Test-Path $historyFile) {
            try {
                $history = Get-Content $historyFile -Raw | ConvertFrom-Json
                if ($null -ne $history) {
                    foreach ($entry in $history) {
                        if ($null -ne $entry.date) {
                            $historyDates[$entry.date] = $true
                        }
                    }
                }
            } catch {}
        }
        
        $today = Get-Date
        $todayStr = $today.ToString("yyyy-MM-dd")
        $year = $today.Year
        $month = $today.Month
        $daysInMonth = [DateTime]::DaysInMonth($year, $month)
        
        # Dynamically update the calendar header title
        if ($null -ne $global:TxtCalendarTitle) {
            $monthName = $today.ToString("MMMM yyyy").ToUpper()
            $global:TxtCalendarTitle.Text = "ATTENDANCE & WORK HISTORY ($monthName)"
        }
        
        # Draw all days of the current month (chronological order, 1 to N)
        for ($day = 1; $day -le $daysInMonth; $day++) {
            $date = [DateTime]::new($year, $month, $day)
            $dateStr = $date.ToString("yyyy-MM-dd")
            $dayName = $date.ToString("ddd").ToUpper()
            $dayNum = $day.ToString()
            
            $isOff = Is-OffDay -date $date
            $isWorked = $historyDates.ContainsKey($dateStr) -or ($dateStr -eq $todayStr -and $global:OfficeStarted)
            $isToday = $dateStr -eq $todayStr
            
            # 1. Base coloring based on state (Worked [Blue] vs Off-Day [Pink] vs Regular [Grey])
            if ($isWorked) {
                # Blue tint for worked/completed days
                $bg = "#1A2535"
                $border = "#89B4FA"
                $text = "#89B4FA"
                $dot = "#89B4FA"
            }
            elseif ($isOff) {
                # Coral/Red tint for off-days
                $bg = "#2D1E2E"
                $border = "#F38BA8"
                $text = "#F38BA8"
                $dot = "#F38BA8"
            }
            else {
                # Neutral grey/black for regular days
                $bg = "#15151C"
                $border = "#2A2A35"
                $text = "#8F8F9D"
                $dot = "#3A3A4A"
            }
            
            # 2. Highlight today's date with a distinct green border
            $borderThickness = "1.2"
            if ($isToday) {
                $border = "#22C55E" # Vibrant green border for today
                $borderThickness = "2.0" # Thicker border to make it pop
            }
            
            $cellXaml = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="45" Height="68" Margin="3" CornerRadius="6" BorderThickness="$borderThickness"
        Background="$bg" BorderBrush="$border">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="$dayName" FontSize="9" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,4,0,0" Foreground="$text" Opacity="0.8"/>
        <TextBlock Grid.Row="1" Text="$dayNum" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="$text"/>
        <Ellipse Grid.Row="2" Width="6" Height="6" Margin="0,0,0,5" Fill="$dot" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Grid>
</Border>
"@
            try {
                $cell = [System.Windows.Markup.XamlReader]::Parse($cellXaml)
                [void]$global:CalendarContainer.Children.Add($cell)
            } catch {
                # Silent fallback on compile error
            }
        }
    })
}

# Start Office
function Start-Office {
    if ($global:OfficeStarted) { return }
    $global:OfficeStarted = $true
    $global:OfficeStartTime = Get-Date
    $global:EntryTime = $global:OfficeStartTime
    if ($null -ne $txtEntryTime) {
        $txtEntryTime.Text = $global:EntryTime.ToString("hh:mm tt")
    }
    $global:TotalBreakDurationSeconds = 0
    $global:WorkDayTargetAchieved = $false
    
    # Clear previous session's task data and saved worked hours on NEW session start
    $global:SavedWorkedHoursStr = $null
    $global:SavedEntryTime = $null
    $global:SavedTaskList = $null
    
    $btnStartOffice.Content = "Stop Office"
    $btnStartOffice.Background = $redBrush
    $txtOfficeStatus.Text = "Office Session: Active"
    $txtOfficeStatus.Foreground = $greenBrush
    
    Log-Activity "Office Started at $($global:OfficeStartTime.ToString('h:mm tt'))"
    Show-Toast "✓ Office Session Started" "#10AC84" "#155724"
    
    Update-CalendarView
    
    # Send entry time to Google Sheets in background silently
    $scriptUrl = $global:Settings.google_script_url
    if (-not [string]::IsNullOrWhiteSpace($scriptUrl)) {
        $entryTimeStr = $global:EntryTime.ToString("hh:mm tt")
        Start-Job -Name "SyncEntryTime" -ArgumentList $scriptUrl, $global:Settings.user_name, $global:Settings.user_role, $entryTimeStr -ScriptBlock {
            param($url, $user, $role, $entryTime)
            
            $today = (Get-Date).ToString("d MMMM")
            $body = @{
                date = $today
                name = $user
                role = $role
                entry = $entryTime
                task_index = 1
            } | ConvertTo-Json -Depth 5
            
            try {
                Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json"
            } catch { }
        } | Out-Null
    }
}

# Stop/Reset Office
function Stop-Office {
    param([switch]$Force)
    
    if (-not $global:OfficeStarted) { return }
    
    if (-not $Force) {
        $confirm = Show-DeskFlowDialog -title "Confirm Reset" -message "Are you sure you want to stop the office session? This will reset the timer." -confirmText "RESET TIMER" -cancelText "CANCEL" -icon "⏱️" -confirmColor "#EF4444"
        if (-not $confirm) { return }
    }
    
    # Save worked hours and entry time BEFORE clearing, so Task Update can still use them
    $now = Get-Date
    $totalElapsedSeconds = ($now - $global:OfficeStartTime).TotalSeconds
    $savedWorkedSec = $totalElapsedSeconds - $global:TotalBreakDurationSeconds
    $totalBreakSeconds = $global:TotalBreakDurationSeconds
    
    if ($global:ActiveBreakType -ne $null) {
        $savedWorkedSec -= ($now - $global:BreakStartTime).TotalSeconds
        $totalBreakSeconds += ($now - $global:BreakStartTime).TotalSeconds
    }
    if ($savedWorkedSec -lt 0) { $savedWorkedSec = 0 }
    
    $ts = [TimeSpan]::FromSeconds($savedWorkedSec)
    $global:SavedWorkedHoursStr = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
    
    $tsBreak = [TimeSpan]::FromSeconds($totalBreakSeconds)
    $finalBreakHoursStr = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($tsBreak.TotalHours), $tsBreak.Minutes, $tsBreak.Seconds)
    
    # Make sure textboxes lost focus to capture any last typing
    if ($null -ne $global:LastFocusedDetailsTextBox) {
        try { $global:LastFocusedDetailsTextBox.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.UIElement]::LostFocusEvent))) } catch {}
    }
    
    # Auto-save the final state of the day to history
    $finalTaskUpdateText = Get-TaskUpdateText
    Save-DayToHistory -workedHours $global:SavedWorkedHoursStr -breakHours $finalBreakHoursStr -taskUpdate $finalTaskUpdateText
    $global:SavedEntryTime = $global:EntryTime
    $global:SavedTaskList = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $global:TaskList) {
        $global:SavedTaskList.Add([PSCustomObject]@{
            Project  = $t.Project
            Details  = $t.Details
            Link     = $t.Link
            Status   = $t.Status
            Duration = $t.Duration
        })
    }
    
    $global:OfficeStarted = $false
    $global:OfficeStartTime = $null
    $global:EntryTime = $null
    if ($null -ne $txtEntryTime) {
        $txtEntryTime.Text = "--:--:--"
    }
    
    # Pause and clear multitasking task list
    foreach ($task in $global:TaskList) {
        $task.IsActive = $false
    }
    $global:TaskList.Clear()
    if ($null -ne $tasksContainer) {
        $tasksContainer.Children.Clear()
    }
    $global:LastFocusedDetailsTextBox = $null
    $global:LastActiveTaskBeforeBreak = $null
    
    $global:TotalBreakDurationSeconds = 0
    $global:ActiveBreakType = $null
    $global:BreakStartTime = $null
    $global:ActiveBreakElapsedSeconds = 0
    $global:WorkDayTargetAchieved = $false
    
    Update-BreakButtonsState
    
    $btnStartOffice.Content = "Start Office"
    $btnStartOffice.Background = $blueBrush
    $txtOfficeStatus.Text = "Office Session: Inactive"
    $txtOfficeStatus.Foreground = $greyBrush
    $txtWorkedTime.Text = "00:00:00"
    $txtTotalBreak.Text = "00:00:00"
    
    Log-Activity "Office Session Stopped/Reset"
    if ($Force) {
        Show-Toast "✓ Office Session Completed" "#10AC84" "#155724"
    } else {
        Show-Toast "⚠️ Office Session Reset" "#FF4D4D" "#8B0000"
    }
    
    Update-CalendarView
}

# Break Manager toggling states
# Break Manager toggling states
function Update-BreakButtonsState {
    if ($global:ActiveBreakType -eq $null) {
        $btnLunch.Content = "$global:LunchEmoji Lunch"
        $btnLunch.Background = $purpleBrush
        $btnLunch.IsEnabled = $true

        $btnPrayer.Content = "$global:PrayerEmoji Prayer"
        $btnPrayer.Background = $purpleBrush
        $btnPrayer.IsEnabled = $true

        $btnCombo.Content = "$global:LunchEmoji+$global:PrayerEmoji Prayer + Lunch"
        $btnCombo.Background = $purpleBrush
        $btnCombo.IsEnabled = $true
        
        # Reset custom buttons
        if ($null -ne $global:Settings.custom_breaks) {
            foreach ($cb in $global:Settings.custom_breaks) {
                $btn = $global:CustomBreakButtons[$cb.id]
                if ($null -ne $btn) {
                    $btn.Content = $cb.name
                    $btn.Background = $purpleBrush
                    $btn.IsEnabled = $true
                }
            }
        }
    }
    else {
        $btnLunch.IsEnabled = ($global:ActiveBreakType -eq "Lunch")
        $btnPrayer.IsEnabled = ($global:ActiveBreakType -eq "Prayer")
        $btnCombo.IsEnabled = ($global:ActiveBreakType -eq "Combo")
        
        if ($global:ActiveBreakType -eq "Lunch") {
            $btnLunch.Content = "I'm Back (00m 00s)"
            $btnLunch.Background = $redBrush
        }
        elseif ($global:ActiveBreakType -eq "Prayer") {
            $btnPrayer.Content = "I'm Back (00m 00s)"
            $btnPrayer.Background = $redBrush
        }
        elseif ($global:ActiveBreakType -eq "Combo") {
            $btnCombo.Content = "I'm Back (00m 00s)"
            $btnCombo.Background = $redBrush
        }
        
        # Disable all non-active custom buttons, enable active one
        if ($null -ne $global:Settings.custom_breaks) {
            foreach ($cb in $global:Settings.custom_breaks) {
                $btn = $global:CustomBreakButtons[$cb.id]
                if ($null -ne $btn) {
                    if ($global:ActiveBreakType -eq $cb.id) {
                        $btn.IsEnabled = $true
                        $btn.Content = "I'm Back (00m 00s)"
                        $btn.Background = $redBrush
                    } else {
                        $btn.IsEnabled = $false
                        $btn.Background = $purpleBrush
                    }
                }
            }
        }
    }
}

function Save-Settings {
    if ($null -ne $txtSetGoodMorning) { $global:Settings.templates.good_morning = $txtSetGoodMorning.Text }
    if ($null -ne $txtSetLunchStart) { $global:Settings.templates.lunch_start = $txtSetLunchStart.Text }
    if ($null -ne $txtSetLunchReturn) { $global:Settings.templates.lunch_return = $txtSetLunchReturn.Text }
    if ($null -ne $txtSetPrayerStart) { $global:Settings.templates.prayer_start = $txtSetPrayerStart.Text }
    if ($null -ne $txtSetPrayerReturn) { $global:Settings.templates.prayer_return = $txtSetPrayerReturn.Text }
    if ($null -ne $txtSetComboStart) { $global:Settings.templates.combo_start = $txtSetComboStart.Text }
    if ($null -ne $txtSetComboReturn) { $global:Settings.templates.combo_return = $txtSetComboReturn.Text }
    if ($null -ne $txtSetTaskUpdateTemplate) { $global:Settings.templates.task_update = $txtSetTaskUpdateTemplate.Text }
    if ($null -ne $txtSetLeavingOfficeTemplate) { $global:Settings.templates.leaving_office = $txtSetLeavingOfficeTemplate.Text }
    if ($null -ne $chkSetMinimizeToTray) { $global:Settings.minimize_to_tray = [bool]$chkSetMinimizeToTray.IsChecked }
    if ($null -ne $chkSetStartWithWindows) { $global:Settings.start_with_windows = $chkSetStartWithWindows.IsChecked }
    if ($null -ne $chkSetAutoDetectSession) { $global:Settings.auto_detect_session = $chkSetAutoDetectSession.IsChecked }
    if ($null -ne $chkSetWebhookEnabled) { $global:Settings.webhook_enabled = [bool]$chkSetWebhookEnabled.IsChecked }
    if ($null -ne $txtSetWebhookDisplayName) { $global:Settings.webhook_display_name = $txtSetWebhookDisplayName.Text.Trim() }
    if ($null -ne $txtSetWebhookAvatarUrl) { $global:Settings.webhook_avatar_url = $txtSetWebhookAvatarUrl.Text.Trim() }
    
    if ($null -ne $cmbSetWebhookEmoji -and $cmbSetWebhookEmoji.SelectedItem -ne $null) {
        $selText = $cmbSetWebhookEmoji.SelectedItem.Content.ToString()
        $emojiName = $selText -replace '\s+.*$', ''
        $global:Settings.webhook_avatar_emoji = $emojiName
    } else {
        $global:Settings.webhook_avatar_emoji = "None"
    }
    
    if ($null -ne $webhookUrlsPanel) {
        $urlList = @()
        foreach ($child in $webhookUrlsPanel.Children) {
            if ($child -is [System.Windows.Controls.Grid]) {
                foreach ($gridChild in $child.Children) {
                    if (($gridChild -is [System.Windows.Controls.TextBox] -or $gridChild -is [System.Windows.Controls.PasswordBox]) -and $gridChild.Tag -eq "WebhookUrlInput") {
                        $val = if ($gridChild -is [System.Windows.Controls.PasswordBox]) { $gridChild.Password.Trim() } else { $gridChild.Text.Trim() }
                        if (-not [string]::IsNullOrWhiteSpace($val)) {
                            $urlList += $val
                        }
                    }
                }
            }
        }
        $global:Settings.webhook_url = $urlList -join ", "
    }
    
    if ($null -ne $chkOffSun) {
        $weeklyOffs = @()
        if ($chkOffSun.IsChecked) { $weeklyOffs += "Sunday" }
        if ($chkOffMon.IsChecked) { $weeklyOffs += "Monday" }
        if ($chkOffTue.IsChecked) { $weeklyOffs += "Tuesday" }
        if ($chkOffWed.IsChecked) { $weeklyOffs += "Wednesday" }
        if ($chkOffThu.IsChecked) { $weeklyOffs += "Thursday" }
        if ($chkOffFri.IsChecked) { $weeklyOffs += "Friday" }
        if ($chkOffSat.IsChecked) { $weeklyOffs += "Saturday" }
        $global:Settings.off_days_weekly = $weeklyOffs
    }
    
    if ($null -ne $offRulesPanel) {
        $rulesList = @()
        foreach ($child in $offRulesPanel.Children) {
            if ($child.Tag -ne $null) { $rulesList += $child.Tag }
        }
        $global:Settings.off_days_occurrences = $rulesList
    }
    
    if ($null -ne $offHolidaysPanel) {
        $holidaysList = @()
        foreach ($child in $offHolidaysPanel.Children) {
            if ($child.Tag -ne $null) { $holidaysList += $child.Tag }
        }
        $global:Settings.off_days_custom = $holidaysList
    }
    
    if ($null -ne $txtSetGmailAddress) { $global:Settings.gmail_address = $txtSetGmailAddress.Text.Trim() }
    if ($null -ne $pwdSetGmailAppPassword) { $global:Settings.gmail_app_password = $pwdSetGmailAppPassword.Password.Trim() }
    if ($null -ne $txtTableBodyColor) {
        $colorVal = $txtTableBodyColor.Text.Trim()
        if ($colorVal -match '^#[0-9a-fA-F]{3,6}$') {
            $global:Settings.table_body_color = $colorVal
        }
    }

    if ($null -ne $txtSetQuickTasks) {
        if ($txtSetQuickTasks.Text.Trim() -ne "") {
            $tasksSplit = $txtSetQuickTasks.Text.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            $global:Settings.quick_tasks = @($tasksSplit)
        } else {
            $global:Settings.quick_tasks = @()
        }
    }
    
    if ($null -ne $window -and $null -ne $btnAlwaysOnTop) {
        $window.Topmost = $global:Settings.always_on_top
        if ($global:Settings.always_on_top) {
            $btnAlwaysOnTop.Foreground = $purpleBrush
        } else {
            $btnAlwaysOnTop.Foreground = $greyBrush
        }
    }
    
    if ($null -ne $txtSetUserName) { $global:Settings.user_name = $txtSetUserName.Text.Trim() }
    if ($null -ne $txtSetUserRole) { $global:Settings.user_role = $txtSetUserRole.Text.Trim() }
    if ($null -ne $txtSetGoogleScriptUrl) { $global:Settings.google_script_url = $txtSetGoogleScriptUrl.Text.Trim() }
    if ($null -ne $txtSetGoogleSheetUrl) { $global:Settings.google_sheet_url = $txtSetGoogleSheetUrl.Text.Trim() }

    $registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $keyName = "DeskFlow"
    $targetExe = Join-Path $scriptDir "DeskFlow.exe"
    if (Test-Path $targetExe) {
        $launchPath = $targetExe
    } elseif (Test-Path (Join-Path $scriptDir "Launch.bat")) {
        $launchPath = Join-Path $scriptDir "Launch.bat"
    } else {
        $launchPath = (Get-Process -Id $PID).Path
    }

    $hklmPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    if ($global:Settings.start_with_windows) {
        Set-ItemProperty -Path $registryPath -Name $keyName -Value "`"$launchPath`" --autostart" -ErrorAction SilentlyContinue
    } else {
        Remove-ItemProperty -Path $registryPath -Name $keyName -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $registryPath -Name "OfficeStatusGenerator" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $hklmPath -Name $keyName -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $hklmPath -Name "OfficeStatusGenerator" -ErrorAction SilentlyContinue
    }
    
    $settingsFile = Join-Path $global:DataDir "settings.json"
    $json = ConvertTo-Json $global:Settings -Depth 10
    Set-Content -Path $settingsFile -Value $json -Force
    
    if ($null -ne $panelQuickTasks) { Load-QuickTasks }
    if ($null -ne $global:TxtCalendarTitle) { Update-CalendarView }
}

function Show-AddCustomBreakDialog {
    $plus = [char]0x2795
    $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Add Custom Status Button" Height="460" Width="380"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="Transparent" AllowsTransparency="True" WindowStyle="None">
    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#6C5CE7"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="15,10"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#15151B"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#2D2D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ScrollViewer Name="PART_ContentHost" Padding="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#6C5CE7"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="1.2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#1E1E24"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#2D2D35"/>
                                <Setter Property="Foreground" Value="#6F6F7D"/>
                                <Setter TargetName="border" Property="Opacity" Value="0.6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ModernPasswordBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#15151B"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#2D2D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="PasswordBox">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ScrollViewer Name="PART_ContentHost" Padding="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#6C5CE7"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="1.2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#1E1E24"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#2D2D35"/>
                                <Setter Property="Foreground" Value="#6F6F7D"/>
                                <Setter TargetName="border" Property="Opacity" Value="0.6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border CornerRadius="12" Background="#121216" BorderBrush="#2A2A35" BorderThickness="1.5">
        <Grid Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <TextBlock Text="ADD CUSTOM STATUS BUTTON" Foreground="White" FontSize="14" FontWeight="Bold" Margin="0,0,0,15" HorizontalAlignment="Center"/>
            
            <StackPanel Grid.Row="1">
                <TextBlock Text="BUTTON DISPLAY NAME" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                <TextBox Name="TxtBreakName" Style="{StaticResource ModernTextBox}" Height="36" Margin="0,0,0,12" ToolTip="e.g. Tea Break"/>
                
                <TextBlock Text="START TEMPLATE MESSAGE" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                <TextBox Name="TxtStartTemplate" Style="{StaticResource ModernTextBox}" Height="36" Margin="0,0,0,12" ToolTip="e.g. Taking a quick tea break"/>
                
                <TextBlock Text="RETURN TEMPLATE MESSAGE" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                <TextBox Name="TxtReturnTemplate" Style="{StaticResource ModernTextBox}" Height="36" Margin="0,0,0,12" ToolTip="e.g. Back from tea break"/>
                
                <TextBlock Text="TIME LIMIT (MINUTES)" Foreground="#8F8F9D" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
                <TextBox Name="TxtLimitMinutes" Style="{StaticResource ModernTextBox}" Height="36" ToolTip="e.g. 15 (0 to disable alerts)"/>
            </StackPanel>
            
            <Grid Grid.Row="2" Margin="0,15,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="10"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Button Name="BtnCancel" Content="Cancel" Style="{StaticResource ModernButton}" Background="#252530" Foreground="White" Height="38"/>
                <Button Name="BtnAdd" Grid.Column="2" Content="Add Button" Style="{StaticResource ModernButton}" Background="#6C5CE7" Height="38"/>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

    $dialogReader = New-Object System.Xml.XmlReaderSettings
    $dialogReader.ConformanceLevel = [System.Xml.ConformanceLevel]::Fragment
    $dialogXmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$dialogXaml, $dialogReader)
    $dialogWindow = [System.Windows.Markup.XamlReader]::Load($dialogXmlReader)
    $dialogWindow.Owner = $window
    
    $txtBreakName = $dialogWindow.FindName("TxtBreakName")
    $txtStartTemplate = $dialogWindow.FindName("TxtStartTemplate")
    $txtReturnTemplate = $dialogWindow.FindName("TxtReturnTemplate")
    $txtLimitMinutes = $dialogWindow.FindName("TxtLimitMinutes")
    $btnCancel = $dialogWindow.FindName("BtnCancel")
    $btnAdd = $dialogWindow.FindName("BtnAdd")
    
    $dialogResult = $null
    
    $btnCancel.Add_Click({
        $dialogWindow.Close()
    })
    
    $btnAdd.Add_Click({
        $name = $txtBreakName.Text.Trim()
        $start = $txtStartTemplate.Text.Trim()
        $return = $txtReturnTemplate.Text.Trim()
        $limitStr = $txtLimitMinutes.Text.Trim()
        
        if ([string]::IsNullOrEmpty($name)) {
            [System.Windows.MessageBox]::Show("Please enter a button name.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        if ([string]::IsNullOrEmpty($start)) {
            [System.Windows.MessageBox]::Show("Please enter start template.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        if ([string]::IsNullOrEmpty($return)) {
            [System.Windows.MessageBox]::Show("Please enter return template.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        
        $limit = 0
        if (-not [string]::IsNullOrEmpty($limitStr)) {
            if (-not [int]::TryParse($limitStr, [ref]$limit)) {
                [System.Windows.MessageBox]::Show("Please enter a valid number for limit minutes.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }
        }
        
        $dialogResult = [PSCustomObject]@{
            id = "Custom_" + [Guid]::NewGuid().ToString("N")
            name = $name
            start_template = $start
            return_template = $return
            limit_minutes = $limit
        }
        $dialogWindow.Close()
    })
    
    # Drag window functionality
    $dialogWindow.Add_MouseLeftButtonDown({
        $dialogWindow.DragMove()
    })
    
    [void]$dialogWindow.ShowDialog()
    return $dialogResult
}

function Load-CustomBreaks {
    $panelCustomBreaks.Children.Clear()
    $global:CustomBreakButtons = @{}
    
    if ($null -eq $global:Settings.custom_breaks) {
        $global:Settings.custom_breaks = @()
    }
    
    foreach ($cb in $global:Settings.custom_breaks) {
        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = "0,0,0,8"
        
        $col1 = New-Object System.Windows.Controls.ColumnDefinition
        $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition
        $col2.Width = New-Object System.Windows.GridLength(8, [System.Windows.GridUnitType]::Pixel)
        $col3 = New-Object System.Windows.Controls.ColumnDefinition
        $col3.Width = [System.Windows.GridLength]::Auto
        
        [void]$grid.ColumnDefinitions.Add($col1)
        [void]$grid.ColumnDefinitions.Add($col2)
        [void]$grid.ColumnDefinitions.Add($col3)
        
        # Break toggle button
        $btnBreak = New-Object System.Windows.Controls.Button
        $btnBreak.Style = $window.FindResource("ModernButton")
        $btnBreak.Height = 36
        $btnBreak.Content = $cb.name
        $btnBreak.Tag = $cb.id
        [System.Windows.Controls.Grid]::SetColumn($btnBreak, 0)
        
        # Cache button reference
        $global:CustomBreakButtons[$cb.id] = $btnBreak
        
        # If active
        if ($global:ActiveBreakType -eq $cb.id) {
            $btnBreak.Background = $redBrush
            $btnBreak.Content = "I'm Back (00m 00s)"
        } else {
            $btnBreak.Background = $purpleBrush
        }
        
        $currentCb = $cb
        
        # Click event
        $btnBreak.Add_Click({
            Toggle-CustomBreak $currentCb
        })
        
        # Delete button
        $btnDelete = New-Object System.Windows.Controls.Button
        $btnDelete.Style = $window.FindResource("ModernButton")
        $btnDelete.Background = $redBrush
        $btnDelete.Width = 36
        $btnDelete.Height = 36
        # Use Unicode character array constructor to build trash can icon string
        $btnDelete.Content = [char]0xD83D + [char]0xDDD1
        $btnDelete.ToolTip = "Delete Custom Status Button"
        [System.Windows.Controls.Grid]::SetColumn($btnDelete, 2)
        
        $btnDelete.Add_Click({
            $confirm = Show-DeskFlowDialog -title "Confirm Delete" -message "Are you sure you want to delete this custom status button?" -confirmText "DELETE" -cancelText "CANCEL" -icon "🗑️" -confirmColor "#EF4444"
            if ($confirm) {
                if ($global:ActiveBreakType -eq $currentCb.id) {
                    Toggle-CustomBreak $currentCb
                }
                $global:Settings.custom_breaks = @($global:Settings.custom_breaks | Where-Object { $_.id -ne $currentCb.id })
                Save-Settings
                Load-CustomBreaks
                Update-BreakButtonsState
            }
        })
        
        [void]$grid.Children.Add($btnBreak)
        [void]$grid.Children.Add($btnDelete)
        
        [void]$panelCustomBreaks.Children.Add($grid)
    }
}

function Toggle-CustomBreak {
    param($customBreak)
    
    if (-not $global:OfficeStarted) {
        Start-Office
    }
    
    if ($global:ActiveBreakType -eq $null) {
        # Start break
        $global:ActiveBreakType = $customBreak.id
        $global:BreakStartTime = Get-Date
        $global:ActiveBreakElapsedSeconds = 0
        
        Update-BreakButtonsState
        
        $msg = Format-Template -template $customBreak.start_template
        
        Append-Preview $msg
        Copy-ToClipboard $msg
        Send-WebhookMessage $msg
        Log-Activity "$($customBreak.name) Break Started"
        Show-Toast "✓ $($customBreak.name) Started (Copied)" "#10AC84" "#155724"
    }
    elseif ($global:ActiveBreakType -eq $customBreak.id) {
        # Return from break
        $endTime = Get-Date
        $durationSpan = $endTime - $global:BreakStartTime
        $durationMinutes = [Math]::Round($durationSpan.TotalMinutes)
        
        $global:TotalBreakDurationSeconds += $durationSpan.TotalSeconds
        
        $msg = Format-Template -template $customBreak.return_template -duration $durationMinutes
        
        $global:ActiveBreakType = $null
        $global:BreakStartTime = $null
        $global:ActiveBreakElapsedSeconds = 0
        
        Update-BreakButtonsState
        
        Append-Preview $msg
        Copy-ToClipboard $msg
        Send-WebhookMessage $msg
        Log-Activity "$($customBreak.name) Break Ended ($durationMinutes min)"
        Show-Toast "✓ Returned from $($customBreak.name) (Copied)" "#10AC84" "#155724"
    }
}

# Toggling breaks
function Toggle-Break {
    param([string]$type)
    
    if (-not $global:OfficeStarted) {
        # Auto-start office when starting a break for convenience
        Start-Office
    }
    
    if ($global:ActiveBreakType -eq $null) {
        # Start break
        $global:ActiveBreakType = $type
        $global:BreakStartTime = Get-Date
        $global:ActiveBreakElapsedSeconds = 0
        
        # Auto-pause active tasks when starting a break
        foreach ($t in $global:TaskList) {
            if ($t.IsActive) {
                $t.IsActive = $false
                $t.BtnToggleTimer.Content = "▶"
                $t.BtnToggleTimer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10AC84")
                $global:LastActiveTaskBeforeBreak = $t
                Sync-TaskRow -TaskObj $t
            }
        }
        
        Update-BreakButtonsState
        
        $templateKey = switch ($type) {
            "Lunch" { "lunch_start" }
            "Prayer" { "prayer_start" }
            "Combo" { "combo_start" }
        }
        $msg = Format-Template -template $global:Settings.templates.$templateKey
        
        Append-Preview $msg
        Copy-ToClipboard $msg
        Send-WebhookMessage $msg
        Log-Activity "$type Break Started"
        Show-Toast "✓ $type Break Started (Copied)" "#10AC84" "#155724"
    }
    elseif ($global:ActiveBreakType -eq $type) {
        # Return from break
        $endTime = Get-Date
        $durationSpan = $endTime - $global:BreakStartTime
        $durationMinutes = [Math]::Round($durationSpan.TotalMinutes)
        
        # Accumulate break time
        $global:TotalBreakDurationSeconds += $durationSpan.TotalSeconds
        
        $templateKey = switch ($type) {
            "Lunch" { "lunch_return" }
            "Prayer" { "prayer_return" }
            "Combo" { "combo_return" }
        }
        $msg = Format-Template -template $global:Settings.templates.$templateKey -duration $durationMinutes
        
        $global:ActiveBreakType = $null
        $global:BreakStartTime = $null
        $global:ActiveBreakElapsedSeconds = 0
        
        # Auto-resume last active task when returning from break
        if ($null -ne $global:LastActiveTaskBeforeBreak) {
            $t = $global:LastActiveTaskBeforeBreak
            if ($global:TaskList.Contains($t)) {
                $t.IsActive = $true
                $t.BtnToggleTimer.Content = "⏸"
                $t.BtnToggleTimer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF9F43")
                $t.Status = "In Progress"
                # Update status combo selection
                $cmb = Find-VisualChild -Parent $t.Grid -Name "CmbStatus"
                if ($null -ne $cmb) {
                    foreach ($item in $cmb.Items) {
                        if ($item.Content.ToString() -eq "In Progress") {
                            $item.IsSelected = $true
                            break
                        }
                    }
                }
                Sync-TaskRow -TaskObj $t
            }
            $global:LastActiveTaskBeforeBreak = $null
        }
        
        Update-BreakButtonsState
        
        Append-Preview $msg
        Copy-ToClipboard $msg
        Send-WebhookMessage $msg
        Log-Activity "$type Break Ended ($durationMinutes min)"
        Show-Toast "✓ Returned from $type (Copied)" "#10AC84" "#155724"
    }
}

# Log completed break from idle popup
function Log-IdleBreak {
    param([string]$type)
    
    $gridIdlePrompt.Visibility = [System.Windows.Visibility]::Collapsed
    
    $awayMin = $global:AwayDurationMinutes
    $awaySeconds = $awayMin * 60
    
    $global:TotalBreakDurationSeconds += $awaySeconds
    
    $templateKey = switch ($type) {
        "Lunch" { "lunch_return" }
        "Prayer" { "prayer_return" }
        "Combo" { "combo_return" }
    }
    
    $msg = Format-Template -template $global:Settings.templates.$templateKey -duration $awayMin
    Append-Preview $msg
    Copy-ToClipboard $msg
    Send-WebhookMessage $msg
    Log-Activity "$type Break Logged from Idle ($awayMin min)"
    Show-Toast "✓ Idle $type Logged & Copied" "#10AC84" "#155724"
}

# Trigger Good Morning Action
function Trigger-GoodMorning {
    $msg = Format-Template -template $global:Settings.templates.good_morning
    Append-Preview $msg
    Copy-ToClipboard $msg
    Send-WebhookMessage $msg
    Log-Activity "Good Morning Status Generated"
    Show-Toast "✓ Good Morning Status Copied" "#10AC84" "#155724"
}

# Clear Preview Panel Action
function Clear-PreviewConfirm {
    $confirm = Show-DeskFlowDialog -title "Confirm Clear Timeline" -message "Are you sure you want to clear the preview pane and today's activity timeline?" -confirmText "CLEAR TIMELINE" -cancelText "CANCEL" -icon "🗑️" -confirmColor "#EF4444"
    if ($confirm) {
        $listPreview.Items.Clear()
        $listTimeline.Items.Clear()
        Log-Activity "Cleared Preview and Timeline"
        Show-Toast "✓ Cleared Preview & Timeline" "#10AC84" "#155724"
    }
}

# Task Update Generator Action (does not stop session)
function Trigger-TaskUpdate {
    if (-not $global:OfficeStarted) {
        Show-Toast "⚠️ Please start office session first!" "#FF4D4D" "#8B0000"
        return
    }
    
    $now = Get-Date
    $totalElapsedSeconds = ($now - $global:OfficeStartTime).TotalSeconds
    $workedSeconds = $totalElapsedSeconds - $global:TotalBreakDurationSeconds
    $totalBreakSeconds = $global:TotalBreakDurationSeconds
    
    if ($global:ActiveBreakType -ne $null) {
        $currentBreakSeconds = ($now - $global:BreakStartTime).TotalSeconds
        $workedSeconds -= $currentBreakSeconds
        $totalBreakSeconds += $currentBreakSeconds
    }
    if ($workedSeconds -lt 0) { $workedSeconds = 0 }
    
    $ts = [TimeSpan]::FromSeconds($workedSeconds)
    $workedHoursStr = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
    
    $taskUpdateText = Get-TaskUpdateText
    
    # Generate the task update message
    $msg = Format-Template -template $global:Settings.templates.task_update -workingHours $workedHoursStr -taskUpdate $taskUpdateText
    
    Append-Preview $msg
    Copy-ToClipboard $msg
    Send-WebhookMessage $msg
    Log-Activity "Task Update Generated ($workedHoursStr)"
    Show-Toast "✓ Task Update Copied ($workedHoursStr)" "#10AC84" "#155724"
}

# Leaving from Office Action (stops session & saves final history)
function Trigger-LeavingOffice {
    if (-not $global:OfficeStarted) {
        Show-Toast "⚠️ Please start office session first!" "#FF4D4D" "#8B0000"
        return
    }
    
    $confirm = Show-DeskFlowDialog -title "Confirm Leaving Office" -message "Are you sure you want to end your office session and log today's work to history?" -confirmText "END SESSION" -cancelText "CANCEL" -icon "🚪" -confirmColor "#8B5CF6"
    if (-not $confirm) {
        return
    }
    
    $now = Get-Date
    $totalElapsedSeconds = ($now - $global:OfficeStartTime).TotalSeconds
    $workedSeconds = $totalElapsedSeconds - $global:TotalBreakDurationSeconds
    $totalBreakSeconds = $global:TotalBreakDurationSeconds
    
    if ($global:ActiveBreakType -ne $null) {
        $currentBreakSeconds = ($now - $global:BreakStartTime).TotalSeconds
        $workedSeconds -= $currentBreakSeconds
        $totalBreakSeconds += $currentBreakSeconds
    }
    if ($workedSeconds -lt 0) { $workedSeconds = 0 }
    
    $ts = [TimeSpan]::FromSeconds($workedSeconds)
    $workedHoursStr = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
    
    $tsBreak = [TimeSpan]::FromSeconds($totalBreakSeconds)
    $breakHoursStr = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($tsBreak.TotalHours), $tsBreak.Minutes, $tsBreak.Seconds)
    
    $taskUpdateText = Get-TaskUpdateText
    
    # Save the final log state of the day to history
    Save-DayToHistory -workedHours $workedHoursStr -breakHours $breakHoursStr -taskUpdate $taskUpdateText
    
    # Generate the leaving status message
    $msg = Format-Template -template $global:Settings.templates.leaving_office
    
    Append-Preview $msg
    Copy-ToClipboard $msg
    Send-WebhookMessage $msg
    Log-Activity "Leaving from Office Status Generated"
    Show-Toast "✓ Leaving from Office Status Copied" "#10AC84" "#155724"
    
    # Actually stop the office session
    Stop-Office -Force
}

# 6. Database / Persistence Actions

# Save to daily log history
function Save-DayToHistory {
    param(
        [string]$workedHours,
        [string]$breakHours,
        [string]$taskUpdate
    )
    
    $historyFile = Join-Path $global:DataDir "history.json"
    $history = @()
    if (Test-Path $historyFile) {
        try {
            $history = Get-Content $historyFile -Raw | ConvertFrom-Json
            if ($null -eq $history) { $history = @() }
        } catch {
            $history = @()
        }
    }
    
    $timelineItems = @()
    foreach ($item in $listTimeline.Items) {
        $timelineItems += $item
    }
    
    $allText = @()
    foreach ($item in $listPreview.Items) {
        $allText += $item
    }
    $combinedText = [string]::Join("`r`n`r`n", $allText)
    
    $newEntry = [PSCustomObject]@{
        date = (Get-Date).ToString("yyyy-MM-dd")
        display_date = (Get-Date).ToString("dddd, MMMM d, yyyy")
        worked_hours = $workedHours
        break_duration = $breakHours
        task_update = $taskUpdate
        timeline = $timelineItems
        preview_text = $combinedText
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    # Avoid duplicate daily entries (overwrite today's entry if already created)
    $todayDate = (Get-Date).ToString("yyyy-MM-dd")
    $filteredHistory = @()
    foreach ($entry in $history) {
        if ($entry.date -ne $todayDate) {
            $filteredHistory += $entry
        }
    }
    $filteredHistory += $newEntry
    
    $json = ConvertTo-Json $filteredHistory -Depth 10
    Set-Content -Path $historyFile -Value $json -Force
}

# Helper to find child controls recursively in WPF visual tree
function Find-VisualChild {
    param(
        [Parameter(Mandatory=$true)]
        $Parent,
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    if ($null -eq $Parent) { return $null }
    
    # Try finding in ContentControl content
    if ($Parent -is [System.Windows.Controls.ContentControl]) {
        if ($Parent.Content -is [System.Windows.DependencyObject]) {
            if ($Parent.Content.Name -eq $Name) {
                return $Parent.Content
            }
            $result = Find-VisualChild -Parent $Parent.Content -Name $Name
            if ($null -ne $result) { return $result }
        }
    }
    
    # Try finding in Panel Children
    if ($Parent -is [System.Windows.Controls.Panel]) {
        foreach ($child in $Parent.Children) {
            if ($child -is [System.Windows.DependencyObject]) {
                if ($child.Name -eq $Name) {
                    return $child
                }
                $result = Find-VisualChild -Parent $child -Name $Name
                if ($null -ne $result) { return $result }
            }
        }
    }
    
    # Try logical tree helper
    try {
        $children = [System.Windows.LogicalTreeHelper]::GetChildren($Parent)
        foreach ($child in $children) {
            if ($child -is [System.Windows.DependencyObject]) {
                if ($child.Name -eq $Name) {
                    return $child
                }
                $result = Find-VisualChild -Parent $child -Name $Name
                if ($null -ne $result) { return $result }
            }
        }
    } catch {}
    
    return $null
}

# Sync single task row to Google Sheet (using background jobs to remain non-blocking)
function Sync-TaskRow {
    param(
        [Parameter(Mandatory=$true)]
        $TaskObj,
        
        [string]$Action = "update"
    )
    
    $scriptUrl = $global:Settings.google_script_url
    if ([string]::IsNullOrWhiteSpace($scriptUrl)) {
        Write-Debug "Sync skipped: Google script URL not configured."
        return $false
    }
    
    $border = $TaskObj.BorderSynced
    $textBlock = $TaskObj.TxtSyncedStatus
    if ($null -ne $border -and $null -ne $textBlock) {
        $global:Window.Dispatcher.Invoke({
            $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D291BC")
            $textBlock.Text = "Syncing..."
            $textBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        })
    }
    
    # Format entry time string from office session starting time
    $entryTimeStr = ""
    if ($null -ne $global:EntryTime) {
        $entryTimeStr = $global:EntryTime.ToString("hh:mm tt")
    }
    
    $taskIdx = 1
    if ($null -ne $global:TaskList) {
        $idx = $global:TaskList.IndexOf($TaskObj)
        if ($idx -ge 0) {
            $taskIdx = $idx + 1
        }
    }
    
    # Kill any existing job with same name to prevent duplicate-name crash
    $jobName = "SyncTask_" + $TaskObj.Id
    $existingJob = Get-Job -Name $jobName -ErrorAction SilentlyContinue
    if ($null -ne $existingJob) {
        Stop-Job -Job $existingJob -ErrorAction SilentlyContinue
        Remove-Job -Job $existingJob -Force -ErrorAction SilentlyContinue
    }
    
    Start-Job -Name $jobName -ArgumentList $scriptUrl, $global:Settings.user_name, $global:Settings.user_role, $TaskObj.Project, $TaskObj.Details, $TaskObj.Link, $TaskObj.Status, $TaskObj.Duration, $entryTimeStr, $taskIdx, $Action -ScriptBlock {
        param($url, $user, $role, $project, $details, $link, $status, $duration, $entryTime, $taskIndex, $actionType)
        
        $today = (Get-Date).ToString("d MMMM")
        $timeStr = (Get-Date).ToString("hh:mm:ss tt")
        
        $body = @{
            date = $today
            name = $user
            role = $role
            entry = $entryTime
            project = $project
            task = $details
            link = $link
            status = $status
            duration = $duration
            time = $timeStr
            task_index = $taskIndex
            action = $actionType
        } | ConvertTo-Json -Depth 5
        
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10
            return @{ Success = $true; Response = $response }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    } | Out-Null
    
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        try {
            $job = Get-Job -Name ("SyncTask_" + $TaskObj.Id) -ErrorAction SilentlyContinue
            if ($null -ne $job -and $job.State -ne "Running") {
                $timer.Stop()
                $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                
                $resultObj = $null
                if ($null -ne $result) {
                    if ($result -is [array]) {
                        $resultObj = $result | Where-Object { $_ -is [System.Collections.IDictionary] -or $_ -is [PSCustomObject] } | Select-Object -Last 1
                    } else {
                        $resultObj = $result
                    }
                }
                
                if ($null -ne $resultObj -and $resultObj.Success) {
                    $TaskObj.Synced = $true
                    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10AC84")
                    $textBlock.Text = "Synced"
                    $textBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
                } else {
                    $TaskObj.Synced = $false
                    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EA2027")
                    $textBlock.Text = "Failed"
                    $textBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
                    
                    # Check for 401 and alert user nicely
                    $errMsg = if ($null -ne $resultObj) { $resultObj.Error } else { "Unknown error" }
                    if ($errMsg -like "*401*") {
                        Show-Toast "⚠ 401 Unauthorized: Please set 'Who has access: Anyone' in Apps Script!" "#FF4D4D" "#8B0000"
                    } else {
                        Write-Warning "Sync failed: $errMsg"
                    }
                }
            }
        } catch {
            Write-Warning "Error in Sync check tick: $_"
        }
    }.GetNewClosure())
    $timer.Start()
    return $true
}

# Update visual row index indicators
function Update-TaskIndices {
    for ($i = 0; $i -lt $global:TaskList.Count; $i++) {
        $task = $global:TaskList[$i]
        $txtIdx = Find-VisualChild -Parent $task.Grid -Name "TxtIndex"
        if ($null -ne $txtIdx) {
            $txtIdx.Text = ($i + 1).ToString()
        }
    }
}

# Generate formatted task details summary text
function Get-TaskUpdateText {
    $lines = @()
    foreach ($task in $global:TaskList) {
        $projPart = if ([string]::IsNullOrWhiteSpace($task.Project)) { "" } else { "[" + $task.Project.Trim() + "] " }
        $detailsPart = $task.Details.Trim()
        $linkPart = if ([string]::IsNullOrWhiteSpace($task.Link)) { "" } else { " (" + $task.Link.Trim() + ")" }
        $statusPart = " - " + $task.Status
        $durationPart = " (" + $task.Duration + ")"
        
        if (-not [string]::IsNullOrWhiteSpace($detailsPart)) {
            $lines += "- $projPart$detailsPart$linkPart$statusPart$durationPart"
        }
    }
    return $lines -join "`n"
}

# Visual preview helper placeholder
function Update-TaskUpdatePreview {
    Write-Debug "Task update preview updated."
}

# Create and add a new dynamic task row grid element to the UI
function Add-TaskRow {
    param(
        [string]$ProjectCode = "",
        [string]$Details = "",
        [string]$Link = "",
        [string]$Status = "In Progress",
        [string]$Duration = "00:00:00",
        [bool]$Synced = $false
    )
    
    $taskId = [Guid]::NewGuid().ToString()
    
    $rowXaml = @"
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Margin="0,0,0,8" Height="30">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="105"/> <!-- Actions -->
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="80"/>  <!-- Project Code -->
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="*"/>   <!-- Task Details -->
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="150"/> <!-- Link / URL -->
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="120"/> <!-- Status -->
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="90"/>  <!-- Tracked Duration -->
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="80"/>  <!-- Synced Badge -->
    </Grid.ColumnDefinitions>
    
    <Grid Grid.Column="0">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="30"/>
            <ColumnDefinition Width="35"/>
            <ColumnDefinition Width="5"/>
            <ColumnDefinition Width="35"/>
        </Grid.ColumnDefinitions>
        <TextBlock Name="TxtIndex" Grid.Column="0" Text="1" Foreground="#8F8F9D" FontSize="11" VerticalAlignment="Center" HorizontalAlignment="Center"/>
        <Button Name="BtnToggleTimer" Grid.Column="1" Content="▶" FontSize="12" Height="28" Background="#10AC84" Foreground="White" BorderThickness="0" Cursor="Hand"/>
        <Button Name="BtnDelete" Grid.Column="3" Content="🗑" FontSize="12" Height="28" Background="#D63031" Foreground="White" BorderThickness="0" Cursor="Hand"/>
    </Grid>
    
    <TextBox Name="TxtProject" Grid.Column="2" Style="{DynamicResource ModernTextBox}" Height="30" Tag="Project..."/>
    <TextBox Name="TxtDetails" Grid.Column="4" Style="{DynamicResource ModernTextBox}" Height="30" Tag="Task Details..."/>
    <TextBox Name="TxtLink" Grid.Column="6" Style="{DynamicResource ModernTextBox}" Height="30" Tag="Link/URL..."/>
    
    <ComboBox Name="CmbStatus" Grid.Column="8" Height="30" Background="#1E1E26" Foreground="Black" FontWeight="Bold" BorderBrush="#2D2D37" BorderThickness="1" VerticalContentAlignment="Center">
        <ComboBoxItem Content="In Progress"/>
        <ComboBoxItem Content="Complete"/>
        <ComboBoxItem Content="Waiting for confirmation"/>
    </ComboBox>
    
    <TextBox Name="TxtDuration" Grid.Column="10" Text="00:00:00" Foreground="White" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" HorizontalAlignment="Center" Background="Transparent" BorderThickness="0" IsReadOnly="True" Cursor="Hand" Padding="4,2"/>
    
    <Border Name="BorderSynced" Grid.Column="12" CornerRadius="4" Background="#2D2D37" Height="22" VerticalAlignment="Center" HorizontalAlignment="Center" Padding="8,2">
        <TextBlock Name="TxtSyncedStatus" Text="Pending" Foreground="#B0B0C0" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
    </Border>
</Grid>
"@

    $rowGrid = [System.Windows.Markup.XamlReader]::Parse($rowXaml)
    
    $txtIndex = Find-VisualChild -Parent $rowGrid -Name "TxtIndex"
    $btnToggleTimer = Find-VisualChild -Parent $rowGrid -Name "BtnToggleTimer"
    $btnDelete = Find-VisualChild -Parent $rowGrid -Name "BtnDelete"
    $txtProject = Find-VisualChild -Parent $rowGrid -Name "TxtProject"
    $txtDetails = Find-VisualChild -Parent $rowGrid -Name "TxtDetails"
    $txtLink = Find-VisualChild -Parent $rowGrid -Name "TxtLink"
    $cmbStatus = Find-VisualChild -Parent $rowGrid -Name "CmbStatus"
    $txtDurationCtrl = Find-VisualChild -Parent $rowGrid -Name "TxtDuration"
    $borderSynced = Find-VisualChild -Parent $rowGrid -Name "BorderSynced"
    $txtSyncedStatus = Find-VisualChild -Parent $rowGrid -Name "TxtSyncedStatus"
    
    $txtProject.Text = $ProjectCode
    $txtDetails.Text = $Details
    $txtLink.Text = $Link
    $txtDurationCtrl.Text = $Duration
    
    $foundStatus = $false
    foreach ($item in $cmbStatus.Items) {
        if ($item.Content.ToString() -eq $Status) {
            $item.IsSelected = $true
            $foundStatus = $true
            break
        }
    }
    if (-not $foundStatus) { $cmbStatus.SelectedIndex = 0 }
    
    $ts = [TimeSpan]::Zero
    [TimeSpan]::TryParse($Duration, [ref]$ts) | Out-Null
    
    $taskObj = [PSCustomObject]@{
        Id = $taskId
        Project = $ProjectCode
        Details = $Details
        Link = $Link
        Status = $Status
        Duration = $Duration
        TimeSpan = $ts
        IsActive = $false
        Synced = $Synced
        Grid = $rowGrid
        TxtDuration = $txtDurationCtrl
        BorderSynced = $borderSynced
        TxtSyncedStatus = $txtSyncedStatus
        BtnToggleTimer = $btnToggleTimer
        CmbStatus = $cmbStatus
    }
    
    # Store references on control tags for scope reliability
    $txtProject.Tag = $taskObj
    $txtDetails.Tag = $taskObj
    $txtLink.Tag = $taskObj
    $cmbStatus.Tag = $taskObj
    $btnToggleTimer.Tag = $taskObj
    $btnDelete.Tag = $taskObj
    $txtDurationCtrl.Tag = $taskObj
    
    # Triple-Click Secret Duration Editor
    $txtDurationCtrl.Add_PreviewMouseDown({
        param($src, $ev)
        if ($ev.ClickCount -eq 3) {
            $ev.Handled = $true
            $ctrl = $src
            $task = $ctrl.Tag
            
            # Secret unlock for edit
            $ctrl.IsReadOnly = $false
            $ctrl.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D2D37")
            $ctrl.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8B5CF6")
            $ctrl.BorderThickness = New-Object System.Windows.Thickness(1)
            $ctrl.SelectAll()
            $ctrl.Focus()
        }
    })
    
    $txtDurationCtrl.Add_KeyDown({
        param($src, $ev)
        if ($ev.Key -eq [System.Windows.Input.Key]::Enter) {
            $ev.Handled = $true
            $src.MoveFocus((New-Object System.Windows.Input.TraversalRequest([System.Windows.Input.FocusNavigationDirection]::Next)))
        }
    })
    
    $txtDurationCtrl.Add_LostFocus({
        $ctrl = $this
        $task = $ctrl.Tag
        if ($null -eq $task) { return }
        
        if (-not $ctrl.IsReadOnly) {
            # Lock control back
            $ctrl.IsReadOnly = $true
            $ctrl.Background = [System.Windows.Media.Brushes]::Transparent
            $ctrl.BorderThickness = New-Object System.Windows.Thickness(0)
            
            $text = $ctrl.Text.Trim()
            $tsParsed = [TimeSpan]::Zero
            $parsed = [TimeSpan]::TryParse($text, [ref]$tsParsed)
            if (-not $parsed) {
                if ($text -match '^(\d+):(\d+)$') {
                    $tsParsed = New-TimeSpan -Hours ([int]$matches[1]) -Minutes ([int]$matches[2])
                    $parsed = $true
                } elseif ($text -match '^\d+$') {
                    $tsParsed = New-TimeSpan -Minutes ([int]$text)
                    $parsed = $true
                }
            }
            
            if ($parsed) {
                $formatted = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($tsParsed.TotalHours), $tsParsed.Minutes, $tsParsed.Seconds)
                $task.TimeSpan = $tsParsed
                $task.Duration = $formatted
                $ctrl.Text = $formatted
                
                Update-TaskUpdatePreview
                Sync-TaskRow -TaskObj $task
                Show-Toast "✅ Task duration updated to $formatted" "#10AC84" "#155724"
            } else {
                $ctrl.Text = $task.Duration
                Show-Toast "⚠️ Invalid duration format! Use HH:mm:ss" "#FF4D4D" "#8B0000"
            }
        }
    })
    
    $global:TaskList.Add($taskObj)
    
    $txtDetails.Add_GotFocus({
        $global:LastFocusedDetailsTextBox = $this
    })
    
    $txtProject.Add_LostFocus({
        $task = $this.Tag
        if ($task.Project -ne $this.Text) {
            $task.Project = $this.Text
            Update-TaskUpdatePreview
            Sync-TaskRow -TaskObj $task
        }
    })
    
    $txtDetails.Add_LostFocus({
        $task = $this.Tag
        if ($task.Details -ne $this.Text) {
            $task.Details = $this.Text
            Update-TaskUpdatePreview
            Sync-TaskRow -TaskObj $task
        }
    })
    
    $txtLink.Add_LostFocus({
        $task = $this.Tag
        if ($task.Link -ne $this.Text) {
            $task.Link = $this.Text
            Update-TaskUpdatePreview
            Sync-TaskRow -TaskObj $task
        }
    })
    
    $cmbStatus.Add_SelectionChanged({
        if ($null -ne $this.SelectedItem) {
            $task = $this.Tag
            $newStatus = $this.SelectedItem.Content.ToString()
            if ($task.Status -ne $newStatus) {
                $task.Status = $newStatus
                
                if ($newStatus -eq "Complete" -or $newStatus -eq "Waiting for confirmation") {
                    if ($task.IsActive) {
                        $task.IsActive = $false
                        $task.BtnToggleTimer.Content = "▶"
                        $task.BtnToggleTimer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10AC84")
                    }
                }
                
                Update-TaskUpdatePreview
                Sync-TaskRow -TaskObj $task
            }
        }
    })
    
    $btnToggleTimer.Add_Click({
        if (-not $global:OfficeStarted) {
            Start-Office
        }
        
        $task = $this.Tag
        if ($task.IsActive) {
            $task.IsActive = $false
            $this.Content = "▶"
            $this.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10AC84")
            Sync-TaskRow -TaskObj $task
        } else {
            foreach ($t in $global:TaskList) {
                if ($t.IsActive) {
                    $t.IsActive = $false
                    $t.BtnToggleTimer.Content = "▶"
                    $t.BtnToggleTimer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10AC84")
                    Sync-TaskRow -TaskObj $t
                }
            }
            
            $task.IsActive = $true
            $this.Content = "⏸"
            $this.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF9F43")
            
            $task.Status = "In Progress"
            foreach ($item in $task.CmbStatus.Items) {
                if ($item.Content.ToString() -eq "In Progress") {
                    $item.IsSelected = $true
                    break
                }
            }
            
            Sync-TaskRow -TaskObj $task
        }
        Update-TaskUpdatePreview
    })
    
    $btnDelete.Tag = @{ Task = $taskObj; Container = $tasksContainer }
    $btnDelete.Add_Click({
        $tagData = $this.Tag
        $task = $tagData.Task
        $container = $tagData.Container
        if ($null -ne $container -and $null -ne $task) {
            # Sync delete action to Google Sheet before removing from local list
            Sync-TaskRow -TaskObj $task -Action "delete"
            
            [void]$container.Children.Remove($task.Grid)
            [void]$global:TaskList.Remove($task)
            Update-TaskIndices
            Update-TaskUpdatePreview
        }
    })
    
    [void]$tasksContainer.Children.Add($rowGrid)
    
    Update-TaskIndices
    Update-TaskUpdatePreview
}

# 7. Navigation Tabs Loading Views

# Dynamic Quick Tasks Loading
function Load-QuickTasks {
    $panelQuickTasks.Children.Clear()
    
    if ($null -eq $global:Settings.quick_tasks) {
        $global:Settings.quick_tasks = @("A+ Content Design", "Listing Image Design", "Code Review", "Bug Fixing", "Client Meeting")
    }
    
    foreach ($taskText in $global:Settings.quick_tasks) {
        $btnTag = New-Object System.Windows.Controls.Button
        $btnTag.Content = "+ " + $taskText
        $btnTag.Style = $window.FindResource("QuickTaskButton")
        $btnTag.Margin = New-Object System.Windows.Thickness(0, 0, 6, 6)
        $btnTag.Padding = New-Object System.Windows.Thickness(8, 4, 8, 4)
        $btnTag.FontSize = 10
        $btnTag.FontWeight = [System.Windows.FontWeights]::Medium
        
        $btnTag.Add_Click({
            if (-not $global:OfficeStarted) {
                Show-Toast "⚠ Please start office session first" "#FF9F43" "#A04000"
                return
            }
            $taskClicked = $this.Content.ToString() -replace '^\+\s*', ''
            Add-TaskRow -ProjectCode "" -Details $taskClicked -Link "" -Status "In Progress" -Duration "00:00:00" -Synced $false
        })
        
        [void]$panelQuickTasks.Children.Add($btnTag)
    }
}

# Global version definition
$global:AppVersion = "1.0.3"
$global:PendingDownloadUrl = $null

function Reset-UpdateUi {
    if ($null -ne $global:BtnCheckUpdate) {
        $global:BtnCheckUpdate.Content = "Check for updates"
        $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8F8F9D")
        $global:BtnCheckUpdate.IsEnabled = $true
    }
}

# Auto-Updater System - uses DispatcherTimer (UI-thread safe, works in ps2exe)
function Invoke-UpdateCheck {
    param([bool]$IsManual = $false)
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "DeskFlow")
        $jsonStr = $wc.DownloadString("https://raw.githubusercontent.com/mitul002/DeskFlow-Official/master/version.json")
        $json = $jsonStr | ConvertFrom-Json
        $latest      = $json.version
        $downloadUrl = $json.url

        if ([string]::IsNullOrWhiteSpace($latest)) { throw "No version info" }

        $latestVer  = [System.Version]$latest
        $currentVer = [System.Version]$global:AppVersion

        if ($latestVer -gt $currentVer) {
            # If no URL in version.json, try GitHub API for the actual asset
            if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
                try {
                    $apiWc = New-Object System.Net.WebClient
                    $apiWc.Headers.Add("User-Agent", "DeskFlow")
                    $releaseJson = $apiWc.DownloadString("https://api.github.com/repos/mitul002/DeskFlow-Official/releases/latest") | ConvertFrom-Json
                    $asset = $releaseJson.assets | Where-Object { $_.name -like "*Setup*.exe" -or $_.name -like "*.exe" } | Select-Object -First 1
                    if ($null -ne $asset) { $downloadUrl = $asset.browser_download_url }
                } catch {}
            }
            $global:PendingDownloadUrl = $downloadUrl

            if ($IsManual) {
                if ($null -ne $global:BtnCheckUpdate) {
                    $global:BtnCheckUpdate.Content = "New version available (v$latest) — Click to Install"
                    $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#82AAFF")
                    $global:BtnCheckUpdate.IsEnabled = $true
                }
            } else {
                # Custom styled update dialog instead of Windows MessageBox
                $latestCopy = $latest
                $urlCopy    = $downloadUrl
                $dlgResult = Show-DeskFlowDialog `
                    -title "Update Available" `
                    -message "A new version of DeskFlow (v$latestCopy) is ready to install.`n`nYour current version is v$($global:AppVersion). Update now for the latest fixes and improvements." `
                    -confirmText "UPDATE NOW" `
                    -cancelText "LATER" `
                    -icon "🚀" `
                    -confirmColor "#8B5CF6" `
                    -showCancel $true
                if ($dlgResult -eq $true) {
                    Show-Tab "About"
                    if ($null -ne $global:BtnCheckUpdate) {
                        $global:BtnCheckUpdate.Content = "New version available (v$latestCopy) — Click to Install"
                        $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#82AAFF")
                        $global:BtnCheckUpdate.IsEnabled = $true
                    }
                    Start-DownloadAndInstallUpdate -url $urlCopy
                }
            }
        } else {
            if ($IsManual -and $null -ne $global:BtnCheckUpdate) {
                $global:BtnCheckUpdate.Content = "You're on the latest version"
                $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10AC84")
                $global:BtnCheckUpdate.IsEnabled = $true
                $rt = New-Object System.Windows.Threading.DispatcherTimer
                $rt.Interval = [TimeSpan]::FromSeconds(4)
                $rt.Add_Tick({
                    $rt.Stop()
                    Reset-UpdateUi
                }.GetNewClosure())
                $rt.Start()
            }
        }
    } catch {
        if ($IsManual -and $null -ne $global:BtnCheckUpdate) {
            $global:BtnCheckUpdate.Content = "Check failed — click to retry"
            $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF4D4D")
            $global:BtnCheckUpdate.IsEnabled = $true
            $rt = New-Object System.Windows.Threading.DispatcherTimer
            $rt.Interval = [TimeSpan]::FromSeconds(4)
            $rt.Add_Tick({
                $rt.Stop()
                Reset-UpdateUi
            }.GetNewClosure())
            $rt.Start()
        }
    }
}

function Check-ForUpdates {
    param([bool]$IsManual = $false)

    if ($IsManual) {
        if ($null -ne $global:BtnCheckUpdate) {
            $global:BtnCheckUpdate.IsEnabled = $false
            $global:BtnCheckUpdate.Content = "Checking for updates..."
            $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8F8F9D")
        }
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(150)
        $t.Add_Tick({
            $t.Stop()
            Invoke-UpdateCheck -IsManual $true
        }.GetNewClosure())
        $t.Start()
    } else {
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromSeconds(5)
        $t.Add_Tick({
            $t.Stop()
            Invoke-UpdateCheck -IsManual $false
        }.GetNewClosure())
        $t.Start()
    }
}

function Start-DownloadAndInstallUpdate {
    param([string]$url)

    if ([string]::IsNullOrWhiteSpace($url)) {
        # Fallback: try GitHub API for the real download URL from DeskFlow-Official
        try {
            $apiWc = New-Object System.Net.WebClient
            $apiWc.Headers.Add("User-Agent", "DeskFlow")
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $releaseJson = $apiWc.DownloadString("https://api.github.com/repos/mitul002/DeskFlow-Official/releases/latest") | ConvertFrom-Json
            $asset = $releaseJson.assets | Where-Object { $_.name -like "*Setup*.exe" -or $_.name -like "*.exe" } | Select-Object -First 1
            if ($null -ne $asset) { $url = $asset.browser_download_url }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($url)) {
        if ($null -ne $global:BtnCheckUpdate) {
            $global:BtnCheckUpdate.Content = "No download link — check GitHub"
            $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF4D4D")
            $global:BtnCheckUpdate.IsEnabled = $true
        }
        return
    }

    if ($null -ne $global:BtnCheckUpdate) {
        $global:BtnCheckUpdate.IsEnabled = $false
        $global:BtnCheckUpdate.Content = "Starting download..."
    }

    $tempDir = Join-Path $env:TEMP "DeskFlowUpdate"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    $installerPath = Join-Path $tempDir "DeskFlow_Setup.exe"

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient

    $wc.Add_DownloadProgressChanged({
        param($src, $ev)
        if ($null -ne $global:BtnCheckUpdate) {
            $global:BtnCheckUpdate.Content = "Downloading... $($ev.ProgressPercentage)%"
        }
    })

    $wc.Add_DownloadFileCompleted({
        param($src, $ev)
        if ($null -ne $ev.Error) {
            if ($null -ne $global:BtnCheckUpdate) {
                $global:BtnCheckUpdate.Content = "Download failed — click to retry"
                $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF4D4D")
                $global:BtnCheckUpdate.IsEnabled = $true
            }
            $rt = New-Object System.Windows.Threading.DispatcherTimer
            $rt.Interval = [TimeSpan]::FromSeconds(4)
            $rt.Add_Tick({ $rt.Stop(); Reset-UpdateUi }.GetNewClosure())
            $rt.Start()
        } else {
            if ($null -ne $global:BtnCheckUpdate) {
                $global:BtnCheckUpdate.Content = "Installing..."
            }
            # Directly compute the installer path inside the callback
            $targetInstaller = Join-Path $env:TEMP "DeskFlowUpdate\DeskFlow_Setup.exe"
            if (Test-Path $targetInstaller) {
                try {
                    Start-Process -FilePath $targetInstaller -ArgumentList "/SILENT /CLOSEAPPLICATIONS" -Verb RunAs
                    [System.Windows.Application]::Current.Shutdown()
                } catch {
                    if ($null -ne $global:BtnCheckUpdate) {
                        $global:BtnCheckUpdate.Content = "Install canceled — click to retry"
                        $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF4D4D")
                        $global:BtnCheckUpdate.IsEnabled = $true
                    }
                }
            } else {
                if ($null -ne $global:BtnCheckUpdate) {
                    $global:BtnCheckUpdate.Content = "Installer missing — click to retry"
                    $global:BtnCheckUpdate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF4D4D")
                    $global:BtnCheckUpdate.IsEnabled = $true
                }
            }
        }
    })

    $wc.DownloadFileAsync([Uri]$url, $installerPath)
}


# Dynamic UI Helper for Off-Day Recurrence Rule
function Add-OffRuleUI {
    param([string]$day, [array]$weeks)
    
    $weeksStr = $weeks -join ", "
    $ruleText = "$day ($weeksStr)"
    
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = "0,0,0,6"
    
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $col2.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($col1)
    [void]$grid.ColumnDefinitions.Add($col2)
    
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = ([char]::ConvertFromUtf32(0x1F504) + " " + $ruleText)
    $lbl.Foreground = [System.Windows.Media.Brushes]::White
    $lbl.FontSize = 12
    $lbl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
    
    $btnDelete = New-Object System.Windows.Controls.Button
    $btnDelete.Content = ([char]::ConvertFromUtf32(0x1F5D1) + [char]0xFE0F)
    $btnDelete.Width = 26
    $btnDelete.Height = 26
    $btnDelete.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnDelete.Background = [System.Windows.Media.Brushes]::Transparent
    $btnDelete.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF4D4D")
    $btnDelete.BorderThickness = 0
    
    $grid.Tag = @{ day = $day; weeks = $weeks }
    [System.Windows.Controls.Grid]::SetColumn($btnDelete, 1)
    
    $btnDelete.Tag = $grid
    $btnDelete.Add_Click({
        $g = $this.Tag
        if ($null -ne $g.Parent) { [void]$g.Parent.Children.Remove($g) }
    })
    
    [void]$grid.Children.Add($lbl)
    [void]$grid.Children.Add($btnDelete)
    [void]$offRulesPanel.Children.Add($grid)
}

# Dynamic UI Helper for Custom Holiday / Off-Day
function Add-OffHolidayUI {
    param([string]$dateStr, [string]$label)
    
    $holidayText = "$dateStr - $label"
    
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = "0,0,0,6"
    
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $col2.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($col1)
    [void]$grid.ColumnDefinitions.Add($col2)
    
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = ([char]::ConvertFromUtf32(0x1F4C5) + " " + $holidayText)
    $lbl.Foreground = [System.Windows.Media.Brushes]::White
    $lbl.FontSize = 12
    $lbl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
    
    $btnDelete = New-Object System.Windows.Controls.Button
    $btnDelete.Content = ([char]::ConvertFromUtf32(0x1F5D1) + [char]0xFE0F)
    $btnDelete.Width = 26
    $btnDelete.Height = 26
    $btnDelete.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnDelete.Background = [System.Windows.Media.Brushes]::Transparent
    $btnDelete.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF4D4D")
    $btnDelete.BorderThickness = 0
    
    $grid.Tag = @{ date = $dateStr; label = $label }
    [System.Windows.Controls.Grid]::SetColumn($btnDelete, 1)
    
    $btnDelete.Tag = $grid
    $btnDelete.Add_Click({
        $g = $this.Tag
        if ($null -ne $g.Parent) { [void]$g.Parent.Children.Remove($g) }
    })
    
    [void]$grid.Children.Add($lbl)
    [void]$grid.Children.Add($btnDelete)
    [void]$offHolidaysPanel.Children.Add($grid)
}

# Helper to add dynamic webhook URL input field
function Add-WebhookUrlInput {
    param([string]$urlValue = "")
    
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = "0,0,0,8"
    
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $col2.Width = [System.Windows.GridLength]::Auto
    
    [void]$grid.ColumnDefinitions.Add($col1)
    [void]$grid.ColumnDefinitions.Add($col2)
    
        $textBox = New-Object System.Windows.Controls.PasswordBox
    $textBox.Style = $window.FindResource("ModernPasswordBox")
    $textBox.Height = 36
    $textBox.Password = $urlValue
    $textBox.Tag = "WebhookUrlInput"
    [System.Windows.Controls.Grid]::SetColumn($textBox, 0)
    
    $btnDelete = New-Object System.Windows.Controls.Button
    $btnDelete.Content = "🗑️"
    $btnDelete.Width = 36
    $btnDelete.Height = 36
    $btnDelete.Margin = "8,0,0,0"
    $btnDelete.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnDelete.Background = [System.Windows.Media.Brushes]::Transparent
    $btnDelete.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF4D4D")
    $btnDelete.BorderThickness = 0
    [System.Windows.Controls.Grid]::SetColumn($btnDelete, 1)
    
    $btnDelete.Tag = $grid
    $btnDelete.Add_Click({
        $g = $this.Tag
        if ($null -ne $g.Parent) { [void]$g.Parent.Children.Remove($g) }
    })
    
    [void]$grid.Children.Add($textBox)
    [void]$grid.Children.Add($btnDelete)
    
    [void]$webhookUrlsPanel.Children.Add($grid)
}

# Settings Page Load/Save
function Redraw-EmailSets {
    $emailSetsPanel.Children.Clear()
    if ($null -eq $global:Settings.email_sets) { return }
    foreach ($set in $global:Settings.email_sets) {
        $setRow = New-Object System.Windows.Controls.Grid
        $setRow.Margin = "0,0,0,5"
        
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = New-Object System.Windows.GridLength(30, [System.Windows.GridUnitType]::Pixel)
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = New-Object System.Windows.GridLength(150, [System.Windows.GridUnitType]::Pixel)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = [System.Windows.GridLength]::Auto
        $col4 = New-Object System.Windows.Controls.ColumnDefinition; $col4.Width = [System.Windows.GridLength]::Auto
        $setRow.ColumnDefinitions.Add($col0)
        $setRow.ColumnDefinitions.Add($col1)
        $setRow.ColumnDefinitions.Add($col2)
        $setRow.ColumnDefinitions.Add($col3)
        $setRow.ColumnDefinitions.Add($col4)

        $rbDefault = New-Object System.Windows.Controls.RadioButton
        $rbDefault.IsChecked = $set.is_default
        $rbDefault.GroupName = "EmailSetDefault"
        $rbDefault.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $rbDefault.Tag = $set.name
        $rbDefault.Add_Click({
            $selectedName = $this.Tag
            foreach ($s in $global:Settings.email_sets) {
                $s.is_default = ($s.name -eq $selectedName)
            }
            Redraw-EmailSets
            Save-Settings
        })
        [System.Windows.Controls.Grid]::SetColumn($rbDefault, 0)
        $setRow.Children.Add($rbDefault)

        $tbName = New-Object System.Windows.Controls.TextBlock
        $tbName.Text = $set.name
        $tbName.Foreground = [System.Windows.Media.Brushes]::White
        $tbName.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($tbName, 1)
        $setRow.Children.Add($tbName)

        $tbEmails = New-Object System.Windows.Controls.TextBlock
        $tbEmails.Text = $set.emails
        $tbEmails.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8F8F9D")
        $tbEmails.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $tbEmails.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        [System.Windows.Controls.Grid]::SetColumn($tbEmails, 2)
        $setRow.Children.Add($tbEmails)
        
        $btnEdit = New-Object System.Windows.Controls.Button
        $btnEdit.Content = [char]0x270E
        $btnEdit.Background = [System.Windows.Media.Brushes]::Transparent
        $btnEdit.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#82AAFF")
        $btnEdit.BorderThickness = 0
        $btnEdit.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnEdit.Margin = "0,0,10,0"
        $btnEdit.Tag = $set
        $btnEdit.Add_Click({
            $setObj = $this.Tag
            $txtSetEmailSetName.Text = $setObj.name
            $txtSetEmailSetEmails.Text = $setObj.emails
            $global:Settings.email_sets = @($global:Settings.email_sets | Where-Object { $_.name -ne $setObj.name })
            Redraw-EmailSets
            Save-Settings
        })
        [System.Windows.Controls.Grid]::SetColumn($btnEdit, 3)
        $setRow.Children.Add($btnEdit)

        $btnDel = New-Object System.Windows.Controls.Button
        $btnDel.Content = [char]0x274C
        $btnDel.Background = [System.Windows.Media.Brushes]::Transparent
        $btnDel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
        $btnDel.BorderThickness = 0
        $btnDel.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnDel.Tag = $set.name
        $btnDel.Add_Click({
            $delName = $this.Tag
            $global:Settings.email_sets = @($global:Settings.email_sets | Where-Object { $_.name -ne $delName })
            Redraw-EmailSets
            Save-Settings
        })
        [System.Windows.Controls.Grid]::SetColumn($btnDel, 4)
        $setRow.Children.Add($btnDel)

        $emailSetsPanel.Children.Add($setRow)
    }
}

function Redraw-HubstaffAccounts {
    $hubstaffAccountsPanel.Children.Clear()
    if ($null -eq $global:Settings.hubstaff_accounts) { return }
    foreach ($acc in $global:Settings.hubstaff_accounts) {
        $accRow = New-Object System.Windows.Controls.Grid
        $accRow.Margin = "0,0,0,5"
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = New-Object System.Windows.GridLength(30, [System.Windows.GridUnitType]::Pixel)
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = New-Object System.Windows.GridLength(2, [System.Windows.GridUnitType]::Star)
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = [System.Windows.GridLength]::Auto
        $col4 = New-Object System.Windows.Controls.ColumnDefinition; $col4.Width = [System.Windows.GridLength]::Auto
        $accRow.ColumnDefinitions.Add($col0)
        $accRow.ColumnDefinitions.Add($col1)
        $accRow.ColumnDefinitions.Add($col2)
        $accRow.ColumnDefinitions.Add($col3)
        $accRow.ColumnDefinitions.Add($col4)

        $rbDefault = New-Object System.Windows.Controls.RadioButton
        $rbDefault.IsChecked = $acc.is_default
        $rbDefault.GroupName = "HubstaffDefault"
        $rbDefault.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $rbDefault.Tag = $acc.name
        $rbDefault.Add_Click({
            $selectedName = $this.Tag
            foreach ($a in $global:Settings.hubstaff_accounts) {
                $a.is_default = ($a.name -eq $selectedName)
            }
            Redraw-HubstaffAccounts
            Save-Settings
        })
        [System.Windows.Controls.Grid]::SetColumn($rbDefault, 0)
        $accRow.Children.Add($rbDefault)

        $tbName = New-Object System.Windows.Controls.TextBlock
        $tbName.Text = $acc.name
        $tbName.Foreground = [System.Windows.Media.Brushes]::White
        $tbName.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($tbName, 1)
        $accRow.Children.Add($tbName)

        $tbEmail = New-Object System.Windows.Controls.TextBlock
        $tbEmail.Text = $acc.email
        $tbEmail.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8F8F9D")
        $tbEmail.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($tbEmail, 2)
        $accRow.Children.Add($tbEmail)
        
        $btnEdit = New-Object System.Windows.Controls.Button
        $btnEdit.Content = [char]0x270E
        $btnEdit.Background = [System.Windows.Media.Brushes]::Transparent
        $btnEdit.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#82AAFF")
        $btnEdit.BorderThickness = 0
        $btnEdit.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnEdit.Margin = "0,0,10,0"
        $btnEdit.Tag = $acc
        $btnEdit.Add_Click({
            $accObj = $this.Tag
            $txtSetHubstaffName.Text = $accObj.name
            $txtSetHubstaffEmailList.Text = $accObj.email
            $txtSetHubstaffPassList.Password = $accObj.password
            
            $global:Settings.hubstaff_accounts = @($global:Settings.hubstaff_accounts | Where-Object { $_.name -ne $accObj.name })
            Redraw-HubstaffAccounts
            Save-Settings
        })
        [System.Windows.Controls.Grid]::SetColumn($btnEdit, 3)
        $accRow.Children.Add($btnEdit)

        $btnDel = New-Object System.Windows.Controls.Button
        $btnDel.Content = [char]0x274C
        $btnDel.Background = [System.Windows.Media.Brushes]::Transparent
        $btnDel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
        $btnDel.BorderThickness = 0
        $btnDel.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnDel.Tag = $acc.name
        $btnDel.Add_Click({
            $delName = $this.Tag
            $global:Settings.hubstaff_accounts = @($global:Settings.hubstaff_accounts | Where-Object { $_.name -ne $delName })
            Redraw-HubstaffAccounts
            Save-Settings
        })
        [System.Windows.Controls.Grid]::SetColumn($btnDel, 4)
        $accRow.Children.Add($btnDel)

        $hubstaffAccountsPanel.Children.Add($accRow)
    }
}

function Load-TaskUpdateView {
    $cmbTaskUpdateHubstaffAccount.Items.Clear()
    
    $defaultItem = New-Object System.Windows.Controls.ComboBoxItem
    $defaultItem.Content = "No Hubstaff"
    $cmbTaskUpdateHubstaffAccount.Items.Add($defaultItem) | Out-Null
    
    if ($null -ne $global:Settings.hubstaff_accounts) {
        foreach ($acc in $global:Settings.hubstaff_accounts) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $acc.name
            $cmbTaskUpdateHubstaffAccount.Items.Add($item) | Out-Null
        }
    }
    $cmbTaskUpdateHubstaffAccount.SelectedIndex = 0
    
    $cmbTaskUpdateEmailSet.Items.Clear()
    $defaultIndex = 0
    $currentIndex = 0
    if ($null -ne $global:Settings.email_sets) {
        foreach ($set in $global:Settings.email_sets) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $set.name
            $cmbTaskUpdateEmailSet.Items.Add($item) | Out-Null
            if ($set.is_default) {
                $defaultIndex = $currentIndex
            }
            $currentIndex++
        }
    }
    if ($cmbTaskUpdateEmailSet.Items.Count -gt 0) {
        $cmbTaskUpdateEmailSet.SelectedIndex = $defaultIndex
    }
    
    $global:TaskUpdateScreenshotPath = ""
    $txtTaskUpdateSSPath.Text = "No screenshot attached"
    $btnTaskUpdateRemoveSS.Visibility = 'Collapsed'
    
    Update-TaskUpdatePreview
}

function Get-TaskUpdateTemplateText {
    param([string]$accountName = "No Hubstaff")
    
    # Calculate worked hours — use saved data if session ended but still same day
    $workedHoursStr = "00:00:00"
    if ($global:OfficeStarted) {
        $now = Get-Date
        $totalElapsedSeconds = ($now - $global:OfficeStartTime).TotalSeconds
        $workedSeconds = $totalElapsedSeconds - $global:TotalBreakDurationSeconds
        if ($global:ActiveBreakType -ne $null) {
            $workedSeconds -= ($now - $global:BreakStartTime).TotalSeconds
        }
        if ($workedSeconds -lt 0) { $workedSeconds = 0 }
        $ts = [TimeSpan]::FromSeconds($workedSeconds)
        $workedHoursStr = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
    } elseif (-not [string]::IsNullOrWhiteSpace($global:SavedWorkedHoursStr)) {
        $workedHoursStr = $global:SavedWorkedHoursStr
    }
    
    $userName = if ([string]::IsNullOrWhiteSpace($global:Settings.user_name)) { "User" } else { $global:Settings.user_name.Trim() }
    
    # Base template text
    $baseText = "Hello Sir/Mam,`r`n`r`nToday, I have worked {working_hours} hrs on the following task:`r`n`r`n{{TASK_TABLE}}"
    if (-not [string]::IsNullOrWhiteSpace($global:Settings.templates.task_update)) {
        $baseText = $global:Settings.templates.task_update
    }
    $baseText = $baseText -replace '\{working_hours\}', $workedHoursStr
    $baseText = $baseText -replace '\{task_update\}', "{{TASK_TABLE}}"
    $baseText = $baseText -replace '\{user_name\}', $userName
    
    if ([string]::IsNullOrWhiteSpace($accountName) -or $accountName -eq "No Hubstaff") {
        return "$baseText`r`n`r`nToday, I didn't maintain Hubstaff`r`n`r`nThank you.`r`n`r`nBest regards,`r`n$userName"
    } else {
        $acc = $global:Settings.hubstaff_accounts | Where-Object { $_.name -eq $accountName }
        if ($null -ne $acc) {
            return "$baseText`r`n`r`nHubstaff Details:`r`n`r`nToday, I maintained Hubstaff.`r`n(Attached Hubstaff Screenshot)`r`n`r`nHubstaff account and Password:`r`n`r`nMail Id: $($acc.email)`r`nPassword: $($acc.password)`r`n`r`nThank you.`r`n`r`nBest regards,`r`n$userName"
        } else {
            return "$baseText`r`n`r`nToday, I didn't maintain Hubstaff`r`n`r`nThank you.`r`n`r`nBest regards,`r`n$userName"
        }
    }
}

function Update-TaskUpdatePreview {
    # Build dynamic subject
    $userName = if ([string]::IsNullOrWhiteSpace($global:Settings.user_name)) { "User" } else { $global:Settings.user_name.Trim() }
    $todayStr = Get-Date -Format 'dd-MM-yyyy'
    $txtTaskUpdateSubject.Text = "$userName - Today's Task - ($todayStr)"
    
    $selectedAcc = "No Hubstaff"
    if ($null -ne $cmbTaskUpdateHubstaffAccount.SelectedItem) {
        $selectedAcc = $cmbTaskUpdateHubstaffAccount.SelectedItem.Content.ToString()
    }
    
    $txtTaskUpdateEmailContent.Text = Get-TaskUpdateTemplateText -accountName $selectedAcc
}

function Send-TaskUpdateEmail {
    param(
        [string]$gmailAddress,
        [string]$gmailAppPassword,
        [string]$recipientEmails,
        [string]$subject,
        [string]$bodyText,
        [string]$screenshotPath = ""
    )
    
    try {
        $smtp = New-Object Net.Mail.SmtpClient("smtp.gmail.com", 587)
        $smtp.EnableSsl = $true
        $smtp.Credentials = New-Object System.Net.NetworkCredential($gmailAddress, $gmailAppPassword)
        
        $mail = New-Object Net.Mail.MailMessage
        $mail.From = New-Object Net.Mail.MailAddress($gmailAddress)
        
        $recipients = $recipientEmails -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($r in $recipients) {
            $mail.To.Add($r)
        }
        
        $mail.Subject = $subject
        $mail.IsBodyHtml = $true
        
        # Format entry time string from office session starting time (or saved)
        $entryTimeStr = ""
        if ($null -ne $global:EntryTime) {
            $entryTimeStr = $global:EntryTime.ToString("hh:mm tt")
        } elseif ($null -ne $global:SavedEntryTime) {
            $entryTimeStr = $global:SavedEntryTime.ToString("hh:mm tt")
        } else {
            $entryTimeStr = (Get-Date).ToString("hh:mm tt")
        }
        
        # Use active task list, or fallback to saved list from stopped session
        $taskSource = $global:TaskList
        if ($global:TaskList.Count -eq 0 -and $null -ne $global:SavedTaskList -and $global:SavedTaskList.Count -gt 0) {
            $taskSource = $global:SavedTaskList
        }
        
        # Build HTML table for tasks to match Google Sheets style
        # Resolve table row background color from settings (default: #e0a3c1)
        $tableBodyColor = if ($null -ne $global:Settings.table_body_color -and $global:Settings.table_body_color -ne "") { $global:Settings.table_body_color } else { "#e0a3c1" }

        # Filter out blank tasks first
        $validTasks = @($taskSource | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Details) })
        $totalRows = $validTasks.Count
        if ($totalRows -eq 0) { $totalRows = 1 }

        # Precompute consecutive project rowspans
        $projRowSpans = @()
        $idx = 0
        while ($idx -lt $validTasks.Count) {
            $currentProj = if ([string]::IsNullOrWhiteSpace($validTasks[$idx].Project)) { "" } else { $validTasks[$idx].Project.Trim() }
            $span = 1
            $jdx = $idx + 1
            while ($jdx -lt $validTasks.Count) {
                $nextProj = if ([string]::IsNullOrWhiteSpace($validTasks[$jdx].Project)) { "" } else { $validTasks[$jdx].Project.Trim() }
                if ($nextProj -eq $currentProj) {
                    $span++
                    $jdx++
                } else {
                    break
                }
            }
            for ($k = 0; $k -lt $span; $k++) {
                if ($k -eq 0) {
                    $projRowSpans += $span
                } else {
                    $projRowSpans += 0
                }
            }
            $idx += $span
        }

        $rows = @()
        $isFirstRow = $true
        for ($r = 0; $r -lt $validTasks.Count; $r++) {
            $task = $validTasks[$r]
            $proj = if ([string]::IsNullOrWhiteSpace($task.Project)) { "" } else { $task.Project.Trim() }
            $details = if ([string]::IsNullOrWhiteSpace($task.Details)) { "" } else { $task.Details.Trim() }
            
            $rawLink = if ([string]::IsNullOrWhiteSpace($task.Link)) { "" } else { $task.Link.Trim() }
            $linkHtml = ""
            if ($rawLink -ne "") {
                $isUrl = $false
                $hrefUrl = $rawLink
                if ($rawLink -match '^https?://' -or $rawLink -match '^www\.') {
                    $isUrl = $true
                    if ($rawLink -match '^www\.') {
                        $hrefUrl = "https://" + $rawLink
                    }
                } else {
                    $uriResult = $null
                    if ([Uri]::TryCreate($rawLink, [UriKind]::Absolute, [ref]$uriResult) -and ($uriResult.Scheme -eq "http" -or $uriResult.Scheme -eq "https")) {
                        $isUrl = $true
                    }
                }
                
                if ($isUrl) {
                    $linkHtml = "<a href='$hrefUrl' target='_blank' style='color:#1155cc;text-decoration:underline;'>$rawLink</a>"
                } else {
                    $linkHtml = [System.Net.WebUtility]::HtmlEncode($rawLink)
                }
            }
            
            $status = $task.Status
            $duration = $task.Duration
            
            # Entry cell: only first row, with rowspan covering all rows
            $entryCellHtml = ""
            if ($isFirstRow) {
                $entryCellHtml = "<td rowspan='$totalRows' style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:$tableBodyColor;font-family:Montserrat, Arial, sans-serif;font-size:10pt;color:#333333;text-align:center;border:1px solid #ccc;'>$entryTimeStr</td>"
                $isFirstRow = $false
            }

            # Project cell: rowspan for consecutive matching projects
            $projCellHtml = ""
            $pSpan = $projRowSpans[$r]
            if ($pSpan -gt 0) {
                $projCellHtml = "<td rowspan='$pSpan' style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:$tableBodyColor;font-family:Montserrat, Arial, sans-serif;font-size:10pt;color:#333333;text-align:center;border:1px solid #ccc;'>$proj</td>"
            }
            
            $rows += "
            <tr style='height:21px;'>
                $entryCellHtml
                $projCellHtml
                <td style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:$tableBodyColor;font-family:Montserrat, Arial, sans-serif;font-size:10pt;color:#333333;text-align:center;border:1px solid #ccc;'>$details</td>
                <td style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:$tableBodyColor;font-family:Montserrat, Arial, sans-serif;font-size:10pt;color:#333333;text-align:center;border:1px solid #ccc;'>$linkHtml</td>
                <td style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:$tableBodyColor;font-family:Montserrat, Arial, sans-serif;font-size:10pt;color:#333333;text-align:center;border:1px solid #ccc;'>$duration</td>
                <td style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:$tableBodyColor;font-family:Montserrat, Arial, sans-serif;font-size:10pt;color:#333333;text-align:center;border:1px solid #ccc;'>$status</td>
            </tr>"
        }
        
        $tableHtml = "
    <table cellspacing='0' cellpadding='0' dir='ltr' border='1' style='table-layout:fixed;font-size:10pt;font-family:Arial, sans-serif;width:0px;border-collapse:collapse;border:none;margin:15px 0;'>
        <colgroup>
            <col width='100'>
            <col width='100'>
            <col width='396'>
            <col width='100'>
            <col width='100'>
            <col width='100'>
        </colgroup>
        <thead>
            <tr style='height:21px;'>
                <th style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:#000;font-family:Montserrat, Arial, sans-serif;font-size:11pt;font-weight:bold;color:#fff;text-align:center;border:1px solid #ccc;'>Entry</th>
                <th style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:#000;font-family:Montserrat, Arial, sans-serif;font-size:11pt;font-weight:bold;color:#fff;text-align:center;border:1px solid #ccc;'>Project</th>
                <th style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:#000;font-family:Montserrat, Arial, sans-serif;font-size:11pt;font-weight:bold;color:#fff;text-align:center;border:1px solid #ccc;'>Task Details</th>
                <th style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:#000;font-family:Montserrat, Arial, sans-serif;font-size:11pt;font-weight:bold;color:#fff;text-align:center;border:1px solid #ccc;'>Link</th>
                <th style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:#000;font-family:Montserrat, Arial, sans-serif;font-size:11pt;font-weight:bold;color:#fff;text-align:center;border:1px solid #ccc;'>Duration</th>
                <th style='overflow:hidden;padding:2px 3px;vertical-align:middle;background-color:#000;font-family:Montserrat, Arial, sans-serif;font-size:11pt;font-weight:bold;color:#fff;text-align:center;border:1px solid #ccc;'>Status</th>
            </tr>
        </thead>
        <tbody>
            $($rows -join '')
        </tbody>
    </table>"

        $body = $bodyText
        
        # Attachment with fixed 550px max width to match Gmail inline image insertion
        $resizedTempPath = ""
        if (-not [string]::IsNullOrWhiteSpace($screenshotPath) -and (Test-Path $screenshotPath)) {
            $imgToAttach = $screenshotPath
            try {
                Add-Type -AssemblyName System.Drawing
                $srcImg = [System.Drawing.Image]::FromFile($screenshotPath)
                $origW = $srcImg.Width
                $origH = $srcImg.Height
                
                # Target width of 550px for standard 1080p display
                $targetW = 550
                if ($origW -gt $targetW) {
                    $newW = $targetW
                    $newH = [math]::Max(1, [math]::Round($origH * ($targetW / $origW)))
                } else {
                    $newW = $origW
                    $newH = $origH
                }

                $bmp = New-Object System.Drawing.Bitmap($newW, $newH)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.DrawImage($srcImg, 0, 0, $newW, $newH)
                $g.Dispose()
                $srcImg.Dispose()

                $tempDir = [System.IO.Path]::GetTempPath()
                $resizedTempPath = [System.IO.Path]::Combine($tempDir, "deskflow_ss_550px_$([Guid]::NewGuid().ToString('N')).png")
                $bmp.Save($resizedTempPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
                $imgToAttach = $resizedTempPath
            } catch {
                $imgToAttach = $screenshotPath
            }

            $attachment = New-Object Net.Mail.Attachment($imgToAttach)
            $attachment.ContentId = "hubstaff_screenshot"
            $attachment.ContentDisposition.Inline = $true
            $attachment.ContentDisposition.DispositionType = "Inline"
            $mail.Attachments.Add($attachment)
            
            $imgTag = "<br/><br/><img src='cid:hubstaff_screenshot' width='550' style='max-width: 550px; width: 550px; height: auto; border: 1px solid #ddd; border-radius: 6px;'/>"
            $body = $body.Replace("(Attached Hubstaff Screenshot)", $imgTag)
        } else {
            # No screenshot — remove the placeholder text so it doesn't appear in email
            $body = $body.Replace("(Attached Hubstaff Screenshot)", "(No screenshot attached)")
        }
        
        # Bold the working hours value and Hubstaff credential label in HTML
        $body = $body -replace '(\d{2}:\d{2}:\d{2})\s+hrs', '<b>$1</b> hrs'
        $body = $body.Replace("Hubstaff account and Password:", "<b>Hubstaff account and Password:</b>")
        
        # Split body by {{TASK_TABLE}}
        $parts = $body -split '\{\{TASK_TABLE\}\}'
        $parts[0] = $parts[0].Trim() -replace "`r?\n", "<br/>"
        if ($parts.Count -gt 1) {
            $parts[1] = $parts[1].Trim() -replace "`r?\n", "<br/>"
            $mail.Body = $parts[0] + "<br/>" + $tableHtml + "<br/>" + $parts[1]
        } else {
            $mail.Body = $parts[0]
        }
        
        # Wrap everything in a nice font container
        $mail.Body = "<div style='font-family: Roboto, Arial, Helvetica, sans-serif; font-size: 13px; color: #333; line-height: 1.6;'>" + $mail.Body + "</div>"
        
        try {
            $smtp.Send($mail)
        } finally {
            $mail.Dispose()
            if ($resizedTempPath -ne "" -and (Test-Path $resizedTempPath)) {
                Remove-Item $resizedTempPath -Force -ErrorAction SilentlyContinue
            }
        }
        $mail.Dispose()
        $smtp.Dispose()
        return $true
    } catch {
        Write-Error $_
        return $false
    }
}

function Load-SettingsView {
    $txtSetGoodMorning.Text = $global:Settings.templates.good_morning
    $txtSetLunchStart.Text = $global:Settings.templates.lunch_start
    $txtSetLunchReturn.Text = $global:Settings.templates.lunch_return
    $txtSetPrayerStart.Text = $global:Settings.templates.prayer_start
    $txtSetPrayerReturn.Text = $global:Settings.templates.prayer_return
    $txtSetComboStart.Text = $global:Settings.templates.combo_start
    $txtSetComboReturn.Text = $global:Settings.templates.combo_return
    $txtSetTaskUpdateTemplate.Text = $global:Settings.templates.task_update
    $txtSetLeavingOfficeTemplate.Text = $global:Settings.templates.leaving_office
    $chkSetMinimizeToTray.IsChecked = $global:Settings.minimize_to_tray
    $chkSetStartWithWindows.IsChecked = $global:Settings.start_with_windows
    $chkSetAutoDetectSession.IsChecked = $global:Settings.auto_detect_session
    
    # Populate Off-Days Checkboxes
    $chkOffSun.IsChecked = $global:Settings.off_days_weekly -contains "Sunday"
    $chkOffMon.IsChecked = $global:Settings.off_days_weekly -contains "Monday"
    $chkOffTue.IsChecked = $global:Settings.off_days_weekly -contains "Tuesday"
    $chkOffWed.IsChecked = $global:Settings.off_days_weekly -contains "Wednesday"
    $chkOffThu.IsChecked = $global:Settings.off_days_weekly -contains "Thursday"
    $chkOffFri.IsChecked = $global:Settings.off_days_weekly -contains "Friday"
    $chkOffSat.IsChecked = $global:Settings.off_days_weekly -contains "Saturday"
        [void]$offRulesPanel.Children.Clear()
    if ($null -ne $global:Settings.off_days_occurrences) {
        foreach ($rule in $global:Settings.off_days_occurrences) {
            Add-OffRuleUI -day $rule.day -weeks $rule.weeks
        }
    }
    
    [void]$offHolidaysPanel.Children.Clear()
    if ($null -ne $global:Settings.off_days_custom) {
        foreach ($holiday in $global:Settings.off_days_custom) {
            Add-OffHolidayUI -dateStr $holiday.date -label $holiday.label
        }
    }
    
    if ($null -ne $global:Settings.gmail_address) { $txtSetGmailAddress.Text = $global:Settings.gmail_address }
    if ($null -ne $global:Settings.gmail_app_password) { $pwdSetGmailAppPassword.Password = $global:Settings.gmail_app_password }
    $loadedColor = if ($null -ne $global:Settings.table_body_color -and $global:Settings.table_body_color -ne "") { $global:Settings.table_body_color } else { "#e0a3c1" }
    if ($null -ne $txtTableBodyColor) { $txtTableBodyColor.Text = $loadedColor }
    if ($null -ne $bdrTableBodyColorPreview) {
        try { $bdrTableBodyColorPreview.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString($loadedColor) } catch {}
    }
    
    if ($null -eq $global:Settings.email_sets) {
        if (-not (Get-Member -InputObject $global:Settings -Name "email_sets")) {
            $global:Settings | Add-Member -MemberType NoteProperty -Name "email_sets" -Value @() -ErrorAction SilentlyContinue
        } else {
            $global:Settings.email_sets = @()
        }
    }
    Redraw-EmailSets
    if ($null -eq $global:Settings.hubstaff_accounts) {
        if (-not (Get-Member -InputObject $global:Settings -Name "hubstaff_accounts")) {
            $global:Settings | Add-Member -MemberType NoteProperty -Name "hubstaff_accounts" -Value @() -ErrorAction SilentlyContinue
        } else {
            $global:Settings.hubstaff_accounts = @()
        }
    }
    Redraw-HubstaffAccounts

    if ($null -ne $global:Settings.quick_tasks) {
        $txtSetQuickTasks.Text = $global:Settings.quick_tasks -join ", "
    } else {
        $txtSetQuickTasks.Text = ""
    }
    
    # Load Webhook config
    $chkSetWebhookEnabled.IsChecked = $global:Settings.webhook_enabled
    $txtSetWebhookDisplayName.Text = $global:Settings.webhook_display_name
    $txtSetWebhookAvatarUrl.Text = $global:Settings.webhook_avatar_url
    
    if ($null -ne $global:Settings.webhook_avatar_emoji) {
        $found = $false
        foreach ($item in $cmbSetWebhookEmoji.Items) {
            if ($item.Content -like "$($global:Settings.webhook_avatar_emoji)*") {
                $item.IsSelected = $true
                $found = $true
                break
            }
        }
        if (-not $found) { $cmbSetWebhookEmoji.SelectedIndex = 0 }
    } else {
        $cmbSetWebhookEmoji.SelectedIndex = 0
    }
    
    [void]$webhookUrlsPanel.Children.Clear()
    if (-not [string]::IsNullOrWhiteSpace($global:Settings.webhook_url)) {
        $urls = $global:Settings.webhook_url -split '[\r\n,]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($url in $urls) {
            Add-WebhookUrlInput -urlValue $url
        }
    }
    if ($webhookUrlsPanel.Children.Count -eq 0) {
        Add-WebhookUrlInput
    }
    
    if ($null -ne $txtSetUserName) { $txtSetUserName.Text = if ($global:Settings.user_name) { $global:Settings.user_name } else { "" } }
    if ($null -ne $txtSetUserRole) { $txtSetUserRole.Text = if ($global:Settings.user_role) { $global:Settings.user_role } else { "" } }
    if ($null -ne $txtSetGoogleScriptUrl) { $txtSetGoogleScriptUrl.Text = if ($global:Settings.google_script_url) { $global:Settings.google_script_url } else { "" } }
    if ($null -ne $txtSetGoogleSheetUrl) { $txtSetGoogleSheetUrl.Text = if ($global:Settings.google_sheet_url) { $global:Settings.google_sheet_url } else { "" } }
}


# Analytics Tab Loading & Chart rendering
function Load-AnalyticsView {
    $historyFile = Join-Path $global:DataDir "history.json"
    $txtAvgWorkHours.Text = "0.0 hrs"
    $txtAvgBreakTime.Text = "0m"
    $txtDaysLogged.Text = "0 days"
    $gridBarChart.Children.Clear()
    
    if (-not (Test-Path $historyFile)) { return }
    
    try {
        $history = Get-Content $historyFile -Raw | ConvertFrom-Json
        if ($null -eq $history -or @($history).Count -eq 0) { return }
        
        $historyArray = @($history)
        $totalDays = $historyArray.Count
        $txtDaysLogged.Text = "$totalDays days"
        
        $totalWorkSeconds = 0
        $totalBreakSeconds = 0
        
        foreach ($entry in $historyArray) {
            if ($entry.worked_hours -match "(\d+):(\d+):(\d+)") {
                $h = [int]$Matches[1]
                $m = [int]$Matches[2]
                $s = [int]$Matches[3]
                $totalWorkSeconds += ($h * 3600) + ($m * 60) + $s
            }
            if ($entry.break_duration -match "(\d+):(\d+):(\d+)") {
                $h = [int]$Matches[1]
                $m = [int]$Matches[2]
                $s = [int]$Matches[3]
                $totalBreakSeconds += ($h * 3600) + ($m * 60) + $s
            }
        }
        
        $avgWorkHrs = ($totalWorkSeconds / $totalDays) / 3600
        $txtAvgWorkHours.Text = [string]::Format("{0:F1} hrs", $avgWorkHrs)
        
        $avgBreakMins = (($totalBreakSeconds / $totalDays) / 60)
        $txtAvgBreakTime.Text = [string]::Format("{0:F0}m", $avgBreakMins)
        
        $last7 = $historyArray
        if ($last7.Count -gt 7) {
            $last7 = $last7 | Select-Object -Last 7
        }
        
        $maxHrs = 8.0
        $dayValues = @()
        foreach ($entry in $last7) {
            $hrs = 0.0
            if ($entry.worked_hours -match "(\d+):(\d+):(\d+)") {
                $hrs = [int]$Matches[1] + ([int]$Matches[2] / 60.0) + ([int]$Matches[3] / 3600.0)
            }
            $dayValues += [PSCustomObject]@{
                DateStr = (Get-Date $entry.date).ToString("MMM d")
                Hours = $hrs
            }
            if ($hrs -gt $maxHrs) { $maxHrs = $hrs }
        }
        
        foreach ($day in $dayValues) {
            $pct = $day.Hours / $maxHrs
            $barHeight = $pct * 140
            if ($barHeight -lt 10) { $barHeight = 10 }
            
            $colContainer = New-Object System.Windows.Controls.StackPanel
            $colContainer.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
            $colContainer.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            
            $txtHrs = New-Object System.Windows.Controls.TextBlock
            $txtHrs.Text = [string]::Format("{0:F1}h", $day.Hours)
            $txtHrs.Foreground = $brushConv.ConvertFromString("#8F8F9D")
            $txtHrs.FontSize = 9
            $txtHrs.FontWeight = [System.Windows.FontWeights]::SemiBold
            $txtHrs.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $txtHrs.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
            [void]$colContainer.Children.Add($txtHrs)
            
            $bar = New-Object System.Windows.Controls.Border
            $bar.Width = 30
            $bar.Height = $barHeight
            $bar.CornerRadius = New-Object System.Windows.CornerRadius(4, 4, 0, 0)
            $bar.Background = $brushConv.ConvertFromString("#6C5CE7")
            $bar.ToolTip = "$([string]::Format('{0:F2}', $day.Hours)) hrs worked"
            
            $bar.Add_MouseEnter({
                $this.Background = $brushConv.ConvertFromString("#8275E9")
            })
            $bar.Add_MouseLeave({
                $this.Background = $brushConv.ConvertFromString("#6C5CE7")
            })
            [void]$colContainer.Children.Add($bar)
            
            $lblDate = New-Object System.Windows.Controls.TextBlock
            $lblDate.Text = $day.DateStr
            $lblDate.Foreground = $brushConv.ConvertFromString("#B0B0C0")
            $lblDate.FontSize = 10
            $lblDate.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $lblDate.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
            [void]$colContainer.Children.Add($lblDate)
            
            [void]$gridBarChart.Children.Add($colContainer)
        }
    } catch {
        # Silent fail
    }
}

# History Page View Loading
function Load-HistoryView {
    $historyFile = Join-Path $global:DataDir "history.json"
    $listHistoryDays.Items.Clear()
    $txtHistoryWorked.Text = "Worked: 00:00:00"
    $txtHistoryBreak.Text = "Break: 00:00:00"
    $txtHistoryTasks.Text = ""
    $txtHistoryPreview.Text = ""
    $listHistoryTimeline.Items.Clear()
    
    if (Test-Path $historyFile) {
        try {
            $history = Get-Content $historyFile -Raw | ConvertFrom-Json
            if ($null -ne $history) {
                # Load array and reverse it to show newest day first
                $historyArray = @($history)
                [array]::Reverse($historyArray)
                foreach ($entry in $historyArray) {
                    $listHistoryDays.Items.Add($entry.display_date)
                }
                $global:LoadedHistory = $historyArray
            }
        } catch {
            Show-Toast "Error loading history data" "#FF4D4D" "#8B0000"
        }
    }
}

$listHistoryDays.Add_SelectionChanged({
    $idx = $listHistoryDays.SelectedIndex
    if ($idx -ge 0 -and $null -ne $global:LoadedHistory -and $idx -lt $global:LoadedHistory.Length) {
        $entry = $global:LoadedHistory[$idx]
        $txtHistoryWorked.Text = "Worked: $($entry.worked_hours)"
        $breakVal = "00:00:00"
        if ($null -ne $entry.break_duration) {
            $breakVal = $entry.break_duration
        }
        $txtHistoryBreak.Text = "Break: $breakVal"
        $txtHistoryTasks.Text = $entry.task_update
        $txtHistoryPreview.Text = $entry.preview_text
        
        $listHistoryTimeline.Items.Clear()
        foreach ($item in $entry.timeline) {
            $listHistoryTimeline.Items.Add($item)
        }
    }
})

$btnExportHistory.Add_Click({
    $idx = $listHistoryDays.SelectedIndex
    if ($idx -lt 0 -or $null -eq $global:LoadedHistory) {
        [System.Windows.MessageBox]::Show("Please select a day from the list to export.", "No Selection", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    
    $entry = $global:LoadedHistory[$idx]
    $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $saveFileDialog.FileName = "Office_Status_$($entry.date).txt"
    
    if ($saveFileDialog.ShowDialog() -eq $true) {
        $timelineStr = [string]::Join("`r`n", $entry.timeline)
        $breakVal = "00:00:00"
        if ($null -ne $entry.break_duration) {
            $breakVal = $entry.break_duration
        }
        $content = @"
Office Status Log - $($entry.display_date)
=========================================
Total Worked Hours: $($entry.worked_hours)
Total Break Duration: $breakVal

Task Update:
------------
$($entry.task_update)

Generated Preview:
------------------
$($entry.preview_text)

Timeline:
---------
$timelineStr
"@
        try {
            Set-Content -Path $saveFileDialog.FileName -Value $content -Force
            Show-Toast "✓ Exported Day Summary File" "#10AC84" "#155724"
        } catch {
            [System.Windows.MessageBox]::Show("Failed to write file: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }
})

# 8. Setup Window Event Listeners & Keys

# Navigation tabs click triggers
$btnNavDashboard.Add_Click({ Show-Tab "Dashboard" })
$btnNavTaskUpdate.Add_Click({ Show-Tab "TaskUpdate" })
$btnNavHistory.Add_Click({ Show-Tab "History" })
$btnNavAnalytics.Add_Click({ Show-Tab "Analytics" })
$btnNavSettings.Add_Click({ Show-Tab "Settings" })
if ($null -ne $btnNavLicense) { $btnNavLicense.Add_Click({ Show-Tab "License" }) }
if ($null -ne $btnNavAbout) { $btnNavAbout.Add_Click({ Show-Tab "About" }) }
if ($null -ne $borderLicenseBadge) { $borderLicenseBadge.Add_MouseDown({ Show-Tab "License" }) }

if ($null -ne $btnLicCopyHwid) {
    $btnLicCopyHwid.Add_Click({
        if ($null -ne $txtLicMachineId -and -not [string]::IsNullOrEmpty($txtLicMachineId.Text)) {
            Copy-ToClipboard $txtLicMachineId.Text
            Show-Toast "✓ Machine HWID Copied to Clipboard" "#10AC84" "#155724"
        }
    })
}

if ($null -ne $btnLicActivate) {
    $btnLicActivate.Add_Click({
        $key = $txtLicKey.Text.Trim()
        $email = $txtLicEmail.Text.Trim()

        if ([string]::IsNullOrEmpty($key) -or [string]::IsNullOrEmpty($email)) {
            $txtLicToast.Text = "Please enter both License Key and Email Address."
            $borderLicToast.Visibility = "Visible"
            return
        }

        $btnLicActivate.IsEnabled = $false
        $btnLicActivate.Content = "ACTIVATING..."
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        $res = Invoke-DeskFlowValidation -key $key -email $email
        $btnLicActivate.IsEnabled = $true
        $btnLicActivate.Content = "ACTIVATE PRO"

        if ($res.valid) {
            if (Test-DeskFlowSignature -key $key -machineId (Get-DeskFlowMachineId) -licenseType $res.license_type -serverSignature $res.signature) {
                $payload = [PSCustomObject]@{
                    key               = $key
                    email             = $email
                    plan              = if ($res.plan) { $res.plan } else { "Pro" }
                    license_type      = $res.license_type
                    signature         = $res.signature
                    last_online_check = (Get-Date).ToString("o")
                }
                Save-StealthLicensePayload $payload
                $global:IsLicenseValid = $true
                Update-DeskFlowLicenseBadge
                $borderLicToast.Visibility = "Collapsed"
                Show-Toast "⚡ DeskFlow Pro Activated Successfully!" "#10AC84" "#155724"
            } else {
                $txtLicToast.Text = "Invalid server security signature."
                $borderLicToast.Visibility = "Visible"
            }
        } elseif ($res.can_request_transfer -or $res.message -like "*different device*" -or $res.message -like "*Device limit reached*") {
            $txtLicToast.Text = $res.message
            $borderLicToast.Visibility = "Visible"
            $btnLicTransfer.Visibility = "Visible"
            $btnLicRefresh.Visibility = "Collapsed"
        } elseif ($res.transfer_pending -or $res.message -like "*pending admin approval*") {
            $txtLicToast.Text = "Device transfer request is pending Admin approval. Click Refresh Status after approval."
            $borderLicToast.Visibility = "Visible"
            $btnLicTransfer.Visibility = "Collapsed"
            $btnLicRefresh.Visibility = "Visible"
        } else {
            $txtLicToast.Text = $res.message
            $borderLicToast.Visibility = "Visible"
        }
    })
}

if ($null -ne $btnLicTransfer) {
    $btnLicTransfer.Add_Click({
        $key = $txtLicKey.Text.Trim()
        $email = $txtLicEmail.Text.Trim()
        $res = Invoke-DeskFlowValidation -key $key -email $email -requestTransfer $true
        if ($res.valid -or $res.transfer_pending) {
            $txtLicToast.Text = "Device transfer request submitted to Admin! Click Refresh Status after approval."
            $borderLicToast.Visibility = "Visible"
            $btnLicTransfer.Visibility = "Collapsed"
            $btnLicRefresh.Visibility = "Visible"
            Show-Toast "⚡ Transfer Request Submitted to Admin" "#8B5CF6" "#3B0764"
        } else {
            $txtLicToast.Text = $res.message
            $borderLicToast.Visibility = "Visible"
        }
    })
}

if ($null -ne $btnLicRefresh) {
    $btnLicRefresh.Add_Click({
        $key = $txtLicKey.Text.Trim()
        $email = $txtLicEmail.Text.Trim()
        $res = Invoke-DeskFlowValidation -key $key -email $email
        if ($res.valid) {
            if (Test-DeskFlowSignature -key $key -machineId (Get-DeskFlowMachineId) -licenseType $res.license_type -serverSignature $res.signature) {
                $payload = [PSCustomObject]@{
                    key               = $key
                    email             = $email
                    plan              = if ($res.plan) { $res.plan } else { "Pro" }
                    license_type      = $res.license_type
                    signature         = $res.signature
                    last_online_check = (Get-Date).ToString("o")
                }
                Save-StealthLicensePayload $payload
                $global:IsLicenseValid = $true
                Update-DeskFlowLicenseBadge
                $borderLicToast.Visibility = "Collapsed"
                Show-Toast "⚡ License Refresh Successful! Pro Active." "#10AC84" "#155724"
            } else {
                $txtLicToast.Text = "Invalid server security signature."
                $borderLicToast.Visibility = "Visible"
            }
        } elseif ($res.transfer_pending) {
            $txtLicToast.Text = "Transfer still pending Admin approval. Please check back shortly."
            $borderLicToast.Visibility = "Visible"
        } else {
            $txtLicToast.Text = $res.message
            $borderLicToast.Visibility = "Visible"
            if ($res.can_request_transfer -or $res.message -like "*different device*") {
                $btnLicTransfer.Visibility = "Visible"
                $btnLicRefresh.Visibility = "Collapsed"
                $txtLicToast.Text = "Transfer request was declined by Admin or key is registered to another device. You can request shift again."
            }
        }
    })
}

if ($null -ne $btnLicDeactivate) {
    $btnLicDeactivate.Add_Click({
        $confirm = Show-DeskFlowDialog -title "Deactivate License" -message "Are you sure you want to deactivate this license from your PC?`r`n`r`nYou can re-activate with the same key later." -confirmText "YES, DEACTIVATE" -cancelText "CANCEL" -icon "⚠️" -confirmColor "#EF4444"
        if ($confirm) {
            Clear-StealthLicensePayload
            $global:IsLicenseValid = $false
            Update-DeskFlowLicenseBadge
            if ($null -ne $txtLicToast) {
                $txtLicToast.Text = "License deactivated from this device."
                $borderLicToast.Visibility = [System.Windows.Visibility]::Visible
            }
            Show-Toast "⚠️ License Deactivated from PC" "#EF4444" "#450A0A"
        }
    })
}

# Table Body Color - Live preview on hex text change
$txtTableBodyColor.Add_TextChanged({
    $hex = $txtTableBodyColor.Text.Trim()
    if ($hex -match '^#[0-9a-fA-F]{3,6}$') {
        try {
            $brush = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString($hex)
            $bdrTableBodyColorPreview.Background = $brush
        } catch {}
    }
})

# Table Body Color - Pick Color button using Windows Forms ColorDialog
$btnPickTableBodyColor.Add_Click({
    $colorDialog = New-Object System.Windows.Forms.ColorDialog
    $colorDialog.FullOpen = $true
    $currentHex = $txtTableBodyColor.Text.Trim()
    if ($currentHex -match '^#[0-9a-fA-F]{6}$') {
        try {
            $r = [Convert]::ToInt32($currentHex.Substring(1,2), 16)
            $g = [Convert]::ToInt32($currentHex.Substring(3,2), 16)
            $b = [Convert]::ToInt32($currentHex.Substring(5,2), 16)
            $colorDialog.Color = [System.Drawing.Color]::FromArgb($r, $g, $b)
        } catch {}
    }
    if ($colorDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $c = $colorDialog.Color
        $hex = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
        $txtTableBodyColor.Text = $hex
        try {
            $bdrTableBodyColorPreview.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        } catch {}
        $global:Settings.table_body_color = $hex
        Save-Settings
    }
})

# Email Sets settings add set handler
$btnAddEmailSet.Add_Click({
    $name = $txtSetEmailSetName.Text.Trim()
    $emails = $txtSetEmailSetEmails.Text.Trim()
    
    if ($name -eq "" -or $emails -eq "") {
        Show-Toast "Please fill in all Email Set fields." "#FF4D4D" "#8B0000"
        return
    }
    
    if ($null -eq $global:Settings.email_sets) {
        if (-not (Get-Member -InputObject $global:Settings -Name "email_sets")) {
            $global:Settings | Add-Member -MemberType NoteProperty -Name "email_sets" -Value @() -ErrorAction SilentlyContinue
        } else {
            $global:Settings.email_sets = @()
        }
    }
    
    if ($global:Settings.email_sets | Where-Object { $_.name -eq $name }) {
        Show-Toast "Email Set name already exists." "#FF4D4D" "#8B0000"
        return
    }

    $isFirst = ($global:Settings.email_sets.Count -eq 0)
    $newSet = [PSCustomObject]@{ name = $name; emails = $emails; is_default = $isFirst }
    $global:Settings.email_sets += $newSet
    
    $txtSetEmailSetName.Text = ""
    $txtSetEmailSetEmails.Text = ""
    Redraw-EmailSets
    Save-Settings
})

# Hubstaff settings add account handler
$btnAddHubstaffAccount.Add_Click({
    $name = $txtSetHubstaffName.Text.Trim()
    $email = $txtSetHubstaffEmailList.Text.Trim()
    $pass = $txtSetHubstaffPassList.Password.Trim()
    
    if ($name -eq "" -or $email -eq "" -or $pass -eq "") {
        Show-Toast "Please fill in all Hubstaff fields." "#FF4D4D" "#8B0000"
        return
    }
    
    if ($null -eq $global:Settings.hubstaff_accounts) {
        if (-not (Get-Member -InputObject $global:Settings -Name "hubstaff_accounts")) {
            $global:Settings | Add-Member -MemberType NoteProperty -Name "hubstaff_accounts" -Value @() -ErrorAction SilentlyContinue
        } else {
            $global:Settings.hubstaff_accounts = @()
        }
    }
    
    # Check duplicate
    if ($global:Settings.hubstaff_accounts | Where-Object { $_.name -eq $name }) {
        Show-Toast "Account name already exists." "#FF4D4D" "#8B0000"
        return
    }

    $isFirst = ($global:Settings.hubstaff_accounts.Count -eq 0)
    $newAcc = [PSCustomObject]@{ name = $name; email = $email; password = $pass; is_default = $isFirst }
    $global:Settings.hubstaff_accounts += $newAcc
    
    $txtSetHubstaffName.Text = ""
    $txtSetHubstaffEmailList.Text = ""
    $txtSetHubstaffPassList.Password = ""
    
    Redraw-HubstaffAccounts
    Save-Settings
    Show-Toast "Hubstaff account added!" "#10AC84" "#155724"
})

# Task Update Listeners
$btnTaskUpdateBrowseSS.Add_Click({
    $openFileDialog = New-Object Microsoft.Win32.OpenFileDialog
    $openFileDialog.Filter = "Image Files (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg|All Files (*.*)|*.*"
    $openFileDialog.Title = "Select Hubstaff Screenshot"
    if ($openFileDialog.ShowDialog() -eq $true) {
        $global:TaskUpdateScreenshotPath = $openFileDialog.FileName
        $txtTaskUpdateSSPath.Text = [System.IO.Path]::GetFileName($global:TaskUpdateScreenshotPath)
        $txtTaskUpdateSSPath.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $btnTaskUpdateRemoveSS.Visibility = 'Visible'
        
        if ($cmbTaskUpdateHubstaffAccount.SelectedIndex -eq 0 -and $cmbTaskUpdateHubstaffAccount.Items.Count -gt 1) {
            $hubstaffDefaultIndex = 1
            $hubstaffCurrentIndex = 1
            if ($null -ne $global:Settings.hubstaff_accounts) {
                foreach ($acc in $global:Settings.hubstaff_accounts) {
                    if ($acc.is_default) {
                        $hubstaffDefaultIndex = $hubstaffCurrentIndex
                        break
                    }
                    $hubstaffCurrentIndex++
                }
            }
            $cmbTaskUpdateHubstaffAccount.SelectedIndex = $hubstaffDefaultIndex
        }
    }
})

$btnTaskUpdateRemoveSS.Add_Click({
    $global:TaskUpdateScreenshotPath = $null
    $txtTaskUpdateSSPath.Text = "No screenshot attached"
    $txtTaskUpdateSSPath.Foreground = "#8F8F9D"
    $btnTaskUpdateRemoveSS.Visibility = 'Collapsed'
    
    # Selecting index 0 will trigger CmbTaskUpdateHubstaffAccount.Add_SelectionChanged
    # which replaces the template back to "No Hubstaff" version automatically.
    $cmbTaskUpdateHubstaffAccount.SelectedIndex = 0
})

$cmbTaskUpdateHubstaffAccount.Add_SelectionChanged({
    $selectedItem = $cmbTaskUpdateHubstaffAccount.SelectedItem
    if ($null -eq $selectedItem) { return }
    $accountName = $selectedItem.Content.ToString()
    
    $txtTaskUpdateEmailContent.Text = Get-TaskUpdateTemplateText -accountName $accountName
})

$btnTaskUpdateSend.Add_Click({
    $gmailAddress = $global:Settings.gmail_address
    $gmailAppPassword = $global:Settings.gmail_app_password
    
    $selectedEmailSetName = $cmbTaskUpdateEmailSet.Text
    $selectedSet = $global:Settings.email_sets | Where-Object { $_.name -eq $selectedEmailSetName }
    $recipientEmails = if ($null -ne $selectedSet) { $selectedSet.emails } else { "" }
    
    if ([string]::IsNullOrWhiteSpace($gmailAddress) -or [string]::IsNullOrWhiteSpace($gmailAppPassword) -or [string]::IsNullOrWhiteSpace($recipientEmails)) {
        Show-Toast "$warningEmoji Please configure Gmail and Email Sets first!" "#FF4D4D" "#8B0000"
        return
    }
    
    $emailText = $txtTaskUpdateEmailContent.Text
    if (-not $emailText.Contains("{{TASK_TABLE}}")) {
        Show-Toast "$warningEmoji Email must contain {{TASK_TABLE}}!" "#FF4D4D" "#8B0000"
        return
    }
    
    $btnTaskUpdateSend.IsEnabled = $false
    $btnTaskUpdateSend.Content = "$waitEmoji SENDING..."
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    
    # Read subject from the editable TextBox (user may have modified it)
    $subject = $txtTaskUpdateSubject.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($subject)) {
        $userName = if ([string]::IsNullOrWhiteSpace($global:Settings.user_name)) { "User" } else { $global:Settings.user_name.Trim() }
        $subject = "$userName - Today's Task - ($(Get-Date -Format 'dd-MM-yyyy'))"
    }
    $success = Send-TaskUpdateEmail -gmailAddress $gmailAddress -gmailAppPassword $gmailAppPassword -recipientEmails $recipientEmails -subject $subject -bodyText $emailText -screenshotPath $global:TaskUpdateScreenshotPath
    
    $btnTaskUpdateSend.IsEnabled = $true
    $btnTaskUpdateSend.Content = "$emailEmoji SEND EMAIL UPDATE"
    
    if ($success) {
        Show-Toast "$checkEmoji Email sent successfully!" "#10AC84" "#155724"
    } else {
        Show-Toast "$crossEmoji Failed to send email." "#FF4D4D" "#8B0000"
    }
})

# Start / Stop office session
$btnStartOffice.Add_Click({
    if ($global:OfficeStarted) {
        Trigger-LeavingOffice
    } else {
        Start-Office
        Trigger-GoodMorning
    }
})

# Break managers triggers
$btnLunch.Add_Click({ Toggle-Break "Lunch" })
$btnPrayer.Add_Click({ Toggle-Break "Prayer" })
$btnCombo.Add_Click({ Toggle-Break "Combo" })
$btnAddCustomBreak.Add_Click({
    $newBreak = Show-AddCustomBreakDialog
    if ($null -ne $newBreak) {
        if ($null -eq $global:Settings.custom_breaks) {
            $global:Settings.custom_breaks = @()
        }
        $global:Settings.custom_breaks += $newBreak
        Save-Settings
        Load-CustomBreaks
    }
})

# Idle Prompt actions
$btnIdleIgnore.Add_Click({
    $gridIdlePrompt.Visibility = [System.Windows.Visibility]::Collapsed
})
$btnIdleLunch.Add_Click({ Log-IdleBreak "Lunch" })
$btnIdlePrayer.Add_Click({ Log-IdleBreak "Prayer" })
$btnIdleCombo.Add_Click({ Log-IdleBreak "Combo" })

# Task Update triggers
$btnGenerateTaskUpdate.Add_Click({ Trigger-TaskUpdate })
$btnCopyPreview.Add_Click({ Copy-PreviewToClipboard })
$btnClearPreview.Add_Click({ Clear-PreviewConfirm })

# Copy line item event handler
$listPreview.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    param($sender, $e)
    $button = $e.OriginalSource
    if ($button.Tag -eq "CopyBtn") {
        $textToCopy = $button.DataContext
        if ($null -ne $textToCopy -and ($textToCopy -is [string])) {
            Copy-ToClipboard $textToCopy
            Show-Toast "✓ Copied Line to Clipboard" "#10AC84" "#155724"
        }
    }
})

# Always on top pin toggle in titlebar
$btnAlwaysOnTop.Add_Click({
    $global:Settings.always_on_top = -not $global:Settings.always_on_top
    $window.Topmost = $global:Settings.always_on_top
    
    if ($global:Settings.always_on_top) {
        $btnAlwaysOnTop.Foreground = $purpleBrush
        Show-Toast "📌 Window Set to Always on Top" "#10AC84" "#155724"
    } else {
        $btnAlwaysOnTop.Foreground = $greyBrush
        Show-Toast "📌 Always on Top Disabled" "#FF4D4D" "#8B0000"
    }
    
    $chkSetAlwaysOnTop.IsChecked = $global:Settings.always_on_top
    
    # Save Settings
    $settingsFile = Join-Path $global:DataDir "settings.json"
    $json = ConvertTo-Json $global:Settings -Depth 10
    Set-Content -Path $settingsFile -Value $json -Force
})

# Keyboard Shortcuts Listeners
$window.Add_KeyDown({
    param($sender, $e)
    
    $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
    $shift = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift
    
    # Check if user is typing inside text input textboxes to avoid hijacking characters
    $focused = [System.Windows.Input.FocusManager]::GetFocusedElement($window)
    $focusedName = if ($null -ne $focused) { $focused.GetType().Name } else { "" }
    $isEditing = $focusedName -like "*TextBox*" -or $focusedName -eq "TextBoxView"
    
    if ($ctrl) {
        if ($isEditing) {
            # Bypass custom shortcuts if editing text box, allowing standard Ctrl+C/V/Z
            return
        }
        
        switch ($e.Key) {
            "G" {
                Trigger-GoodMorning
                $e.Handled = $true
            }
            "L" {
                Toggle-Break "Lunch"
                $e.Handled = $true
            }
            "P" {
                if ($shift) {
                    Toggle-Break "Combo"
                } else {
                    Toggle-Break "Prayer"
                }
                $e.Handled = $true
            }
            "E" {
                if ($shift) {
                    Trigger-LeavingOffice
                } else {
                    Trigger-TaskUpdate
                }
                $e.Handled = $true
            }
            "C" {
                Copy-PreviewToClipboard
                $e.Handled = $true
            }
            "K" {
                Clear-PreviewConfirm
                $e.Handled = $true
            }
        }
    }
})

# Window loaded configurations
$window.Add_Loaded({
    Load-Settings

    # Background silent license validation check (Thread-safe Dispatcher)
    if ($global:IsLicenseValid) {
        $lic = Get-StealthLicensePayload
        if ($null -ne $lic -and -not [string]::IsNullOrEmpty($lic.key)) {
            $window.Dispatcher.BeginInvoke([Action]{
                try {
                    $res = Invoke-DeskFlowValidation -key $lic.key -email $lic.email
                    if ($res.valid -and (Test-DeskFlowSignature -key $lic.key -machineId (Get-DeskFlowMachineId) -licenseType $res.license_type -serverSignature $res.signature)) {
                        $lic.last_online_check = (Get-Date).ToString("o")
                        $lic.signature = $res.signature
                        if ($res.plan) { $lic.plan = $res.plan }
                        Save-StealthLicensePayload $lic
                        $global:IsLicenseValid = $true
                        Update-DeskFlowLicenseBadge
                    } elseif ($res.message -like "*revoked*" -or $res.message -like "*expired*" -or $res.message -like "*different device*") {
                        $reasonToMark = if ($res.message -like "*expired*") { "LicenseExpired" } else { "LicenseRevoked" }
                        Clear-StealthLicensePayload
                        Mark-StealthLicenseExpired -reason $reasonToMark
                        $global:IsLicenseValid = $false
                        Update-DeskFlowLicenseBadge
                        Show-DeskFlowDialog -Title "License Revoked" -Message "Your DeskFlow license key was revoked or disabled by Admin." -Icon "⛔" -BadgeColor "#3A1B1B" -BadgeBorder "#EF4444" -BadgeFg "#FF8888" -ButtonType "OK" -AccentColor "#EF4444"
                        Show-Tab "License"
                    }
                } catch {}
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    }
    
    # 6-Hour Periodic License Validation Timer (Matching ClipboardPro & OrbitSwipe)
    if ($null -eq $global:PeriodicLicenseTimer) {
        $global:PeriodicLicenseTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:PeriodicLicenseTimer.Interval = [TimeSpan]::FromHours(6)
        $global:PeriodicLicenseTimer.Add_Tick({
            if ($global:IsLicenseValid) {
                $lic = Get-StealthLicensePayload
                if ($null -ne $lic -and -not [string]::IsNullOrEmpty($lic.key)) {
                    $window.Dispatcher.BeginInvoke([Action]{
                        try {
                            $res = Invoke-DeskFlowValidation -key $lic.key -email $lic.email
                            if ($res.valid -and (Test-DeskFlowSignature -key $lic.key -machineId (Get-DeskFlowMachineId) -licenseType $res.license_type -serverSignature $res.signature)) {
                                $lic.last_online_check = (Get-Date).ToString("o")
                                $lic.signature = $res.signature
                                if ($res.plan) { $lic.plan = $res.plan }
                                Save-StealthLicensePayload $lic
                                $global:IsLicenseValid = $true
                                Update-DeskFlowLicenseBadge
                            } elseif ($res.message -like "*revoked*" -or $res.message -like "*expired*" -or $res.message -like "*different device*") {
                                $reasonToMark = if ($res.message -like "*expired*") { "LicenseExpired" } else { "LicenseRevoked" }
                                Clear-StealthLicensePayload
                                Mark-StealthLicenseExpired -reason $reasonToMark
                                $global:IsLicenseValid = $false
                                Update-DeskFlowLicenseBadge
                                Show-DeskFlowDialog -Title "License Revoked" -Message "Your DeskFlow license key was revoked or disabled by Admin." -Icon "⛔" -BadgeColor "#3A1B1B" -BadgeBorder "#EF4444" -BadgeFg "#FF8888" -ButtonType "OK" -AccentColor "#EF4444"
                                Show-Tab "License"
                            }
                        } catch {}
                    }, [System.Windows.Threading.DispatcherPriority]::Background)
                }
            }
        })
        $global:PeriodicLicenseTimer.Start()
    }
    
    # Topmost check
    $window.Topmost = $global:Settings.always_on_top
    if ($global:Settings.always_on_top) {
        $btnAlwaysOnTop.Foreground = $purpleBrush
    } else {
        $btnAlwaysOnTop.Foreground = $greyBrush
    }
    
    # Sync Startup Registry Key path
    $registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $keyName = "DeskFlow"
    $targetExe = Join-Path $scriptDir "DeskFlow.exe"
    if (Test-Path $targetExe) {
        $launchPath = $targetExe
    } elseif (Test-Path (Join-Path $scriptDir "Launch.bat")) {
        $launchPath = Join-Path $scriptDir "Launch.bat"
    } else {
        $launchPath = (Get-Process -Id $PID).Path
    }

    $hklmPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    if ($global:Settings.start_with_windows) {
        Set-ItemProperty -Path $registryPath -Name $keyName -Value "`"$launchPath`" --autostart" -ErrorAction SilentlyContinue
    } else {
        Remove-ItemProperty -Path $registryPath -Name $keyName -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $registryPath -Name "OfficeStatusGenerator" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $hklmPath -Name $keyName -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $hklmPath -Name "OfficeStatusGenerator" -ErrorAction SilentlyContinue
    }
    
    # Initialize System Tray Icon
    try {
        $global:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $global:NotifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $PID).Path)
        $global:NotifyIcon.Text = "Office Status Generator"
        $global:NotifyIcon.Visible = $true
        
        $contextMenu = New-Object System.Windows.Forms.ContextMenu
        $menuShow = New-Object System.Windows.Forms.MenuItem("Show App", {
            $window.Dispatcher.Invoke({
                $window.Show()
                $window.WindowState = [System.Windows.WindowState]::Normal
                $window.Activate()
            })
        })
        $menuToggleOffice = New-Object System.Windows.Forms.MenuItem("Toggle Office Session", {
            $window.Dispatcher.Invoke({
                if ($global:OfficeStarted) {
                    Stop-Office
                } else {
                    Start-Office
                }
            })
        })
        $menuGoodMorning = New-Object System.Windows.Forms.MenuItem("Quick Action: Good Morning", {
            $window.Dispatcher.Invoke({
                Trigger-GoodMorning
            })
        })
        $menuLunch = New-Object System.Windows.Forms.MenuItem("Quick Action: Toggle Lunch", {
            $window.Dispatcher.Invoke({
                Toggle-Break "Lunch"
            })
        })
        $menuPrayer = New-Object System.Windows.Forms.MenuItem("Quick Action: Toggle Prayer", {
            $window.Dispatcher.Invoke({
                Toggle-Break "Prayer"
            })
        })
        $menuLeave = New-Object System.Windows.Forms.MenuItem("Quick Action: Leaving from Office", {
            $window.Dispatcher.Invoke({
                Trigger-LeavingOffice
            })
        })
        $menuExit = New-Object System.Windows.Forms.MenuItem("Exit", {
            $window.Dispatcher.Invoke({
                $global:IsExiting = $true
                $window.Close()
            })
        })
        
        [void]$contextMenu.MenuItems.Add($menuShow)
        [void]$contextMenu.MenuItems.Add($menuToggleOffice)
        [void]$contextMenu.MenuItems.Add("-")
        [void]$contextMenu.MenuItems.Add($menuGoodMorning)
        [void]$contextMenu.MenuItems.Add($menuLunch)
        [void]$contextMenu.MenuItems.Add($menuPrayer)
        [void]$contextMenu.MenuItems.Add($menuLeave)
        [void]$contextMenu.MenuItems.Add("-")
        [void]$contextMenu.MenuItems.Add($menuExit)
        
        $global:NotifyIcon.ContextMenu = $contextMenu
        
        $global:NotifyIcon.Add_DoubleClick({
            $window.Dispatcher.Invoke({
                $window.Show()
                $window.WindowState = [System.Windows.WindowState]::Normal
                $window.Activate()
            })
        })
    } catch {
        # Silent fallback if tray loading fails for any reason
    }
    
    Show-Tab "Dashboard"
    Load-SettingsView
    Load-QuickTasks
    Load-CustomBreaks
    Update-CalendarView
    
    # One-time auto-scroll: bring today's calendar date into view on startup
    $global:StartupScrollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:StartupScrollTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $global:StartupScrollTimer.Add_Tick({
        $global:StartupScrollTimer.Stop()
        $global:StartupScrollTimer = $null
        $sv = $global:CalendarScrollViewer
        if ($null -ne $sv -and $sv.ScrollableWidth -gt 0) {
            $cellWidth = 51
            $offset = ((Get-Date).Day - 1) * $cellWidth
            $sv.ScrollToHorizontalOffset($offset)
        }
    })
    $global:StartupScrollTimer.Start()
    
    # Hide window to System Tray on Windows autostart
    $rawArgs = [Environment]::GetCommandLineArgs()
    if ($rawArgs -contains "--autostart" -or $args -contains "--autostart") {
        $window.Hide()
    }

    # Silent startup update check (runs after 5 seconds via DispatcherTimer)
    Check-ForUpdates -IsManual $false
})

# Note: Window Minimize (_) minimizes to Taskbar normally like standard apps.
# Close (X) respects $global:Settings.minimize_to_tray setting.

# Prevent resource leak on window close, support close-to-tray
$window.Add_Closing({
    Save-Settings
    $e = $args[1]
    if (-not $global:IsExiting -and $global:Settings.minimize_to_tray) {
        $e.Cancel = $true
        $window.Hide()
    } else {
        if ($null -ne $global:NotifyIcon) {
            $global:NotifyIcon.Visible = $false
            $global:NotifyIcon.Dispose()
        }
        $global:ClockTimer.Stop()
        if ($null -ne $global:ToastTimer) {
            $global:ToastTimer.Stop()
        }
        if ($null -ne $global:IdleTimer) {
            $global:IdleTimer.Stop()
        }
        # Explicitly shut down the app message loop since ShutdownMode is OnExplicitShutdown
        try { [System.Windows.Application]::Current.Shutdown() } catch {}
    }
})

# 9. Clock Engine / Dispatcher Timer
$global:ClockTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:ClockTimer.Interval = [TimeSpan]::FromSeconds(1)
$global:ClockTimer.Add_Tick({
    $now = Get-Date
    $txtClock.Text = $now.ToString("h:mm:ss tt")
    $txtDate.Text = $now.ToString("dddd, MMMM d, yyyy")
    
    # Update Active Break Timer Elapsed Time
    if ($global:ActiveBreakType -ne $null) {
        $elapsed = $now - $global:BreakStartTime
        $min = [Math]::Floor($elapsed.TotalMinutes)
        $sec = $elapsed.Seconds
        $elapsedStr = "$($min)m $($sec)s"
        
        $limitMinutes = 0
        $timerText = $null
        
        if ($global:ActiveBreakType -eq "Lunch") {
            $btnLunch.Content = "I'm Back ($elapsedStr)"
            $limitMinutes = $global:Settings.lunch_limit_minutes
            $timerText = $txtLunchTimer
        }
        elseif ($global:ActiveBreakType -eq "Prayer") {
            $btnPrayer.Content = "I'm Back ($elapsedStr)"
            $limitMinutes = $global:Settings.prayer_limit_minutes
            $timerText = $txtPrayerTimer
        }
        elseif ($global:ActiveBreakType -eq "Combo") {
            $btnCombo.Content = "I'm Back ($elapsedStr)"
            $limitMinutes = $global:Settings.lunch_limit_minutes + $global:Settings.prayer_limit_minutes
            $timerText = $txtComboTimer
        }
        elseif ($global:ActiveBreakType.StartsWith("Custom_")) {
            $cb = $global:Settings.custom_breaks | Where-Object { $_.id -eq $global:ActiveBreakType }
            if ($null -ne $cb) {
                $limitMinutes = $cb.limit_minutes
                $btn = $global:CustomBreakButtons[$cb.id]
                if ($null -ne $btn) {
                    $btn.Content = "I'm Back ($elapsedStr)"
                    if ($global:Settings.break_alerts_enabled -and $limitMinutes -gt 0 -and $elapsed.TotalMinutes -ge $limitMinutes) {
                        if ($sec % 2 -eq 0) {
                            $btn.Background = [System.Windows.Media.Brushes]::Red
                        } else {
                            $btn.Background = $brushConv.ConvertFromString("#341F97")
                        }
                    } else {
                        $btn.Background = $redBrush
                    }
                }
            }
        }
        
        # Check alerts
        if ($global:Settings.break_alerts_enabled -and $limitMinutes -gt 0 -and $elapsed.TotalMinutes -ge $limitMinutes) {
            # Pulse the color to Red and White
            if ($null -ne $timerText) {
                if ($sec % 2 -eq 0) {
                    $timerText.Foreground = [System.Windows.Media.Brushes]::Red
                } else {
                    $timerText.Foreground = [System.Windows.Media.Brushes]::White
                }
            }
            # Beep warning every 15 seconds
            if ($sec % 15 -eq 0) {
                try {
                    [System.Media.SystemSounds]::Beep.Play()
                } catch {}
            }
        } else {
            # Reset color to standard green
            if ($null -ne $timerText) {
                $timerText.Foreground = $brushConv.ConvertFromString("#10AC84")
            }
        }
    }
    
    # Update Worked & Break Hours Timer
    if ($global:OfficeStarted) {
        # Increment Active Task Row Timer
        foreach ($task in $global:TaskList) {
            if ($task.IsActive) {
                $task.TimeSpan = $task.TimeSpan.Add([TimeSpan]::FromSeconds(1))
                $formatted = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($task.TimeSpan.TotalHours), $task.TimeSpan.Minutes, $task.TimeSpan.Seconds)
                $task.Duration = $formatted
                if ($null -ne $task.TxtDuration) {
                    try { $task.TxtDuration.Text = $formatted } catch {}
                }
            }
        }

        $totalElapsedSeconds = ($now - $global:OfficeStartTime).TotalSeconds
        $workedSeconds = $totalElapsedSeconds - $global:TotalBreakDurationSeconds
        $totalBreakSeconds = $global:TotalBreakDurationSeconds
        
        # If break is active, subtract current break elapsed duration and accumulate break seconds
        if ($global:ActiveBreakType -ne $null) {
            $currentBreakSeconds = ($now - $global:BreakStartTime).TotalSeconds
            $workedSeconds -= $currentBreakSeconds
            $totalBreakSeconds += $currentBreakSeconds
        }
        
        if ($workedSeconds -lt 0) { $workedSeconds = 0 }
        
        $tsWorked = [TimeSpan]::FromSeconds($workedSeconds)
        $txtWorkedTime.Text = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($tsWorked.TotalHours), $tsWorked.Minutes, $tsWorked.Seconds)
        
        $tsBreak = [TimeSpan]::FromSeconds($totalBreakSeconds)
        $txtTotalBreak.Text = [string]::Format("{0:00}:{1:00}:{2:00}", [Math]::Floor($tsBreak.TotalHours), $tsBreak.Minutes, $tsBreak.Seconds)
        
        # Target workday check
        if ($global:Settings.break_alerts_enabled -and -not $global:WorkDayTargetAchieved) {
            $targetSeconds = $global:Settings.workday_target_hours * 3600
            if ($workedSeconds -ge $targetSeconds) {
                $global:WorkDayTargetAchieved = $true
                try {
                    [System.Media.SystemSounds]::Asterisk.Play()
                } catch {}
                Show-Toast "🎉 Target Workday Achieved ($($global:Settings.workday_target_hours)h)!" "#10AC84" "#155724"
            }
        }
        
        # Inactivity/Idle Tracking
        if ($global:Settings.idle_tracker_enabled -and $global:ActiveBreakType -eq $null -and $gridIdlePrompt.Visibility -ne [System.Windows.Visibility]::Visible) {
            $idleMs = [Win32Idle]::GetIdleTime()
            $idleSeconds = $idleMs / 1000
            $timeoutSeconds = $global:Settings.idle_timeout_minutes * 60
            
            if ($idleSeconds -ge $timeoutSeconds) {
                if (-not $global:WasIdle) {
                    $global:WasIdle = $true
                    $global:IdleStartTime = (Get-Date).AddSeconds(-$idleSeconds)
                }
            } else {
                if ($global:WasIdle) {
                    # User returned from idle! Show overlay prompt.
                    $awaySpan = (Get-Date) - $global:IdleStartTime
                    $awayMin = [Math]::Round($awaySpan.TotalMinutes)
                    if ($awayMin -lt 1) { $awayMin = 1 }
                    
                    $txtIdleMessage.Text = "You were away for $awayMin minutes."
                    $global:AwayDurationMinutes = $awayMin
                    $global:AwayStartTime = $global:IdleStartTime
                    
                    $gridIdlePrompt.Visibility = [System.Windows.Visibility]::Visible
                    
                    $global:WasIdle = $false
                    $global:IdleStartTime = $null
                    
                    # Bring window to foreground to prompt user
                    try {
                        $window.Show()
                        $window.WindowState = [System.Windows.WindowState]::Normal
                        $window.Activate()
                    } catch {}
                }
            }
        }
    }
})
$global:ClockTimer.Start()

function Show-LicenseGateDialog {
    param([string]$reason = "TrialExpired")

    $gateXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DeskFlow Pro Activation" Height="540" Width="500"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True">
    <Border Background="#121218" BorderBrush="#2D2D3F" BorderThickness="1" CornerRadius="16">
        <Grid Margin="24">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header Bar -->
            <Grid Grid.Row="0" Margin="0,0,0,16">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Image Source="$logoUri" Width="36" Height="36" Margin="0,0,12,0" RenderOptions.BitmapScalingMode="HighQuality" Stretch="Uniform" VerticalAlignment="Center"/>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="DeskFlow Pro" FontSize="18" FontWeight="Bold" Foreground="#FFFFFF"/>
                        <TextBlock Text="Smart Office Activity Manager" FontSize="11" Foreground="#8F8F9D"/>
                    </StackPanel>
                </StackPanel>
                <Button Name="btnGateClose" Content="✕" Width="28" Height="28" HorizontalAlignment="Right" VerticalAlignment="Top"
                        Background="Transparent" Foreground="#8F8F9D" BorderThickness="0" FontSize="14" Cursor="Hand"/>
            </Grid>

            <!-- Banner -->
            <Border Grid.Row="1" Background="#1E1E2A" BorderBrush="#2D2D3F" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,0,0,20">
                <StackPanel>
                    <TextBlock Name="txtBannerTitle" Text="🔒 30-Day Free Trial Expired" FontSize="15" FontWeight="Bold" Foreground="#FF4D4D" Margin="0,0,0,4"/>
                    <TextBlock Name="txtBannerDesc" Text="Your 30-day free trial of DeskFlow Smart Office Activity Manager has ended. Please enter your license key to unlock full access."
                               FontSize="12" Foreground="#C5C5D3" TextWrapping="Wrap" LineHeight="18"/>
                </StackPanel>
            </Border>

            <!-- Input Form -->
            <StackPanel Grid.Row="2" VerticalAlignment="Center">
                <TextBlock Text="LICENSE KEY" FontSize="11" FontWeight="SemiBold" Foreground="#8F8F9D" Margin="0,0,0,6"/>
                <TextBox Name="txtGateKey" Height="40" Background="#1A1A24" Foreground="#FFFFFF" BorderBrush="#2D2D3F" BorderThickness="1" 
                         Padding="12,8" FontSize="13" FontFamily="Consolas, Monospace" Margin="0,0,0,16" VerticalContentAlignment="Center"/>

                <TextBlock Text="REGISTERED EMAIL ADDRESS" FontSize="11" FontWeight="SemiBold" Foreground="#8F8F9D" Margin="0,0,0,6"/>
                <TextBox Name="txtGateEmail" Height="40" Background="#1A1A24" Foreground="#FFFFFF" BorderBrush="#2D2D3F" BorderThickness="1" 
                         Padding="12,8" FontSize="13" Margin="0,0,0,16" VerticalContentAlignment="Center"/>

                <Border Name="borderGateToast" Background="#261A1A" BorderBrush="#FF4D4D" BorderThickness="1" CornerRadius="8" Padding="10" Visibility="Collapsed" Margin="0,0,0,16">
                    <TextBlock Name="txtGateToast" Text="Invalid license key." FontSize="12" Foreground="#FF8080" TextWrapping="Wrap" HorizontalAlignment="Center"/>
                </Border>
            </StackPanel>

            <!-- Action Buttons -->
            <Grid Grid.Row="3">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal" Grid.Column="0">
                    <Button Name="btnGateActivate" Content="ACTIVATE PRO" Height="40" Padding="20,0" Background="#10AC84" Foreground="#FFFFFF" 
                            FontWeight="Bold" BorderThickness="0" Cursor="Hand" Margin="0,0,10,0"/>
                    <Button Name="btnGateTransfer" Content="⚡ REQUEST SHIFT" Height="40" Padding="14,0" Background="#8B5CF6" Foreground="#FFFFFF" 
                            FontWeight="Bold" BorderThickness="0" Cursor="Hand" Visibility="Collapsed" Margin="0,0,10,0"/>
                    <Button Name="btnGateRefresh" Content="🔄 REFRESH STATUS" Height="40" Padding="14,0" Background="#10AC84" Foreground="#FFFFFF" 
                            FontWeight="Bold" BorderThickness="0" Cursor="Hand" Visibility="Collapsed"/>
                </StackPanel>

                <Button Name="btnGateExit" Content="EXIT" Grid.Column="1" Height="40" Padding="16,0" Background="#262636" Foreground="#8F8F9D" 
                        FontWeight="SemiBold" BorderThickness="0" Cursor="Hand"/>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($gateXaml))
    $winGate = [System.Windows.Markup.XamlReader]::Load($reader)

    $txtGateKey     = $winGate.FindName("txtGateKey")
    $txtGateEmail   = $winGate.FindName("txtGateEmail")
    $txtBannerTitle = $winGate.FindName("txtBannerTitle")
    $txtBannerDesc  = $winGate.FindName("txtBannerDesc")
    $borderGateToast= $winGate.FindName("borderGateToast")
    $txtGateToast   = $winGate.FindName("txtGateToast")
    $btnGateActivate= $winGate.FindName("btnGateActivate")
    $btnGateTransfer= $winGate.FindName("btnGateTransfer")
    $btnGateRefresh = $winGate.FindName("btnGateRefresh")
    $btnGateClose   = $winGate.FindName("btnGateClose")
    $btnGateExit    = $winGate.FindName("btnGateExit")

    if ($reason -eq "LicenseExpired") {
        $txtBannerTitle.Text = "⌛ Annual License Expired"
        $txtBannerTitle.Foreground = "#F59E0B"
        $txtBannerDesc.Text = "Your 1-Year DeskFlow Pro subscription license has expired. Please renew your subscription or enter a new license key to continue using DeskFlow."
    } elseif ($reason -eq "LicenseRevoked") {
        $txtBannerTitle.Text = "⛔ License Revoked or Disabled"
        $txtBannerTitle.Foreground = "#EF4444"
        $txtBannerDesc.Text = "Your DeskFlow Pro license key was revoked or deactivated by Admin. Please enter a valid key to reactivate DeskFlow."
    } elseif ($reason -eq "OfflineExpired") {
        $txtBannerTitle.Text = "⚡ Offline Grace Period Expired"
        $txtBannerTitle.Foreground = "#F59E0B"
        $txtBannerDesc.Text = "Your 7-day offline grace period has expired. Please connect to the internet to verify your DeskFlow license."
    }

    $winGate.Add_MouseLeftButtonDown({ $winGate.DragMove() })
    $btnGateClose.Add_Click({ $winGate.DialogResult = $false; $winGate.Close() })
    $btnGateExit.Add_Click({ $winGate.DialogResult = $false; $winGate.Close() })

    $lic = Get-StealthLicensePayload
    if ($null -ne $lic) {
        if (-not [string]::IsNullOrEmpty($lic.key)) { $txtGateKey.Text = $lic.key }
        if (-not [string]::IsNullOrEmpty($lic.email)) { $txtGateEmail.Text = $lic.email }
    }

    $btnGateActivate.Add_Click({
        $key = $txtGateKey.Text.Trim()
        $email = $txtGateEmail.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($key)) {
            $txtGateToast.Text = "Please enter your license key."
            $borderGateToast.Visibility = "Visible"
            return
        }

        $btnGateActivate.IsEnabled = $false
        $btnGateActivate.Content = "ACTIVATING..."
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        $res = Invoke-DeskFlowValidation -key $key -email $email
        $btnGateActivate.IsEnabled = $true
        $btnGateActivate.Content = "ACTIVATE PRO"

        if ($res.valid) {
            if (Test-DeskFlowSignature -key $key -machineId (Get-DeskFlowMachineId) -licenseType $res.license_type -serverSignature $res.signature) {
                $payload = [PSCustomObject]@{
                    key               = $key
                    email             = $email
                    plan              = if ($res.plan) { $res.plan } else { "Pro" }
                    license_type      = $res.license_type
                    signature         = $res.signature
                    last_online_check = (Get-Date).ToString("o")
                }
                Save-StealthLicensePayload $payload
                $global:IsLicenseValid = $true
                $winGate.DialogResult = $true
                $winGate.Close()
            } else {
                $txtGateToast.Text = "Security Signature Mismatch. Please try again."
                $borderGateToast.Visibility = "Visible"
            }
        } else {
            $txtGateToast.Text = $res.message
            $borderGateToast.Visibility = "Visible"

            if ($res.can_request_transfer -or $res.message -like "*different device*") {
                $btnGateTransfer.Visibility = "Visible"
                $btnGateRefresh.Visibility = "Collapsed"
            }
            if ($res.transfer_pending) {
                $btnGateRefresh.Visibility = "Visible"
                $btnGateTransfer.Visibility = "Collapsed"
            }
        }
    })

    $btnGateTransfer.Add_Click({
        $key = $txtGateKey.Text.Trim()
        $email = $txtGateEmail.Text.Trim()

        $btnGateTransfer.IsEnabled = $false
        $btnGateTransfer.Content = "SENDING..."
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        $res = Invoke-DeskFlowValidation -key $key -email $email -requestTransfer $true
        $btnGateTransfer.IsEnabled = $true
        $btnGateTransfer.Content = "⚡ REQUEST SHIFT"

        if ($res.valid -or $res.transfer_pending) {
            $txtGateToast.Text = "Transfer request submitted to Admin! Click Refresh Status after approval."
            $borderGateToast.Background = "#153322"
            $borderGateToast.BorderBrush = "#10AC84"
            $txtGateToast.Foreground = "#A3E635"
            $borderGateToast.Visibility = "Visible"
            $btnGateTransfer.Visibility = "Collapsed"
            $btnGateRefresh.Visibility = "Visible"
        } else {
            $txtGateToast.Text = $res.message
            $borderGateToast.Visibility = "Visible"
        }
    })

    $btnGateRefresh.Add_Click({
        $key = $txtGateKey.Text.Trim()
        $email = $txtGateEmail.Text.Trim()

        $btnGateRefresh.IsEnabled = $false
        $btnGateRefresh.Content = "CHECKING..."
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        $res = Invoke-DeskFlowValidation -key $key -email $email
        $btnGateRefresh.IsEnabled = $true
        $btnGateRefresh.Content = "🔄 REFRESH STATUS"

        if ($res.valid) {
            if (Test-DeskFlowSignature -key $key -machineId (Get-DeskFlowMachineId) -licenseType $res.license_type -serverSignature $res.signature) {
                $payload = [PSCustomObject]@{
                    key               = $key
                    email             = $email
                    plan              = if ($res.plan) { $res.plan } else { "Pro" }
                    license_type      = $res.license_type
                    signature         = $res.signature
                    last_online_check = (Get-Date).ToString("o")
                }
                Save-StealthLicensePayload $payload
                $global:IsLicenseValid = $true
                $winGate.DialogResult = $true
                $winGate.Close()
            }
        } else {
            $txtGateToast.Text = $res.message
            $borderGateToast.Visibility = "Visible"
            if ($res.can_request_transfer -or $res.message -like "*different device*") {
                $btnGateTransfer.Visibility = "Visible"
                $btnGateRefresh.Visibility = "Collapsed"
                $borderGateToast.Background = "#3A1B1B"
                $borderGateToast.BorderBrush = "#EF4444"
                $txtGateToast.Foreground = "#FF8888"
                $txtGateToast.Text = "Transfer request was declined by Admin or key is bound to another device. You can request shift again."
            }
        }
    })

    $dialogRes = $winGate.ShowDialog()
    return ($dialogRes -eq $true)
}

function Check-DeskFlowSecurityGate {
    $gateReason = "TrialExpired"
    
    # Check persistent revocation marker
    $expiredMarker = Get-StealthLicenseExpiredReason
    if (-not [string]::IsNullOrEmpty($expiredMarker)) {
        $gateReason = $expiredMarker
    }

    # 1. Check local license payload
    $lic = Get-StealthLicensePayload
    if ($null -ne $lic -and -not [string]::IsNullOrEmpty($lic.key)) {
        # Perform online validation check first to catch revocation/expiration immediately
        $res = Invoke-DeskFlowValidation -key $lic.key -email $lic.email
        if ($res.valid) {
            if (Test-DeskFlowSignature -key $lic.key -machineId (Get-DeskFlowMachineId) -licenseType $res.license_type -serverSignature $res.signature) {
                $lic.last_online_check = (Get-Date).ToString("o")
                $lic.signature = $res.signature
                if ($res.plan) { $lic.plan = $res.plan }
                Save-StealthLicensePayload $lic
                Clear-StealthLicenseExpiredMarker
                $global:IsLicenseValid = $true
                $global:LicensePlan = $res.plan
                return $true
            }
        } elseif ($res.message -like "*revoked*" -or $res.message -like "*expired*" -or $res.message -like "*different device*") {
            # Key revoked/expired on server -> immediately wipe local payload & write persistent revocation marker
            $reasonToMark = if ($res.message -like "*expired*") { "LicenseExpired" } else { "LicenseRevoked" }
            Clear-StealthLicensePayload
            Mark-StealthLicenseExpired -reason $reasonToMark
            $global:IsLicenseValid = $false
            $gateReason = $reasonToMark
        } else {
            # Network issue or offline -> fallback to offline grace period (up to 7 days)
            $lastCheck = [DateTime]::MinValue
            if ([DateTime]::TryParse($lic.last_online_check, [ref]$lastCheck)) {
                $daysOffline = (Get-Date) - $lastCheck
                if ($daysOffline.TotalDays -le 7) {
                    $global:IsLicenseValid = $true
                    $global:LicensePlan = if ($lic.plan) { $lic.plan } else { "Pro" }
                    return $true
                } else {
                    $gateReason = "OfflineExpired"
                }
            }
        }
    }

    # 2. Check 30-day Trial (only if key was NOT explicitly revoked or expired)
    if ($gateReason -ne "LicenseRevoked" -and $gateReason -ne "LicenseExpired") {
        $trialStart = Get-StealthTrialDate
        $daysUsed = ((Get-Date) - $trialStart).TotalDays
        
        # Clock rollback check
        if ((Get-Date) -lt $trialStart) {
            $daysUsed = $global:DeskFlowTrialDays + 1
        }

        if ($daysUsed -lt $global:DeskFlowTrialDays) {
            $global:IsTrialActive = $true
            $global:TrialDaysLeft = [Math]::Max(0, [Math]::Ceiling($global:DeskFlowTrialDays - $daysUsed))
            return $true
        }
    }

    # 3. Gate required
    return Show-LicenseGateDialog -reason $gateReason
}

# Run Gate Check before launching app window
$isAllowed = Check-DeskFlowSecurityGate
if (-not $isAllowed) {
    [System.Environment]::Exit(0)
}

Update-DeskFlowLicenseBadge
if ($null -ne $txtLicMachineId) { $txtLicMachineId.Text = Get-DeskFlowMachineId }

# 10. Run App dispatcher loop
$app = [System.Windows.Application]::Current
if ($null -eq $app) {
    $app = New-Object System.Windows.Application
}
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
[void]$app.Run($window)




