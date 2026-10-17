param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),[string]$FirmwareOutputDir='')
$ErrorActionPreference='Stop'
$fwDir=if($FirmwareOutputDir){$FirmwareOutputDir}else{Join-Path $ProjectRoot 'sw/build'}
& (Join-Path $PSScriptRoot 'build_firmware.ps1') -ProjectRoot $ProjectRoot -OutputDir $fwDir
$workRoot=Join-Path $ProjectRoot 'build/firmware_sim'
& fusesoc --cores-root $ProjectRoot run --target=sim_firmware --tool=modelsim --work-root $workRoot --setup local:ibex:mesh_soc:2.0
if($LASTEXITCODE -ne 0){throw 'FuseSoC firmware setup failed'}
Copy-Item (Join-Path $fwDir 'core*.mem') $workRoot
Push-Location $workRoot
try {
  & vsim -c -do 'do edalize_main.tcl; quit -f' 2>&1 | Out-File compile.log
  if($LASTEXITCODE -ne 0 -or (Select-String compile.log -Pattern '\*\* (Error|Fatal):')){throw 'Firmware HDL compile failed; see compile.log'}
  & vsim -c work.tb_firmware -do 'onerror {quit -code 1}; run -all; quit -f' 2>&1 | Tee-Object firmware.log
  if($LASTEXITCODE -ne 0 -or !(Select-String firmware.log -Pattern 'TEST_PASS:') -or (Select-String firmware.log -Pattern '\*\* (Error|Fatal):')){throw 'Firmware simulation failed; see firmware.log'}
} finally {Pop-Location}
