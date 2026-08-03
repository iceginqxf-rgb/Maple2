# Maple2 Client XML Build & Deploy System
# 
# Two modes:
#   build-client.ps1 full    - Full rebuild from orig (verify consistency)
#   build-client.ps1 incr    - Incremental: apply only new step from staging baseline
#   build-client.ps1 deploy   - Deploy staging to live (stop client, copy, restart)
#   build-client.ps1 verify   - Verify staging matches expected files
#
# Staging files:
#   client_work/staging.m2h / staging.m2d  - Current build baseline
#   client_work/staging-version.txt         - Track which steps have been applied
#
# Custom files (all in client_work/):
#   custom_90000050.xml     - 5x exp skill
#   custom_90000092.xml     - atk+150% skill  
#   custom_20001011.xml     - 5x exp item
#   custom_20001012.xml     - atk+150% item
#   custom_itemname.xml     - Chinese names
#   all_item_ids.txt        - Item IDs for batch potion skill replacement

param(
    [Parameter(Position=0)]
    [string]$Mode = "full"
)

$ErrorActionPreference = "Stop"
$cli = "C:\Users\icegi\Maple2\Orion2-CLI\bin\Release\net8.0\Orion2-CLI.exe"
$origH = "C:\Users\icegi\Maple2\client\Data\Xml.m2h.orig"
$origD = "C:\Users\icegi\Maple2\client\Data\Xml.m2d.orig"
$work = "C:\Users\icegi\Maple2\client_work"
$stgH = "$work\staging.m2h"
$stgD = "$work\staging.m2d"
$verFile = "$work\staging-version.txt"

# Define all build steps in order
# Each step: name, command type, params
$steps = @(
    @{ Name="batch-potion-skill"; Type="batch"; Input="$work\all_item_ids.txt" }
    @{ Name="skill-90000050";    Type="replace"; Path="skill/90/90000050.xml"; Input="$work\custom_90000050.xml" }
    @{ Name="skill-90000092";    Type="replace"; Path="skill/90/90000092.xml"; Input="$work\custom_90000092.xml" }
    @{ Name="item-20001011";     Type="replace"; Path="item/2/00/20001011.xml"; Input="$work\custom_20001011.xml" }
    @{ Name="item-20001012";     Type="replace"; Path="item/2/00/20001012.xml"; Input="$work\custom_20001012.xml" }
    @{ Name="itemname";           Type="replace"; Path="string/cn/itemname.xml"; Input="$work\custom_itemname.xml" }
)

function GetAppliedSteps {
    if (Test-Path $verFile) {
        return Get-Content $verFile | Where-Object { $_.Trim().Length -gt 0 }
    }
    return @()
}

function SaveAppliedSteps($applied) {
    $applied | Set-Content $verFile
}

function ApplyStep($step, $inH, $inD, $outH, $outD) {
    Write-Host "  Applying: $($step.Name)"
    if ($step.Type -eq "batch") {
        & $cli patch-copy-potion-skill $inH $inD $step.Input $outH $outD
    } elseif ($step.Type -eq "replace") {
        & $cli replace $inH $inD $step.Path $step.Input $outH $outD
    }
    if (-not (Test-Path $outD)) { throw "Step $($step.Name) failed - output not created" }
}

switch ($Mode.ToLower()) {

    "full" {
        Write-Host "=== FULL REBUILD from orig ==="
        $curH = $origH; $curD = $origD
        $applied = @()
        $stepNum = 0
        foreach ($step in $steps) {
            $stepNum++
            $outH = "$work\staging_s$stepNum.m2h"
            $outD = "$work\staging_s$stepNum.m2d"
            Write-Host "`nStep $stepNum/$($steps.Count): $($step.Name)"
            ApplyStep $step $curH $curD $outH $outD
            $curH = $outH; $curD = $outD
            $applied += $step.Name
        }
        # Copy final to staging
        Copy-Item $curH $stgH -Force
        Copy-Item $curD $stgD -Force
        SaveAppliedSteps $applied
        Write-Host "`n=== FULL BUILD COMPLETE ==="
        Write-Host "Staging: $stgD ($((Get-Item $stgD).Length) bytes)"
        Write-Host "Steps applied: $($applied.Count)/$($steps.Count)"
    }

    "incr" {
        Write-Host "=== INCREMENTAL BUILD from staging ==="
        if (-not (Test-Path $stgD)) {
            Write-Host "No staging found, running full build first..."
            & $PSCommandPath "full"
            return
        }
        $applied = GetAppliedSteps
        $curH = $stgH; $curD = $stgD
        $newCount = 0
        foreach ($step in $steps) {
            if ($applied -contains $step.Name) { continue }
            $newCount++
            $outH = "$work\staging_new.m2h"
            $outD = "$work\staging_new.m2d"
            Write-Host "`nNew step: $($step.Name)"
            ApplyStep $step $curH $curD $outH $outD
            $curH = $outH; $curD = $outD
            $applied += $step.Name
        }
        if ($newCount -eq 0) {
            Write-Host "No new steps to apply. Staging is up to date."
        } else {
            Copy-Item $curH $stgH -Force
            Copy-Item $curD $stgD -Force
            SaveAppliedSteps $applied
            Write-Host "`n=== INCREMENTAL BUILD COMPLETE ==="
            Write-Host "Applied $newCount new step(s). Total: $($applied.Count)/$($steps.Count)"
        }
    }

    "deploy" {
        Write-Host "=== DEPLOY staging to live ==="
        if (-not (Test-Path $stgD)) { throw "No staging found. Run build first." }
        Get-Process MapleStory2,"Mushroom Launcher" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep 3
        Copy-Item $stgH "C:\Users\icegi\Maple2\client\Data\Xml.m2h" -Force
        Copy-Item $stgD "C:\Users\icegi\Maple2\client\Data\Xml.m2d" -Force
        Write-Host "Deployed: $((Get-Item 'C:\Users\icegi\Maple2\client\Data\Xml.m2d').Length) bytes"
    }

    "verify" {
        Write-Host "=== VERIFY staging ==="
        $applied = GetAppliedSteps
        Write-Host "Steps applied: $($applied.Count)/$($steps.Count)"
        foreach ($s in $applied) { Write-Host "  - $s" }
        if (Test-Path $stgD) {
            Write-Host "`nStaging: $((Get-Item $stgD).Length) bytes, $((Get-Item $stgD).LastWriteTime)"
        } else {
            Write-Host "`nNo staging file found!"
        }
    }

    "restart-server" {
        Write-Host "=== RESTART SERVER ==="
        Stop-Process -Name Maple2.Server.Game,Maple2.Server.Login,Maple2.Server.World,Maple2.Server.Web -Force -EA SilentlyContinue
        Start-Sleep 2
        schtasks /run /tn Maple2-Server-World
        Start-Sleep 2
        schtasks /run /tn Maple2-Server-Login
        schtasks /run /tn Maple2-Server-Web
        Start-Sleep 2
        schtasks /run /tn Maple2-Server-Game
        Start-Sleep 5
        Get-Process Maple2.Server.* -EA SilentlyContinue | FT Id,ProcessName -AutoSize
    }

    default {
        Write-Host @"
Maple2 Client Build System

Usage:
  build-client.ps1 full           - Full rebuild from orig backup (safe, slow)
  build-client.ps1 incr           - Incremental: apply only new steps from staging
  build-client.ps1 deploy          - Deploy staging to live client
  build-client.ps1 verify         - Show staging status and applied steps
  build-client.ps1 restart-server  - Restart game server

Workflow:
  1. Add new custom XML to client_work/
  2. Add new step to $steps array in this script
  3. Run: build-client.ps1 incr    (fast, only applies new step)
  4. Run: build-client.ps1 deploy  (deploy to live)
  5. Test in game
  6. Periodically: build-client.ps1 full (verify consistency)
"@
    }
}
