param([int]$ClockHz=100000000,[string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),[string]$ReportTag='upgrade')
$ErrorActionPreference='Stop'
$divider=1000000000.0/$ClockHz
if($divider -lt 2 -or $divider -gt 128 -or [math]::Abs($divider*8-[math]::Round($divider*8)) -gt 0.00001){throw 'ClockHz must give an MMCM output divider in [2,128] with 0.125 granularity (e.g. 50M,80M,100M,125M).'}
& (Join-Path $PSScriptRoot 'build_firmware.ps1') -ProjectRoot $ProjectRoot
$workRoot=Join-Path $ProjectRoot 'build/vivado_upgrade'
& fusesoc --cores-root $ProjectRoot run --target=vc707 --tool=vivado --work-root $workRoot --setup local:ibex:mesh_soc:2.0
if($LASTEXITCODE -ne 0){throw 'FuseSoC Vivado setup failed'}
Push-Location $workRoot
try {
  & vivado -mode batch -source (Join-Path $workRoot 'local_ibex_mesh_soc_2.0.tcl') -log create.log -journal create.jou
  if($LASTEXITCODE -ne 0){throw 'Vivado project creation failed'}
  $xpr=Join-Path $workRoot 'local_ibex_mesh_soc_2.0.xpr'
  if(!(Test-Path $xpr)) {$xpr=(Get-ChildItem $workRoot -Recurse -Filter *.xpr | Select-Object -First 1).FullName}
  if($ReportTag -notmatch '^[A-Za-z0-9_-]+$'){throw 'ReportTag must contain only letters, digits, underscore, or hyphen.'}
  $reports=Join-Path $ProjectRoot "reports/post_route_${ReportTag}_$ClockHz"
  & vivado -mode batch -source (Join-Path $PSScriptRoot 'vivado_post_route.tcl') -log route.log -journal route.jou -tclargs $xpr $reports (Join-Path $ProjectRoot 'sw/build') $ClockHz
  if($LASTEXITCODE -ne 0){throw 'Post-route failed; see build/vivado_upgrade/route.log'}
  $result=Get-Content (Join-Path $reports 'result.txt') | ConvertFrom-StringData
  if([double]$result.setup_slack_ns -lt 0 -or [double]$result.hold_slack_ns -lt 0 -or [int]$result.critical_drc -gt 0){throw "Implementation completed but timing/DRC is not closed at $ClockHz Hz; inspect reports before claiming success."}
} finally {Pop-Location}
