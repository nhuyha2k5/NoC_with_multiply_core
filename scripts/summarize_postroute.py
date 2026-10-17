"""Summarize a post-route report folder as Markdown.

Usage: python scripts/summarize_postroute.py reports/post_route_<tag>_<hz>

Reads result.txt, utilization_route.rpt, utilization_hier_route.rpt and
critical_paths.rpt (written by scripts/vivado_post_route.tcl) and prints:
  * timing/DRC summary,
  * whole-design resources,
  * resource breakdown by block (routers, network interfaces, caches, CPUs,
    memories, peripherals), with the per-router average,
  * the worst setup paths (source -> destination, levels, slack).
"""
import pathlib
import re
import sys
from collections import OrderedDict, defaultdict


def read_result(folder):
    out = {}
    path = folder / "result.txt"
    if path.exists():
        for line in path.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    return out


def flat_utilization(folder):
    text = (folder / "utilization_route.rpt").read_text(errors="ignore")
    keys = OrderedDict([("Slice LUTs", None), ("Slice Registers", None),
                        ("Block RAM Tile", None), ("DSPs", None)])
    for key in keys:
        m = re.search(r"^\|\s*%s\s*\|\s*([\d.]+)\s*\|.*?\|\s*([\d.]+)\s*\|\s*([\d.<]+)\s*\|\s*$" % re.escape(key),
                      text, re.M)
        if m:
            keys[key] = (m.group(1), m.group(2), m.group(3))
    return keys


def hier_rows(folder):
    """Rows of the hierarchical utilization table: (depth, instance, module, cols)."""
    path = folder / "utilization_hier_route.rpt"
    if not path.exists():
        return [], []
    rows, header = [], []
    for line in path.read_text(errors="ignore").splitlines():
        if not line.startswith("|"):
            continue
        cells = line.split("|")[1:-1]
        if not cells:
            continue
        if cells[0].strip() == "Instance":
            header = [c.strip() for c in cells]
            continue
        if not header or len(cells) != len(header):
            continue
        name = cells[0]
        depth = (len(name) - len(name.lstrip(" "))) // 2
        inst = name.strip()
        module = cells[1].strip()
        vals = {}
        for h, c in zip(header[2:], cells[2:]):
            c = c.strip()
            try:
                vals[h] = float(c)
            except ValueError:
                vals[h] = 0.0
        rows.append((depth, inst, module, vals))
    return rows, header


CATEGORIES = [
    ("Router (router_vc)", lambda inst, mod: mod.startswith("router_vc")),
    ("NI initiator AXI-Lite (axi_lite_to_mesh)", lambda inst, mod: mod.startswith("axi_lite_to_mesh")),
    ("NI target AXI-Lite (mesh_to_axi_lite)", lambda inst, mod: mod.startswith("mesh_to_axi_lite")),
    ("NI memory (mesh_to_axi4)", lambda inst, mod: mod.startswith("mesh_to_axi4")),
    ("NI burst initiator (axi4_to_mesh)", lambda inst, mod: mod.startswith("axi4_to_mesh")),
    ("MESI D-cache", lambda inst, mod: mod.startswith("mesi_dcache")),
    ("Coherence manager", lambda inst, mod: mod.startswith("coherence_manager")),
    ("Ibex core (ibex_top)", lambda inst, mod: mod.startswith("ibex_top")),
    ("Boot ROM", lambda inst, mod: mod.startswith("boot_rom")),
    ("Shared RAM (axi4_banked_ram)", lambda inst, mod: mod.startswith("axi4_banked_ram")),
    ("PLIC", lambda inst, mod: mod.startswith("plic_core")),
    ("Timer/IPI", lambda inst, mod: mod.startswith("timer_ipi")),
    ("NoC control/counters", lambda inst, mod: mod.startswith("noc_control")),
    ("DMA engine", lambda inst, mod: mod.startswith("axi4_dma") or mod.startswith("axi_lite_dma")),
    ("Matrix accelerator", lambda inst, mod: mod.startswith("axi_lite_matrix")),
    ("UART/GPIO/mailbox", lambda inst, mod: mod.startswith(("axi_lite_uart", "axi_lite_gpio", "axi_lite_mailbox"))),
]


def breakdown(rows):
    totals = OrderedDict((name, defaultdict(float)) for name, _ in CATEGORIES)
    counts = defaultdict(int)
    claimed_depth = None  # depth of the innermost counted ancestor
    for depth, inst, mod, vals in rows:
        # "(inst)" rows repeat the parent's own leaf logic; skip them, and do
        # not count descendants of an instance that is already counted.
        if inst.startswith("("):
            continue
        if claimed_depth is not None and depth > claimed_depth:
            continue
        claimed_depth = None
        for name, match in CATEGORIES:
            if match(inst, mod):
                counts[name] += 1
                for k, v in vals.items():
                    totals[name][k] += v
                claimed_depth = depth
                break
    return totals, counts


def critical_paths(folder, limit=8):
    path = folder / "critical_paths.rpt"
    if not path.exists():
        return []
    text = path.read_text(errors="ignore")
    out = []
    for block in text.split("Slack (")[1:limit + 1]:
        slack = re.match(r"\s*(?:MET|VIOLATED)\)\s*:\s*(-?[\d.]+)ns", block)
        src = re.search(r"Source:\s+(\S+)", block)
        dst = re.search(r"Destination:\s+(\S+)", block)
        lv = re.search(r"Logic Levels:\s+(\d+)", block)
        dp = re.search(r"Data Path Delay:\s+([\d.]+)ns\s+\(logic ([\d.]+)ns.*?route ([\d.]+)ns", block)
        if slack and src and dst:
            out.append((slack.group(1), lv.group(1) if lv else "?", dp.groups() if dp else ("?", "?", "?"),
                        src.group(1), dst.group(1)))
    return out


def main():
    folder = pathlib.Path(sys.argv[1])
    res = read_result(folder)
    print("### Timing và DRC\n")
    for k in ("clock_hz", "setup_slack_ns", "hold_slack_ns", "critical_drc", "reqp_1839", "drc_warnings"):
        if k in res:
            print("- %s = %s" % (k, res[k]))
    print("\n### Tài nguyên toàn thiết kế\n")
    print("| Tài nguyên | Dùng | Có sẵn | % |\n|---|---:|---:|---:|")
    for k, v in flat_utilization(folder).items():
        if v:
            print("| %s | %s | %s | %s |" % (k, v[0], v[1], v[2]))
    rows, header = hier_rows(folder)
    if rows:
        totals, counts = breakdown(rows)
        cols = [c for c in ("Total LUTs", "FFs", "RAMB36", "RAMB18", "DSP Blocks", "DSP48 Blocks") if c in header]
        print("\n### Tài nguyên theo khối\n")
        print("| Khối | Số instance | " + " | ".join(cols) + " |")
        print("|---|---:|" + "---:|" * len(cols))
        for name, vals in totals.items():
            if counts[name]:
                print("| %s | %d | %s |" % (name, counts[name], " | ".join("%.0f" % vals.get(c, 0) for c in cols)))
        r = totals["Router (router_vc)"]
        n = counts["Router (router_vc)"]
        if n:
            print("\nTrung bình một router: %.0f LUT, %.0f FF." % (r.get("Total LUTs", 0) / n, r.get("FFs", 0) / n))
    print("\n### Đường setup xấu nhất\n")
    print("| Slack (ns) | Logic levels | Delay (logic/route) | Từ | Đến |\n|---:|---:|---|---|---|")
    for slack, lv, dp, src, dst in critical_paths(folder):
        print("| %s | %s | %s (%s/%s) | `%s` | `%s` |" % (slack, lv, dp[0], dp[1], dp[2], src, dst))


if __name__ == "__main__":
    main()
