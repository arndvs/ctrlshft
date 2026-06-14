#!/usr/bin/env bash
# system-triage.sh — Phase 1 of performance audit: collect raw system metrics.
#
# Usage:
#   bash ~/dotfiles/bin/perf/system-triage.sh [--section NAME]
#
# Sections: memory, processes, network, disk, proxy, all (default)
#
# Cross-platform: Windows (Git Bash/MINGW), macOS, Linux.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

OS="$(detect_os)"
SECTION="${1:-all}"

# Strip --section prefix if passed
[[ "$SECTION" == "--section" ]] && SECTION="${2:-all}"

# ── Memory Snapshot ───────────────────────────────────────────────────────────
section_memory() {
    green "── Memory: process-level (>200 MB private) ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                Get-Process | Where-Object { $_.PrivateMemorySize64 -gt 200MB } |
                Sort-Object PrivateMemorySize64 -Descending |
                Format-Table @{N="PrivMB";E={[math]::Round($_.PrivateMemorySize64/1MB)};A="right"},
                             @{N="WorkMB";E={[math]::Round($_.WorkingSet64/1MB)};A="right"},
                             @{N="Handles";E={$_.HandleCount};A="right"},
                             @{N="Threads";E={$_.Threads.Count};A="right"},
                             @{N="Uptime";E={if($_.StartTime){((Get-Date)-$_.StartTime).ToString("d\.hh\:mm")}else{"?"}}},
                             ProcessName, Id -AutoSize
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos)
            ps -Ao pid,rss,vsz,comm -r | head -20 | awk 'NR==1{print; next} {printf "%7s %8.0f MB %10.0f MB  %s\n", $1, $2/1024, $3/1024, $4}'
            ;;
        linux)
            ps -Ao pid,rss,vsz,comm --sort=-rss | head -20 | awk 'NR==1{print; next} $2>204800{printf "%7s %8.0f MB %10.0f MB  %s\n", $1, $2/1024, $3/1024, $4}'
            ;;
    esac

    echo ""
    green "── Memory: system totals ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                $os = Get-CimInstance Win32_OperatingSystem
                $total = [math]::Round($os.TotalVisibleMemorySize/1MB, 1)
                $free = [math]::Round($os.FreePhysicalMemory/1MB, 1)
                $used = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/1MB, 1)
                $pct = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/$os.TotalVisibleMemorySize * 100)
                Write-Output "  Total: ${total} GB | Used: ${used} GB | Free: ${free} GB | ${pct}% used"
                $commit = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
                if ($commit) {
                    Write-Output "  Committed: $([math]::Round($commit.CommittedBytes/1GB, 1)) GB / $([math]::Round($commit.CommitLimit/1GB, 1)) GB"
                }
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos)
            vm_stat 2>/dev/null | awk '/Pages (free|active|inactive|speculative|wired)/{gsub(/\./,"",$NF); printf "  %-14s %6.0f MB\n", $2, $NF*4096/1048576}'
            sysctl -n hw.memsize 2>/dev/null | awk '{printf "  Total:        %6.0f MB\n", $1/1048576}'
            ;;
        linux)
            free -h 2>/dev/null || cat /proc/meminfo 2>/dev/null | head -5
            ;;
    esac

    echo ""
    green "── Memory: handle hogs (top 10) ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                Get-Process | Sort-Object HandleCount -Descending | Select-Object -First 10 |
                Format-Table @{N="Handles";E={$_.HandleCount};A="right"},
                             @{N="MB";E={[math]::Round($_.WorkingSet64/1MB)};A="right"},
                             ProcessName, Id -AutoSize
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos|linux)
            # Handle counts are a Windows concept; show open file descriptors instead
            echo "  (Open file descriptors per process — top 10)"
            for pid in $(ps -Ao pid --sort=-rss 2>/dev/null | head -12 | tail -11 | tr -d ' '); do
                local count name
                count=$(ls /proc/"$pid"/fd 2>/dev/null | wc -l) || continue
                name=$(ps -p "$pid" -o comm= 2>/dev/null) || continue
                printf "  %6d fds  %s (PID %s)\n" "$count" "$name" "$pid"
            done 2>/dev/null | sort -rn | head -10
            ;;
    esac
}

# ── Process Census ────────────────────────────────────────────────────────────
section_processes() {
    green "── Processes: top 15 memory hogs ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 |
                Format-Table @{N="MB";E={[math]::Round($_.WorkingSet64/1MB)};A="right"}, ProcessName, Id -AutoSize
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos)
            ps -Amro pid,rss,comm | head -16 | awk 'NR==1{print; next} {printf "%7s %6.0f MB  %s\n", $1, $2/1024, $3}'
            ;;
        linux)
            ps -Ao pid,rss,comm --sort=-rss | head -16 | awk 'NR==1{print; next} {printf "%7s %6.0f MB  %s\n", $1, $2/1024, $3}'
            ;;
    esac

    echo ""
    green "── Processes: AI / Editor / Dev ──"
    echo ""

    case "$OS" in
        windows)
            local procs
            procs=$(tasklist 2>/dev/null)
            echo "$procs" | grep -iE "Code|orca|claude|node|python|srt|litellm|uv|cursor" | sort -k5 -rn || echo "  (none)"
            echo ""
            echo "  VS Code:  $(echo "$procs" | grep -ci 'Code')"
            echo "  Orca:     $(echo "$procs" | grep -ci 'Orca')"
            echo "  Node:     $(echo "$procs" | grep -ci 'node')"
            echo "  Python:   $(echo "$procs" | grep -ci 'python')"
            echo "  Cursor:   $(echo "$procs" | grep -ci 'cursor')"
            ;;
        macos|linux)
            ps -Ao pid,rss,comm | grep -iE "code|orca|claude|node|python|litellm|uv|cursor" | sort -k2 -rn || echo "  (none)"
            echo ""
            echo "  VS Code:  $(pgrep -ci 'code' 2>/dev/null || echo 0)"
            echo "  Node:     $(pgrep -ci 'node' 2>/dev/null || echo 0)"
            echo "  Python:   $(pgrep -ci 'python' 2>/dev/null || echo 0)"
            echo "  Cursor:   $(pgrep -ci 'cursor' 2>/dev/null || echo 0)"
            ;;
    esac
}

# ── Network Latency ───────────────────────────────────────────────────────────
section_network() {
    green "── Network: API latency ──"
    echo ""

    echo "  GitHub API:"
    curl -sf -w "    dns: %{time_namelookup}s | connect: %{time_connect}s | tls: %{time_appconnect}s | total: %{time_total}s\n" -o /dev/null https://api.github.com 2>/dev/null || echo "    (unreachable)"

    echo "  Copilot API:"
    curl -sf -w "    dns: %{time_namelookup}s | connect: %{time_connect}s | tls: %{time_appconnect}s | total: %{time_total}s\n" -o /dev/null https://api.githubcopilot.com 2>/dev/null || echo "    (not reachable — normal if no active Copilot session)"
}

# ── Disk Health ───────────────────────────────────────────────────────────────
section_disk() {
    green "── Disk: free space ──"
    echo ""

    case "$OS" in
        windows)
            powershell.exe -NoProfile -Command '
                Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
                Format-Table DeviceID,
                    @{N="Total GB";E={[math]::Round($_.Size/1GB,1)};A="right"},
                    @{N="Free GB";E={[math]::Round($_.FreeSpace/1GB,1)};A="right"},
                    @{N="Free %";E={[math]::Round($_.FreeSpace/$_.Size*100)};A="right"} -AutoSize
            ' 2>/dev/null || yellow "  (PowerShell not available)"
            ;;
        macos|linux)
            df -h / 2>/dev/null
            ;;
    esac
}

# ── Proxy Health ──────────────────────────────────────────────────────────────
section_proxy() {
    green "── Proxy: LiteLLM health ──"
    echo ""

    if curl -sf -w "  response: %{time_total}s\n" -o /dev/null http://localhost:4000/health/readiness 2>/dev/null; then
        green "  healthy"
    else
        echo "  not running (or not on port 4000)"
    fi

    echo ""
    echo "  Last 15 log lines:"
    tail -15 ~/.shft/proxy.log 2>/dev/null || echo "  (no proxy log found)"
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
green "╔══════════════════════════════════════════╗"
green "║  ctrl+shft Performance Triage            ║"
green "║  OS: $OS                                 "
green "╚══════════════════════════════════════════╝"
echo ""

case "$SECTION" in
    all)
        section_memory
        echo ""
        section_processes
        echo ""
        section_network
        echo ""
        section_disk
        echo ""
        section_proxy
        ;;
    memory)    section_memory ;;
    processes) section_processes ;;
    network)   section_network ;;
    disk)      section_disk ;;
    proxy)     section_proxy ;;
    *)
        red "Unknown section: $SECTION"
        echo "  Available: memory, processes, network, disk, proxy, all"
        exit 1
        ;;
esac

echo ""
green "── Triage complete ──"
