param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$ProjectRoot=(Resolve-Path -LiteralPath $ProjectRoot).Path
$out=Join-Path $ProjectRoot 'build/verification'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$core=Get-Content (Join-Path $ProjectRoot 'ibex_mesh_soc.core')
$common=@()
$inCommon=$false
foreach($line in $core){
  if($line -eq '  common:'){$inCommon=$true;continue}
  if($inCommon -and $line -match '^  [a-z]') {break}
  if($inCommon -and $line -match '^      - (rtl/.*\.sv)$'){$common+=Join-Path $ProjectRoot $Matches[1]}
}
$tb=@('tb/common/axi_lite_bfm.sv','tb/performance/noc_endpoint_stats.sv',
  'tb/tb_interrupts.sv','tb/tb_uart_irq.sv','tb/tb_system_engines.sv',
  'tb/tb_router_correctness.sv','tb/tb_memory_decode.sv','tb/tb_arbiter_reference.sv')|ForEach-Object{Join-Path $ProjectRoot $_}
Push-Location $out
try{
  & vlib work | Out-Null
  & vlog -sv '+define+NOC_LEGACY_2CORE_MAP' @common @tb *> compile.log
  if($LASTEXITCODE -ne 0){Get-Content compile.log -Tail 50;throw 'Compile failed'}
  foreach($top in @('tb_arbiter_reference','tb_router_correctness','tb_memory_decode','tb_interrupts','tb_uart_irq','tb_system_engines')){
    & vsim -c "work.$top" '+CSV=concurrent.csv' -do 'onerror {quit -code 1}; run -all; quit -f' *> "$top.log"
    $log=Get-Content "$top.log" -Raw
    if($LASTEXITCODE -ne 0 -or $log -notmatch 'TEST_PASS:' -or $log -match '\*\* (Error|Fatal):'){
      Get-Content "$top.log" -Tail 60;throw "$top failed"
    }
    Select-String -Path "$top.log" -Pattern '^# (TEST_PASS:|ENDPOINT)'|ForEach-Object{$_.Line}
  }
}finally{Pop-Location}
