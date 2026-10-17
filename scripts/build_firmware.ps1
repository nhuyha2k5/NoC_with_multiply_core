param([string]$Toolchain='D:/xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64/xpack-riscv-none-elf-gcc-15.2.0-1/bin',
  [string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),[string]$OutputDir='')
$ErrorActionPreference='Stop'
$root=$ProjectRoot
$out=if($OutputDir){$OutputDir}else{Join-Path $root 'sw/build'}
New-Item -ItemType Directory -Force -Path $out|Out-Null
$gcc=Join-Path $Toolchain 'riscv-none-elf-gcc.exe'
$objcopy=Join-Path $Toolchain 'riscv-none-elf-objcopy.exe'
if(!(Test-Path -LiteralPath $gcc)){throw "RISC-V GCC missing: $gcc"}
for($hart=0;$hart -lt 4;$hart++){
  $elf=Join-Path $out "core$hart.elf"
  $bin=Join-Path $out "core$hart.bin"
  # Private 8 KiB data/stack region per hart in the upper half of the 128 KiB RAM.
  $origin='0x{0:x8}' -f (0x20010000 + $hart*0x2000)
  & $gcc -march=rv32imc_zicsr -mabi=ilp32 -O2 -ffreestanding -fno-builtin -fno-tree-loop-distribute-patterns -fno-jump-tables -msmall-data-limit=0 -nostdlib -nostartfiles "-DHART=$hart" "-Wl,--defsym=RAM_ORIGIN=$origin" "-Wl,-T,$root/sw/link.ld" "-Wl,-Map,$out/core$hart.map" "$root/sw/start.S" "$root/sw/demo.c" -o $elf
  if($LASTEXITCODE -ne 0){throw "Firmware core$hart compile failed"}
  & $objcopy -O binary $elf $bin
  if($LASTEXITCODE -ne 0){throw 'objcopy failed'}
  $bytes=[IO.File]::ReadAllBytes($bin)
  if($bytes.Length -gt 16384){throw 'Firmware exceeds 16 KiB ROM'}
  $lines=for($i=0;$i -lt 16384;$i+=4){
    if($i -lt $bytes.Length){
      $word=[uint32]0
      for($b=0;$b -lt 4;$b++){if($i+$b -lt $bytes.Length){$word=$word -bor ([uint32]$bytes[$i+$b] -shl ($b*8))}}
      $word.ToString('x8')
    }else{'00000013'}
  }
  [IO.File]::WriteAllLines((Join-Path $out "core$hart.mem"),[string[]]$lines,[Text.Encoding]::ASCII)
  Write-Host "FIRMWARE_BUILD_PASS hart=$hart bytes=$($bytes.Length)"
}
