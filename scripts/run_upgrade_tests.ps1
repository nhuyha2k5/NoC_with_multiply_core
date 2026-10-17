param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$ProjectRoot=(Resolve-Path -LiteralPath $ProjectRoot).Path
$out=Join-Path $ProjectRoot 'build/upgrade_tests'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$common=@();$inCommon=$false
foreach($line in (Get-Content (Join-Path $ProjectRoot 'ibex_mesh_soc.core'))){
  if($line -eq '  common:'){$inCommon=$true;continue}
  if($inCommon -and $line -match '^  [a-z]'){break}
  if($inCommon -and $line -match '^      - (rtl/.*\.sv)$'){$common+=Join-Path $ProjectRoot $Matches[1]}
}
$tops=@('tb_queued_ni','tb_axi4_burst_mesh','tb_dma_burst','tb_dma_interleave','tb_qos_runtime','tb_router_starvation')
$files=@((Join-Path $ProjectRoot 'tb/common/axi_lite_bfm.sv'),(Join-Path $ProjectRoot 'tb/common/axi4_bfm.sv'))
$files+=$tops|ForEach-Object{Join-Path $ProjectRoot "tb/$_.sv"}
Push-Location $out
try{
  & vlib work | Out-Null
  & vlog -sv '+define+NOC_LEGACY_2CORE_MAP' @common @files *> compile.log
  if($LASTEXITCODE -ne 0){Get-Content compile.log -Tail 50;throw 'Upgrade compile failed'}
  foreach($top in $tops){
    & vsim -c "work.$top" -do 'onerror {quit -code 1}; run -all; quit -f' *> "$top.log"
    $log=Get-Content "$top.log" -Raw
    if($LASTEXITCODE -ne 0 -or $log -notmatch 'TEST_PASS:' -or $log -match '\*\* (Error|Fatal):'){
      Get-Content "$top.log" -Tail 50;throw "$top failed"
    }
    Select-String "$top.log" -Pattern '^# TEST_PASS:' | ForEach-Object{$_.Line}
  }
}finally{Pop-Location}
