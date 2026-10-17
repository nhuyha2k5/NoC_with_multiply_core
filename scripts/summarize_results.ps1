param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot),[string]$RunTag='')
$ErrorActionPreference='Stop'
if($RunTag -and $RunTag -notmatch '^[A-Za-z0-9_-]+$'){throw 'RunTag must contain only letters, digits, underscore, or hyphen.'}
$runDir=if($RunTag){"build/baseline_$RunTag"}else{'build/baseline'}
$rows=Import-Csv (Join-Path $ProjectRoot "$runDir/summary.csv")
if($rows.Count -ne 240){throw "Expected 240 VC rows / 120 configs, got $($rows.Count)"}
$names=@('uniform','hotspot','complement','transpose','neighbor')
$md=[Collections.Generic.List[string]]::new()
$md.Add('# Raw NoC baseline: measured results')
$md.Add('')
$md.Add('Three seeds per configuration; averages over seeds, not a worst-case guarantee. Fixed 3000-cycle measurement after 500-cycle warmup; drain excluded from throughput. Packet size 3 flits on either VC. Latency is head-injection to tail-reception; source queue delay is separate.')
if($rows[0].PSObject.Properties['qos_mode'] -and $rows[0].PSObject.Properties['qos_classes']){
  $modes=@($rows|Select-Object -ExpandProperty qos_mode -Unique)
  $classes=@($rows|Select-Object -ExpandProperty qos_classes -Unique)
  if($modes.Count -eq 1 -and $classes.Count -eq 1){$md.Add("Router policy: mode $($modes[0]), class-priority $($classes[0]). For the neutral baseline class-priority should be 0 because packet ID occupies header bits [2:1].")}
}
$md.Add('')
$md.Add('| Pattern | Offered packets/source/cycle | Sink block % | RX flits/node/cycle | VC0 mean / p99 cycles | VC1 mean / p99 cycles | FIFO mean / max | Source queue delay VC0 / VC1 |')
$md.Add('|---|---|---|---|---|---|---|---|')
function Average($set,$column){return ($set|ForEach-Object{[double]$_.$column}|Measure-Object -Average).Average}
for($p=0;$p -lt 5;$p++){foreach($rate in @(2,10,20,30)){foreach($stall in @(0,50)){
  $v0=@($rows|Where-Object{[int]$_.pattern -eq $p -and [int]$_.rate_pct -eq $rate -and [int]$_.stall_pct -eq $stall -and $_.vc -eq '0'})
  $v1=@($rows|Where-Object{[int]$_.pattern -eq $p -and [int]$_.rate_pct -eq $rate -and [int]$_.stall_pct -eq $stall -and $_.vc -eq '1'})
  if($v0.Count -ne 3 -or $v1.Count -ne 3){throw 'Missing seeds'}
  $md.Add(('| {0} | {1:F2} | {2} | {3:F4} | {4:F2} / {5:F1} | {6:F2} / {7:F1} | {8:F3} / {9} | {10:F2} / {11:F2} |' -f $names[$p],($rate/100.0),$stall,(Average $v0 'flits_per_node_cycle'),(Average $v0 'avg_latency'),(Average $v0 'p99_latency'),(Average $v1 'avg_latency'),(Average $v1 'p99_latency'),(Average $v0 'avg_fifo_occupancy'),(($v0|ForEach-Object{[int]$_.max_fifo_occupancy}|Measure-Object -Maximum).Maximum),(Average $v0 'avg_source_queue_delay'),(Average $v1 'avg_source_queue_delay')))
}}}
$md.Add('')
$md.Add("Throughput columns are whole-network totals normalized by 9 nodes, repeated in each VC CSV row. Do not sum the two VC rows. p99 columns above are averages of each seed p99, not a percentile of pooled samples. Raw per-seed measurements are in $runDir/summary.csv.")
$md.Add('')
$md.Add('Hotspot interpretation: all nine sources target one local sink. That sink accepts at most one flit/cycle, so 3-flit packets cap total throughput at 1/3 packet/cycle (0.1111 RX flits/node/cycle). Offered rate 0.10 packets/source/cycle already exceeds this physical limit; large source-queue delay is expected saturation, not evidence of packet loss. Every offered packet is still checked and drained after the measurement window.')
$report=Join-Path $ProjectRoot $(if($RunTag){"docs/baseline_results_$RunTag.md"}else{'docs/baseline_results.md'})
[IO.File]::WriteAllLines($report,$md,[Text.UTF8Encoding]::new($false))
Write-Host "BASELINE_REPORT_PASS: $report"
