param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("noc_v2_regression_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

$sources = @(
  'rtl/router/router_pkg.sv',
  'rtl/router/vc_fifo.sv',
  'rtl/router/input_port_vc.sv',
  'rtl/router/packet_arbiter.sv',
  'rtl/router/router_vc.sv',
  'rtl/mesh_3x3/mesh_3x3_vc.sv',
  'rtl/network_interface/axi_lite_if.sv',
  'rtl/network_interface/axi_lite_to_mesh.sv',
  'rtl/network_interface/mesh_to_axi_lite.sv',
  'rtl/ip_core/axi_lite_ram.sv',
  'tb/tb_axi_mesh_3x3.sv'
) | ForEach-Object { Join-Path $ProjectRoot $_ }

Push-Location $tempRoot
try {
  & vlib work | Out-Null
  & vlog -sv @sources
  if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit code $LASTEXITCODE" }
  & vsim -c work.tb_axi_mesh_3x3 -do 'run -all; quit -f'
  if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
