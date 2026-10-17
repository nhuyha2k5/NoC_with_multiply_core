param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot 'third_party\ibex\ibex_top.core'))) {
  throw "Vendored Ibex source is missing from third_party/ibex"
}

Write-Host 'Checking the self-contained Ibex, primitive and mesh SoC cores...'
& fusesoc --cores-root $ProjectRoot list-cores | Select-String 'ibex_top|mesh_soc|prim_xilinx'
if ($LASTEXITCODE -ne 0) { throw "FuseSoC core discovery failed" }

Write-Host 'Generate the Vivado project with:'
Write-Host "fusesoc --cores-root `"$ProjectRoot`" run --target=vc707 --setup local:ibex:mesh_soc:2.0"
