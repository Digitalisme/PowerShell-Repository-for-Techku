# ==============================================================================
# home.ps1 - Welcome Page & Interactive Portal for ps1.techku.id
# ==============================================================================

& {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # ANSI Colors configuration for a beautiful color gradient
    function Get-AnsiColor ($r, $g, $b) {
        return "$([char]27)[38;2;$r;$g;${b}m"
    }
    $Reset = "$([char]27)[0m"

    # Fetch System Info dynamically
    $osName = "Windows Operating System"
    try { 
        $osName = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption 
    } catch {
        try {
            $osName = (Get-WmiObject Win32_OperatingSystem -ErrorAction Stop).Caption
        } catch {}
    }
    
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $privilege = if ($isAdmin) { "Administrator (Elevated)" } else { "Standard User (Limited)" }

    $global:TechkuPortalActive = $true
    $selectedIndex = 0

    # Test for interactive raw console support
    $interactive = $true
    try {
        $null = $Host.UI.RawUI.KeyAvailable
    } catch {
        $interactive = $false
    }

    $exitPortal = $false
    while (-not $exitPortal) {
        $options = @(
            "Run RAM Cleaner (Optimisasi RAM)",
            "Exit"
        )

        $running = $true
        while ($running) {
            Clear-Host
            
            # 1. Header (WELCOME ASCII Art with Cyan-to-Magenta gradient)
            Write-Host ""
            Write-Host "$(Get-AnsiColor 0 240 255)   __      __   _                      $Reset"
            Write-Host "$(Get-AnsiColor 0 190 255)   \ \    / /__| |__ ___ ___ _ __  ___ $Reset"
            Write-Host "$(Get-AnsiColor 130 130 255)    \ \/\/ / -_) / _/ _ \ _ \ '  \/ -_)$Reset"
            Write-Host "$(Get-AnsiColor 240 70 255)     \_/\_/\___|_\__\___/___/_|_|_\___|$Reset"
            Write-Host "            [ P S 1 . T E C H K U . I D ]" -ForegroundColor Gray
            Write-Host ""

            # 2. System Information Box (Safe ASCII borders)
            Write-Host " +--------------------------------------------------------------------------+" -ForegroundColor Cyan
            Write-Host "   System    : $osName" -ForegroundColor White
            Write-Host "   User      : $currentUser" -ForegroundColor White
            Write-Host -NoNewline "   Privilege : " -ForegroundColor White
            if ($isAdmin) {
                Write-Host $privilege -ForegroundColor Green
            } else {
                Write-Host $privilege -ForegroundColor Yellow
            }
            Write-Host " +--------------------------------------------------------------------------+" -ForegroundColor Cyan
            Write-Host ""

            # 3. Interactive Arrow-Key Menu or Fallback Input Menu
            if ($interactive) {
                Write-Host " Select an option to execute:" -ForegroundColor Gray
                Write-Host ""
                for ($i = 0; $i -lt $options.Count; $i++) {
                    if ($i -eq $selectedIndex) {
                        # Highlighted choice
                        Write-Host "   > [ $($options[$i]) ]  " -ForegroundColor Black -BackgroundColor Cyan
                    } else {
                        # Inactive choice
                        Write-Host "     [ $($options[$i]) ]  " -ForegroundColor White
                    }
                }
                Write-Host ""
                Write-Host " [Up/Down Arrows] Navigate  |  [Enter] Select" -ForegroundColor DarkGray

                # Key intercept logic
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                if ($key.VirtualKeyCode -eq 38) { # Up Arrow
                    $selectedIndex = ($selectedIndex - 1 + $options.Count) % $options.Count
                }
                elseif ($key.VirtualKeyCode -eq 40) { # Down Arrow
                    $selectedIndex = ($selectedIndex + 1) % $options.Count
                }
                elseif ($key.VirtualKeyCode -eq 13) { # Enter key
                    $running = $false
                }
            } else {
                # Fallback for headless/standard inputs
                Write-Host " Available Options:" -ForegroundColor Gray
                Write-Host ""
                for ($i = 0; $i -lt $options.Count; $i++) {
                    Write-Host "   [$($i + 1)] $($options[$i])" -ForegroundColor White
                }
                Write-Host ""
                
                $inputValid = $false
                while (-not $inputValid) {
                    $choice = Read-Host " Enter choice (1-$($options.Count))"
                    if ($choice -as [int] -and [int]$choice -ge 1 -and [int]$choice -le $options.Count) {
                        $selectedIndex = [int]$choice - 1
                        $inputValid = $true
                        $running = $false
                    } else {
                        Write-Host " Invalid choice. Please try again." -ForegroundColor Red
                    }
                }
            }
        }

        # Action routing
        if ($selectedIndex -eq 0) {
            Clear-Host
            Write-Host "=======================================================" -ForegroundColor Cyan
            Write-Host "               RUNNING RAM CLEANER                     " -ForegroundColor Cyan
            Write-Host "=======================================================" -ForegroundColor Cyan
            Write-Host ""
            
            # $localPath = Join-Path $PSScriptRoot "cleanram.ps1"
            # if ($PSScriptRoot -and (Test-Path $localPath)) {
            #     Write-Host "[*] Executing local cleanram.ps1..." -ForegroundColor Gray
            #     & $localPath
            # } else {
                Write-Host "[*] Fetching cleanram.ps1 from Techku portal..." -ForegroundColor Gray
                try {
                    $scriptContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Digitalisme/PowerShell-Repository-for-Techku/refs/heads/main/cleanram.ps" -ErrorAction Stop
                    Invoke-Expression $scriptContent
                } catch {
                    Write-Host "[!] Error: Failed to download cleanram.ps1 from https://raw.githubusercontent.com/Digitalisme/PowerShell-Repository-for-Techku/refs/heads/main/cleanram.ps" -ForegroundColor Red
                    Write-Host "    Details: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Press any key to return to menu..." -ForegroundColor Gray
                    if ($interactive) {
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    } else {
                        $null = Read-Host
                    }
                # }
            }
        } else {
            Clear-Host
            Write-Host "Exiting Techku Portal. Goodbye!" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            $exitPortal = $true
            $global:TechkuPortalActive = $false
        }
    }
}
