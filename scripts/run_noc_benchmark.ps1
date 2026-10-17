param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),[switch]$Quick,[string]$RunTag='',
  [ValidateRange(0,2)][int]$QosMode=1,[ValidateRange(0,1)][int]$QosClasses=0)
$ErrorActionPreference='Stop'
$ProjectRoot=(Resolve-Path $ProjectRoot).Path
if($RunTag -and $RunTag -notmatch '^[A-Za-z0-9_-]+$'){throw 'RunTag must contain only letters, digits, underscore, or hyphen.'}
$out=Join-Path $ProjectRoot $(if($RunTag){"build/baseline_$RunTag"}else{'build/baseline'})
New-Item -ItemType Directory -Path $out -Force | Out-Null
$runLock=[IO.File]::Open((Join-Path $out 'run.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$sources=@('router_pkg','vc_fifo','input_port_vc','packet_arbiter','router_vc')|ForEach-Object{Join-Path $ProjectRoot "rtl/router/$_.sv"}
$sources+=Join-Path $ProjectRoot 'rtl/mesh_3x3/mesh_3x3_vc.sv'
$sources+=Join-Path $ProjectRoot 'tb/performance/tb_noc_baseline.sv'
Push-Location $out
try {
  & vlib work | Out-Null
  & vlog -sv @sources *> compile.log
  if($LASTEXITCODE -ne 0){Get-Content compile.log -Tail 40;throw 'Baseline compile failed'}
  $patterns=@(0,1,2,3,4);$rates=@(2,10,20,30);$seeds=@(1,42,2026)
  if($Quick){$patterns=@(0,1);$rates=@(10,30);$seeds=@(1)}
  foreach($pattern in $patterns){foreach($rate in $rates){foreach($seed in $seeds){
    foreach($stall in @(0,50)){
      $name="p${pattern}_r${rate}_s${stall}_seed${seed}"
      & vsim -c work.tb_noc_baseline "+RATE=$rate" "+PATTERN=$pattern" "+STALL=$stall" "+SEED=$seed" "+QOS_MODE=$QosMode" "+QOS_CLASSES=$QosClasses" "+CSV=$name.csv" -do 'onerror {quit -code 1}; run -all; quit -f' *> "$name.log"
      $log=Get-Content "$name.log" -Raw
      if($LASTEXITCODE -ne 0 -or $log -notmatch 'TEST_PASS:' -or $log -match '\*\* (Error|Fatal):'){Get-Content "$name.log" -Tail 40;throw "$name failed"}
      Select-String "$name.log" -Pattern '^# (BASELINE|TEST_PASS)'|ForEach-Object{$_.Line}
    }
  }}}
  Get-ChildItem -Filter p*_r*_s*_seed*.csv | ForEach-Object{Import-Csv $_.FullName} | Export-Csv summary.csv -NoTypeInformation
} finally {Pop-Location;$runLock.Dispose()}
