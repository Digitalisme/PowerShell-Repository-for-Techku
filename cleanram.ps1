# ==============================================================================
# RAMCleaner.ps1 - PowerShell Port of RAMCleaner-ori.cpp
# Created by Roland Vincent (C++ Port) / Cleaned up in PowerShell
# Modified by Techku for online script run
# ==============================================================================

& {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Output Header
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "                  SYSTEM RAM CLEANER                   " -ForegroundColor Cyan
    Write-Host "            PowerShell Edition (P/Invoke)              " -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "Created by Roland Vincent" -ForegroundColor Gray
    Write-Host "Modified by Techku for Powershell running" -ForegroundColor Gray
    Write-Host ""

    if (-not $isAdmin) {
        Write-Host "[!] WARNING: You are running as a non-Administrator." -ForegroundColor Yellow
        Write-Host "    Some system processes cannot be optimized due to permissions." -ForegroundColor Yellow
        Write-Host "    For maximum RAM reclamation, please run PowerShell as Admin." -ForegroundColor Yellow
        Write-Host ""
    }

    # P/Invoke definitions for Win32 API calls
    $Signature = @'
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetProcessWorkingSetSize(IntPtr hProcess, IntPtr dwMinimumWorkingSetSize, IntPtr dwMaximumWorkingSetSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
'@

    if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
        Add-Type -TypeDefinition $Signature
    }

    $PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    $PROCESS_VM_READ = 0x0010
    $PROCESS_SET_LIMITED_INFORMATION = 0x2000
    $PROCESS_SET_QUOTA = 0x0100
    $Access = $PROCESS_QUERY_LIMITED_INFORMATION -bor $PROCESS_VM_READ -bor $PROCESS_SET_LIMITED_INFORMATION -bor $PROCESS_SET_QUOTA

    function Get-MemoryStatus {
        $total = 0
        $free = 0
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $total = $os.TotalVisibleMemorySize * 1024
            $free = $os.FreePhysicalMemory * 1024
        } catch {
            try {
                $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
                $total = $os.TotalVisibleMemorySize * 1024
                $free = $os.FreePhysicalMemory * 1024
            } catch {
                $total = [System.GC]::GetGCMemoryInfo().TotalAvailableMemoryBytes
                $free = 0
            }
        }
        $used = $total - $free
        $percent = if ($total -gt 0) { [Math]::Round(($used / $total) * 100, 1) } else { 0 }
        
        return [PSCustomObject]@{
            TotalBytes = $total
            FreeBytes  = $free
            UsedBytes  = $used
            Percent    = $percent
        }
    }

    function Show-MemoryBar ($status) {
        $barLength = 20
        $filledLength = [System.Convert]::ToInt32([Math]::Round(($status.Percent / 100) * $barLength))
        $emptyLength = $barLength - $filledLength
        
        $bar = ("#" * $filledLength) + ("-" * $emptyLength)
        
        $usedGB = [Math]::Round($status.UsedBytes / 1GB, 2)
        $totalGB = [Math]::Round($status.TotalBytes / 1GB, 2)
        
        Write-Host "Memory Usage: [$bar] $($status.Percent)% ($usedGB GB / $totalGB GB)" -ForegroundColor Cyan
    }

    # Fetch initial memory state
    $memBefore = Get-MemoryStatus
    Show-MemoryBar $memBefore
    Write-Host ""
    Write-Host "[] Starting RAM Cleaner..." -ForegroundColor Cyan

    $processes = Get-Process
    $successCount = 0
    $failCount = 0
    $deniedCount = 0
    $results = @()

    $totalProcs = $processes.Count
    $current = 0

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($proc in $processes) {
        $current++
        if ($proc.Id -eq 0 -or $proc.Id -eq 4) { continue }
        
        # Display smooth text progress bar
        $percent = [Math]::Round(($current / $totalProcs) * 100)
        $barProgress = [System.Convert]::ToInt32([Math]::Round($percent / 5))
        $bar = ("#" * $barProgress) + ("-" * (20 - $barProgress))
        
        $procName = $proc.ProcessName
        if ($procName.Length -gt 15) { $procName = $procName.Substring(0, 15) + "..." }
        $procName = $procName.PadRight(18)
        
        Write-Host -NoNewline ("`rProgress: [$bar] $percent% ($procName)")
        
        try {
            $name = $proc.ProcessName
            $processId = $proc.Id
            $wsBefore = $proc.WorkingSet64
        } catch {
            continue
        }
        
        # Open process and trim working set size
        $h = [Win32]::OpenProcess($Access, $false, $processId)
        if ($h -ne [IntPtr]::Zero) {
            $res = [Win32]::SetProcessWorkingSetSize($h, [IntPtr](-1), [IntPtr](-1))
            [void][Win32]::CloseHandle($h)
            
            if ($res) {
                $successCount++
                $proc.Refresh()
                try {
                    $wsAfter = $proc.WorkingSet64
                    $freed = $wsBefore - $wsAfter
                    if ($freed -lt 0) { $freed = 0 }
                } catch {
                    $freed = 0
                }
                if ($freed -gt 0) {
                    $results += [PSCustomObject]@{
                        Name  = $name
                        PID   = $processId
                        Freed = $freed
                    }
                }
            } else {
                $failCount++
            }
        } else {
            $deniedCount++
        }
    }

    $sw.Stop()
    Write-Host "" # Clear progress bar line
    Write-Host "[] Finished in $($sw.ElapsedMilliseconds) ms`n" -ForegroundColor Green

    # Fetch final memory state
    $memAfter = Get-MemoryStatus
    $systemFreedTotal = $memBefore.UsedBytes - $memAfter.UsedBytes
    if ($systemFreedTotal -lt 0) { $systemFreedTotal = 0 }
    $processFreedTotal = ($results | Measure-Object -Property Freed -Sum).Sum

    # Print Summary block
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "                     SUMMARY                           " -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "  Processes Optimized    : $successCount"
    Write-Host "  Processes Skipped      : $deniedCount (Access Denied)"
    Write-Host "  RAM Freed (Process sum): $([Math]::Round($processFreedTotal / 1MB, 2)) MB"
    Write-Host "  RAM Freed (System-wide): $([Math]::Round($systemFreedTotal / 1MB, 2)) MB"
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Show-MemoryBar $memAfter
    Write-Host ""

    # Print Top 10 Reclaimed Processes
    $topFreed = $results | Sort-Object Freed -Descending | Select-Object -First 10
    if ($topFreed) {
        Write-Host "Top 10 Reclaimed Processes:" -ForegroundColor Green
        Write-Host "=======================================================" -ForegroundColor Cyan
        Write-Host " Process Name         | PID         | RAM Freed        " -ForegroundColor Cyan
        Write-Host "-------------------------------------------------------" -ForegroundColor Cyan
        foreach ($item in $topFreed) {
            $nameCol = $item.Name
            if ($nameCol.Length -gt 20) { $nameCol = $nameCol.Substring(0, 17) + "..." }
            $nameCol = $nameCol.PadRight(20)
            
            $pidCol = "$($item.PID)".PadRight(11)
            
            $freedMB = [Math]::Round($item.Freed / 1MB, 2)
            $freedCol = "$freedMB MB".PadRight(15)
            
            Write-Host " $nameCol | $pidCol | $freedCol"
        }
        Write-Host "=======================================================" -ForegroundColor Cyan
    }
        Write-Host ""
    Write-Host "Press any key to return to Techku Portal..." -ForegroundColor Gray
    $interactive = $true
    try { $null = $Host.UI.RawUI.KeyAvailable } catch { $interactive = $false }
    if ($interactive) {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        $null = Read-Host
    }
    if (-not $global:TechkuPortalActive) {
        Write-Host "[*] Redirecting back to Techku Portal..." -ForegroundColor Gray
        Invoke-RestMethod "https://raw.githubusercontent.com/Digitalisme/PowerShell-Repository-for-Techku/refs/heads/main/home.ps1" | Invoke-Expression
    }
}
