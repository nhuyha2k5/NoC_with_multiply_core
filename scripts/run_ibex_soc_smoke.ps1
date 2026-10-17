param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
# Keep FuseSoC's work tree on the same Windows drive as all source cores.
# Python's relpath cannot combine C: temporary paths with a D: project.
$buildRoot = Join-Path $ProjectRoot 'build'
$workRoot = Join-Path $buildRoot ("sim_ibex_" + [guid]::NewGuid().ToString('N'))
$testPassed = $false

if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot 'third_party\ibex\ibex_top.core'))) {
  throw "Vendored Ibex source is missing from third_party/ibex"
}

& fusesoc --cores-root $ProjectRoot run `
  --target=sim_ibex_soc --tool=modelsim --work-root $workRoot `
  --setup local:ibex:mesh_soc:2.0
if ($LASTEXITCODE -ne 0) { throw "FuseSoC setup failed with exit code $LASTEXITCODE" }

Push-Location $workRoot
try {
  # Edalize normally invokes these commands through make. Calling the
  # generated Tcl directly also works on Windows installations without make.
  & vsim -c -do 'do edalize_main.tcl; exit'
  if ($LASTEXITCODE -ne 0) { throw "Ibex/SoC compilation failed with exit code $LASTEXITCODE" }

  & vsim -c work.tb_ibex_soc_smoke -do 'run -all; quit -f'
  if ($LASTEXITCODE -ne 0) { throw "Ibex/SoC smoke test failed with exit code $LASTEXITCODE" }
  $testPassed = $true
} finally {
  Pop-Location
  if ($testPassed -and (Test-Path -LiteralPath $workRoot)) {
    $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    $workPath = (Resolve-Path -LiteralPath $workRoot).Path
    if (!$workPath.StartsWith($projectPath + '\build\', [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove build path outside the project: $workPath"
    }
    Remove-Item -LiteralPath $workPath -Recurse -Force
    if ((Test-Path -LiteralPath $buildRoot) -and
        !(Get-ChildItem -LiteralPath $buildRoot -Force | Select-Object -First 1)) {
      Remove-Item -LiteralPath $buildRoot -Force
    }
  }
}
