# Maple2 Client XML Build Script
# Always builds from orig backup, applies ALL patches in sequence
# To add a new fix: add a new step below
# Never build from "live" - always from orig

$ErrorActionPreference = "Stop"
$cli = "C:\Users\icegi\Maple2\Orion2-CLI\bin\Release\net8.0\Orion2-CLI.exe"
$origH = "C:\Users\icegi\Maple2\client\Data\Xml.m2h.orig"
$origD = "C:\Users\icegi\Maple2\client\Data\Xml.m2d.orig"
$work = "C:\Users\icegi\Maple2\client_work"

# ========== PATCH REGISTRY ==========
# Each patch: (stepName, inputFile, archivePath, type)
# type: "replace" = replace existing file, "batch-skill" = batch potion skill replacement

# Step 1: Batch replace 640 consumable skills with potion template
# Step 2: Replace skill 90000050 -> 5x exp custom skill
# Step 3: Replace skill 90000092 -> atk+150% custom skill
# Step 4: Replace item 20001011 -> 5x exp ticket
# Step 5: Replace item 20001012 -> atk+150% ticket
# Step 6: Replace string/cn/itemname.xml -> Chinese names for custom items

# ========== BUILD ==========

Write-Host "=== Step 1: Batch potion skill replacement (640 items) ==="
& $cli patch-copy-potion-skill $origH $origD "$work\all_item_ids.txt" "$work\build_s1.m2h" "$work\build_s1.m2d"
if (-not (Test-Path "$work\build_s1.m2d")) { throw "Step 1 failed" }
$curH = "$work\build_s1.m2h"; $curD = "$work\build_s1.m2d"

Write-Host "`n=== Step 2: Replace skill 90000050 (5x exp) ==="
& $cli replace $curH $curD "skill/90/90000050.xml" "$work\custom_90000050.xml" "$work\build_s2.m2h" "$work\build_s2.m2d"
$curH = "$work\build_s2.m2h"; $curD = "$work\build_s2.m2d"

Write-Host "`n=== Step 3: Replace skill 90000092 (atk+150%) ==="
& $cli replace $curH $curD "skill/90/90000092.xml" "$work\custom_90000092.xml" "$work\build_s3.m2h" "$work\build_s3.m2d"
$curH = "$work\build_s3.m2h"; $curD = "$work\build_s3.m2d"

Write-Host "`n=== Step 4: Replace item 20001011 (5x exp ticket) ==="
& $cli replace $curH $curD "item/2/00/20001011.xml" "$work\custom_20001011.xml" "$work\build_s4.m2h" "$work\build_s4.m2d"
$curH = "$work\build_s4.m2h"; $curD = "$work\build_s4.m2d"

Write-Host "`n=== Step 5: Replace item 20001012 (atk+150% ticket) ==="
& $cli replace $curH $curD "item/2/00/20001012.xml" "$work\custom_20001012.xml" "$work\build_s5.m2h" "$work\build_s5.m2d"
$curH = "$work\build_s5.m2h"; $curD = "$work\build_s5.m2d"

Write-Host "`n=== Step 6: Replace itemname.xml (Chinese names) ==="
& $cli replace $curH $curD "string/cn/itemname.xml" "$work\custom_itemname.xml" "$work\build_final.m2h" "$work\build_final.m2d"

Write-Host "`n=== BUILD COMPLETE ==="
Write-Host "Output: $work\build_final.m2h + $work\build_final.m2d"
Write-Host "Size: $((Get-Item "$work\build_final.m2d").Length) bytes"

# ========== DEPLOY (uncomment to auto-deploy) ==========
# Write-Host "`n=== Deploying ==="
# Get-Process MapleStory2,"Mushroom Launcher" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
# Start-Sleep 3
# Copy-Item "$work\build_final.m2h" "C:\Users\icegi\Maple2\client\Data\Xml.m2h" -Force
# Copy-Item "$work\build_final.m2d" "C:\Users\icegi\Maple2\client\Data\Xml.m2d" -Force
# Write-Host "Deployed to live"
