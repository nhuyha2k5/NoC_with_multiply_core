param([switch]$QuickBenchmark,[switch]$PostRoute,[int]$ClockHz=100000000,[string]$RunTag='upgrade_current')
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'run_rtl_regression.ps1')
& python (Join-Path $PSScriptRoot 'run_mesi_mutations.py')
if($LASTEXITCODE -ne 0){throw 'MESI mutation suite: a mutation survived or errored'}
& (Join-Path $PSScriptRoot 'run_system_tests.ps1')
& (Join-Path $PSScriptRoot 'run_upgrade_tests.ps1')
& (Join-Path $PSScriptRoot 'run_soc4_tests.ps1')
& (Join-Path $PSScriptRoot 'run_firmware.ps1')
& (Join-Path $PSScriptRoot 'run_noc_benchmark.ps1') -Quick:$QuickBenchmark -RunTag $RunTag
if($PostRoute){& (Join-Path $PSScriptRoot 'run_post_route.ps1') -ClockHz $ClockHz -ReportTag $RunTag}
Write-Host 'ALL_TESTS_PASS: correctness, MESI 2/4-core (+mutations), IRQ 2/4-hart, 4-core map, engines, real 4-Ibex firmware, baseline'
