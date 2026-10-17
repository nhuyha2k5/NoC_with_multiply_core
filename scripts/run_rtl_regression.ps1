param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$ProjectRoot=(Resolve-Path $ProjectRoot).Path
$tempRoot = Join-Path $ProjectRoot 'build/rtl_regression'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$router = @(
  'rtl/router/router_pkg.sv',
  'rtl/router/vc_fifo.sv',
  'rtl/router/input_port_vc.sv',
  'rtl/router/packet_arbiter.sv',
  'rtl/router/router_vc.sv',
  'rtl/mesh_3x3/mesh_3x3_vc.sv'
)
$interfaces = @(
  'rtl/cache/coherence_pkg.sv',
  'rtl/network_interface/axi_lite_if.sv',
  'rtl/network_interface/coherence_if.sv',
  'rtl/network_interface/axi_lite_to_mesh.sv',
  'rtl/network_interface/mesh_to_axi_lite.sv'
)

function Invoke-QuestaTest {
  param([string]$Name, [string]$Top, [string[]]$Files)
  $testDir = Join-Path $tempRoot $Name
  New-Item -ItemType Directory -Path $testDir -Force | Out-Null
  $sources = $Files | ForEach-Object { Join-Path $ProjectRoot $_ }
  Push-Location $testDir
  try {
    & vlib work | Out-Null
    & vlog -sv '+define+NOC_LEGACY_2CORE_MAP' @sources *> compile.log
    if ($LASTEXITCODE -ne 0) { throw "$Name compilation failed" }
    & vsim -c "work.$Top" -do 'onerror {quit -code 1}; run -all; quit -f' *> simulation.log
    $log=Get-Content simulation.log -Raw
    if ($LASTEXITCODE -ne 0 -or $log -notmatch 'TEST_PASS:' -or $log -match '\*\* (Error|Fatal):') { Get-Content simulation.log -Tail 40;throw "$Name simulation failed" }
    Select-String simulation.log -Pattern '^# TEST_PASS:' | ForEach-Object {$_.Line}
  } finally {
    Pop-Location
  }
}

try {
  Invoke-QuestaTest 'qos' 'tb_packet_arbiter_qos' @(
    'rtl/router/packet_arbiter.sv',
    'tb/tb_packet_arbiter_qos.sv'
  )

  Invoke-QuestaTest 'axi_mesh' 'tb_axi_mesh_3x3' ($router + @(
    'rtl/network_interface/axi_lite_if.sv',
    'rtl/network_interface/axi_lite_to_mesh.sv',
    'rtl/network_interface/mesh_to_axi_lite.sv',
    'rtl/ip_core/axi_lite_ram.sv',
    'tb/tb_axi_mesh_3x3.sv'
  ))

  Invoke-QuestaTest 'mesi' 'tb_mesi_coherence' ($router + $interfaces + @(
    'rtl/cache/coherence_manager.sv',
    'rtl/cache/coherence_manager_2core.sv',
    'rtl/cache/mesi_dcache.sv',
    'rtl/ip_core/axi_lite_ram.sv',
    'tb/tb_mesi_coherence.sv'
  ))

  Invoke-QuestaTest 'mesi4' 'tb_mesi_coherence_4core' ($router + $interfaces + @(
    'rtl/cache/coherence_manager.sv',
    'rtl/cache/mesi_dcache.sv',
    'rtl/ip_core/axi_lite_ram.sv',
    'tb/tb_mesi_coherence_4core.sv'
  ))

  Invoke-QuestaTest 'peripherals' 'tb_distributed_peripherals' ($router + @(
    'rtl/network_interface/axi_lite_if.sv',
    'rtl/network_interface/axi_lite_to_mesh.sv',
    'rtl/network_interface/mesh_to_axi_lite.sv',
    'rtl/ip_core/axi_lite_register_port.sv',
    'rtl/ip_core/axi_lite_uart.sv',
    'rtl/ip_core/axi_lite_gpio.sv',
    'rtl/ip_core/axi_lite_timer.sv',
    'rtl/ip_core/axi_lite_mailbox.sv',
    'rtl/node/uart_node.sv',
    'rtl/node/gpio_node.sv',
    'rtl/node/timer_node.sv',
    'rtl/node/mailbox_node.sv',
    'tb/tb_distributed_peripherals.sv'
  ))
  Write-Host 'ALL_TESTS_PASS: QoS, AXI mesh, MESI 2-core and 4-core, distributed peripheral regressions'
} finally {
  Write-Host "Regression logs retained at $tempRoot"
}
