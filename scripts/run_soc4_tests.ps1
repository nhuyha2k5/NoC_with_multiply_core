# 4-core SoC block/system tests on the default (4-core) address map:
# PLIC 4x16 + CLINT, node map/decode with 4 masters, 4-cache MESI (both
# manager modes). Logs: build/soc4_tests/<test>.log
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$ProjectRoot=(Resolve-Path -LiteralPath $ProjectRoot).Path
$out=Join-Path $ProjectRoot 'build/soc4_tests'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$common=@();$inCommon=$false
foreach($line in (Get-Content (Join-Path $ProjectRoot 'ibex_mesh_soc.core'))){
  if($line -eq '  common:'){$inCommon=$true;continue}
  if($inCommon -and $line -match '^  [a-z]'){break}
  if($inCommon -and $line -match '^      - (rtl/.*\.sv)$'){$common+=Join-Path $ProjectRoot $Matches[1]}
}
$tb=@('tb/common/axi_lite_bfm.sv','tb/tb_interrupts_4hart.sv','tb/tb_soc_4core_map.sv','tb/tb_mesi_coherence_4core.sv')|
  ForEach-Object{Join-Path $ProjectRoot $_}
$runs=@(
  @{Name='tb_interrupts_4hart';Top='tb_interrupts_4hart';Args=@()},
  @{Name='tb_soc_4core_map';Top='tb_soc_4core_map';Args=@()},
  @{Name='tb_mesi_coherence_4core_er1';Top='tb_mesi_coherence_4core';Args=@('-gEARLY_RELEASE=1')},
  @{Name='tb_mesi_coherence_4core_er0';Top='tb_mesi_coherence_4core';Args=@('-gEARLY_RELEASE=0')}
)
Push-Location $out
try{
  if(Test-Path work){Remove-Item -Recurse -Force work}
  & vlib work | Out-Null
  & vlog -sv @common @tb *> compile.log
  if($LASTEXITCODE -ne 0){Get-Content compile.log -Tail 50;throw '4-core test compile failed'}
  foreach($r in $runs){
    $log="$($r.Name).log"
    $vsimArgs=@('-c',"work.$($r.Top)")+$r.Args+@('-do','onerror {quit -code 1}; run -all; quit -f')
    & vsim @vsimArgs *> $log
    $text=Get-Content $log -Raw
    if($LASTEXITCODE -ne 0 -or $text -notmatch 'TEST_PASS:' -or $text -match '\*\* (Error|Fatal):'){
      Get-Content $log -Tail 40;throw "$($r.Name) failed"
    }
    Select-String $log -Pattern '^# (TEST_PASS:|MESI4_)' | ForEach-Object{$_.Line}
  }
  Write-Host 'ALL_TESTS_PASS: 4-core interrupts, node map, 4-cache MESI (EARLY_RELEASE 1/0)'
}finally{Pop-Location}
