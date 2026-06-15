#!/usr/bin/env bash
# deep-analysis.sh — Phase 2 of performance audit: targeted deep dives.
#
# Usage:
#   bash ~/dotfiles/bin/perf/deep-analysis.sh [--section NAME]
#
# Sections: vscode, bloatware, devservers, all (default)
#
# Cross-platform: Windows (Git Bash/MINGW), macOS, Linux.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

OS="$(detect_os)"
SECTION="${1:-all}"

[[ "$SECTION" == "--section" ]] && SECTION="${2:-all}"

# ── VS Code Process Tree ─────────────────────────────────────────────────────
section_vscode() {
    green "── VS Code: extension host memory ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                $codeProcs = Get-CimInstance Win32_Process | Where-Object {
                    $_.Name -match "Code" -and $_.Name -match "\.exe$"
                }

                # Extension hosts — utility processes with high memory
                $extHosts = $codeProcs | Where-Object {
                    $_.CommandLine -match "--type=(utility|extensionHost)" -and $_.WorkingSetSize -gt 100MB
                } | Sort-Object WorkingSetSize -Descending

                if ($extHosts) {
                    foreach ($eh in $extHosts) {
                        $typeName = "ExtHost"
                        if ($eh.CommandLine -match "NodeService") { $typeName = "NodeService" }
                        $mb = [math]::Round($eh.WorkingSetSize / 1MB)
                        Write-Output ("=== {0} PID {1} ({2} MB) ===" -f $typeName, $eh.ProcessId, $mb)

                        # Find child/related processes
                        $children = $codeProcs | Where-Object {
                            $_.ParentProcessId -eq $eh.ProcessId -and $_.WorkingSetSize -gt 10MB
                        }
                        foreach ($c in $children) {
                            $name = "Other"
                            if ($c.CommandLine -match "pylance") { $name = "Pylance" }
                            elseif ($c.CommandLine -match "tsserver") { $name = "TypeScript" }
                            elseif ($c.CommandLine -match "tailwind") { $name = "Tailwind" }
                            elseif ($c.CommandLine -match "eslint") { $name = "ESLint" }
                            elseif ($c.CommandLine -match "copilot") { $name = "Copilot" }
                            elseif ($c.CommandLine -match "spell") { $name = "SpellCheck" }
                            elseif ($c.CommandLine -match "json") { $name = "JSON" }
                            elseif ($c.CommandLine -match "markdown") { $name = "Markdown" }
                            $cmb = [math]::Round($c.WorkingSetSize / 1MB)
                            Write-Output ("  {0} - PID {1} ({2} MB)" -f $name, $c.ProcessId, $cmb)
                        }
                        Write-Output ""
                    }
                } else {
                    Write-Output "  (no VS Code extension hosts found over 100 MB)"
                }
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos)
            echo "  VS Code processes by memory:"
            ps -Ao pid,rss,comm | grep -i "[Cc]ode" | sort -k2 -rn | awk '{printf "  PID %-7s %6.0f MB  %s\n", $1, $2/1024, $3}'
            ;;
        linux)
            echo "  VS Code processes by memory:"
            ps -Ao pid,rss,comm | grep -i "[Cc]ode" | sort -k2 -rn | awk '{printf "  PID %-7s %6.0f MB  %s\n", $1, $2/1024, $3}'
            ;;
    esac

    echo ""
    green "── VS Code: recent workspaces ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                $storageDir = "$env:APPDATA\Code - Insiders\User\workspaceStorage"
                if (-not (Test-Path $storageDir)) {
                    $storageDir = "$env:APPDATA\Code\User\workspaceStorage"
                }
                if (Test-Path $storageDir) {
                    Get-ChildItem $storageDir -Directory | ForEach-Object {
                        $ws = "$($_.FullName)\workspace.json"
                        if (Test-Path $ws) {
                            $data = Get-Content $ws -Raw | ConvertFrom-Json
                            $folder = if ($data.folder) { $data.folder } elseif ($data.workspace) { $data.workspace } else { "unknown" }
                            [PSCustomObject]@{ Folder = $folder; LastWrite = $_.LastWriteTime }
                        }
                    } | Where-Object { $_.LastWrite -gt (Get-Date).AddHours(-12) } |
                    Sort-Object LastWrite -Descending | Format-Table -AutoSize -Wrap
                } else {
                    Write-Output "  (workspace storage dir not found)"
                }
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos)
            local storage_dir="$HOME/Library/Application Support/Code/User/workspaceStorage"
            if [[ -d "$storage_dir" ]]; then
                find "$storage_dir" -name "workspace.json" -mtime -1 -exec cat {} \; 2>/dev/null | grep -o '"folder":"[^"]*"' | head -10
            else
                echo "  (workspace storage not found)"
            fi
            ;;
        linux)
            local storage_dir="$HOME/.config/Code/User/workspaceStorage"
            if [[ -d "$storage_dir" ]]; then
                find "$storage_dir" -name "workspace.json" -mtime -1 -exec cat {} \; 2>/dev/null | grep -o '"folder":"[^"]*"' | head -10
            else
                echo "  (workspace storage not found)"
            fi
            ;;
    esac
}

# ── Bloatware Detection ──────────────────────────────────────────────────────
section_bloatware() {
    green "── Bloatware: running services >20 MB ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                $bloatPatterns = @(
                    # HP
                    "HpTouchpoint", "HpSysInfo", "HpDiags", "BrEndpoint", "BrService", "BrAmSvc",
                    "HpAnalytics", "Sure", "HpComm",
                    # Dell
                    "SupportAssist", "DellData",
                    # Lenovo
                    "Vantage", "LenovoNow",
                    # AV bloat
                    "McAfee", "Norton", "TrendMicro", "Avast",
                    # Telemetry
                    "Telemetry", "DiagTrack", "dmwappushservice", "CompatTelRunner"
                )

                $services = Get-CimInstance Win32_Service | Where-Object { $_.State -eq "Running" }
                $flagged = @()
                $clean = @()

                foreach ($svc in $services) {
                    $proc = Get-Process -Id $svc.ProcessId -ErrorAction SilentlyContinue
                    $mb = if ($proc) { [math]::Round($proc.WorkingSet64/1MB) } else { 0 }

                    $isBloat = $false
                    foreach ($pattern in $bloatPatterns) {
                        if ($svc.Name -match $pattern -or $svc.DisplayName -match $pattern -or $svc.PathName -match $pattern) {
                            $isBloat = $true
                            break
                        }
                    }

                    if ($isBloat) {
                        $flagged += [PSCustomObject]@{
                            Name = $svc.Name
                            Display = $svc.DisplayName
                            MB = $mb
                            Start = $svc.StartMode
                            Path = $svc.PathName
                        }
                    } elseif ($mb -gt 20) {
                        $clean += [PSCustomObject]@{
                            Name = $svc.Name
                            Display = $svc.DisplayName
                            MB = $mb
                            Start = $svc.StartMode
                        }
                    }
                }

                if ($flagged.Count -gt 0) {
                    Write-Output "  ⚠ FLAGGED (known bloatware/telemetry):"
                    Write-Output ""
                    $flagged | Sort-Object MB -Descending | Format-Table Name, Display, MB, Start -AutoSize
                    Write-Output ""
                    Write-Output "  Disable commands:"
                    foreach ($f in $flagged) {
                        Write-Output ("    Stop-Service ''{0}'' -Force; Set-Service ''{0}'' -StartupType Disabled" -f $f.Name)
                    }
                } else {
                    Write-Output "  ✓ No known bloatware services detected"
                }

                Write-Output ""
                Write-Output "  Large services (>20 MB, not flagged):"
                if ($clean.Count -gt 0) {
                    $clean | Sort-Object MB -Descending | Format-Table Name, Display, MB, Start -AutoSize
                } else {
                    Write-Output "  (none)"
                }
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos)
            echo "  Launch agents/daemons consuming resources:"
            launchctl list 2>/dev/null | grep -viE "^-|apple|com\.apple" | head -20 || echo "  (none)"
            ;;
        linux)
            echo "  Non-essential services consuming resources:"
            systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -viE "system|network|ssh|dbus|cron|journal" | head -20 || echo "  (none)"
            ;;
    esac
}

# ── Dev Server Profiling ─────────────────────────────────────────────────────
section_devservers() {
    green "── Dev Servers: node processes >200 MB ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                $nodes = Get-CimInstance Win32_Process -Filter "Name=''node.exe''" |
                    Where-Object { $_.WorkingSetSize -gt 200MB }

                if ($nodes) {
                    $nodes | Select-Object ProcessId,
                        @{N="MB";E={[math]::Round($_.WorkingSetSize/1MB)}},
                        @{N="Uptime";E={
                            $start = (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).StartTime
                            if ($start) { ((Get-Date) - $start).ToString("d\.hh\:mm") } else { "?" }
                        }},
                        @{N="Cmd";E={
                            if ($_.CommandLine.Length -gt 120) { $_.CommandLine.Substring($_.CommandLine.Length-120) }
                            else { $_.CommandLine }
                        }} |
                    Sort-Object MB -Descending | Format-Table -AutoSize -Wrap
                } else {
                    Write-Output "  ✓ No node processes over 200 MB"
                }
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos|linux)
            local result
            result=$(ps -Ao pid,rss,comm,args | grep -i "node" | awk '$2>204800' | sort -k2 -rn)
            if [[ -n "$result" ]]; then
                echo "$result" | awk '{printf "  PID %-7s %6.0f MB  %s\n", $1, $2/1024, $4}'
            else
                green "  ✓ No node processes over 200 MB"
            fi
            ;;
    esac

    echo ""
    green "── Dev Servers: all node instances ──"
    echo ""

    case "$OS" in
        windows)
            local count
            count=$(tasklist 2>/dev/null | grep -ci "node" || true)
            echo "  Total node processes: $count"
            ;;
        macos|linux)
            local count
            count=$(pgrep -c "node" 2>/dev/null || echo 0)
            echo "  Total node processes: $count"
            ;;
    esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
green "╔══════════════════════════════════════════╗"
green "║  ctrl+shft Deep Analysis                 ║"
green "║  OS: $OS                                 "
green "╚══════════════════════════════════════════╝"
echo ""

case "$SECTION" in
    all)
        section_vscode
        echo ""
        section_bloatware
        echo ""
        section_devservers
        ;;
    vscode)     section_vscode ;;
    bloatware)  section_bloatware ;;
    devservers) section_devservers ;;
    *)
        red "Unknown section: $SECTION"
        echo "  Available: vscode, bloatware, devservers, all"
        exit 1
        ;;
esac

echo ""
green "── Deep analysis complete ──"
