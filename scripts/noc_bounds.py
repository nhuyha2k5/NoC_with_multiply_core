"""Analytical bounds for the 3x3 XY mesh and comparison with measured runs.

For each synthetic pattern of tb/performance/tb_noc_baseline.sv this script
computes, per unit injection rate (1 flit/node/cycle):
  * the load of every channel (injection, ejection and the 24 directed
    inter-router links) under deterministic XY routing;
  * the ideal saturation throughput theta* = 1 / max channel load (capped at
    1 by the injection port);
  * the mean hop count H.
It then reads the benchmark summary CSV and reports
  * zero-load latency (rate 2 %, no sink stall) against H, with a least-squares
    fit T0 = a + b*H (b = cycles per hop);
  * accepted throughput at the highest offered load against the max-min fair
    allocation of that offered load (water-filling: every flow grows at the
    same rate until a channel of capacity 1 flit/cycle saturates). With
    independent source queues this is the ideal a fair router can reach; it
    can exceed theta* because flows that avoid the bottleneck keep going.

Usage: python scripts/noc_bounds.py build/baseline_<tag>/summary.csv [out.csv]
Node id = x*3 + y (x = column), as in the testbench and the SoC.
"""
import csv
import sys
from collections import defaultdict

K = 3
NODES = K * K
PACKET_FLITS = 3
PATTERNS = {0: "uniform", 1: "hotspot", 2: "complement", 3: "transpose", 4: "neighbor"}


def coord(n):
    return n // K, n % K


def node(x, y):
    return x * K + y


def destinations(pattern, s):
    """Destination distribution P(d | s) exactly as choose_destination()."""
    if pattern == 0:
        return {d: 1.0 / (NODES - 1) for d in range(NODES) if d != s}
    if pattern == 1:
        return {4: 1.0}
    if pattern == 2:
        return {8 - s: 1.0}
    if pattern == 3:
        return {(s % 3) * 3 + s // 3: 1.0}
    if pattern == 4:
        return {(s + 1) % NODES: 1.0}
    raise ValueError(pattern)


def xy_links(s, d):
    """Directed inter-router links visited by an XY route from s to d."""
    (x, y), (dx, dy) = coord(s), coord(d)
    links = []
    while x != dx:
        nx = x + (1 if dx > x else -1)
        links.append((node(x, y), node(nx, y)))
        x = nx
    while y != dy:
        ny = y + (1 if dy > y else -1)
        links.append((node(x, y), node(x, ny)))
        y = ny
    return links


def analyse(pattern):
    load = defaultdict(float)
    hops = 0.0
    for s in range(NODES):
        load[("inj", s)] += 1.0
        for d, p in destinations(pattern, s).items():
            load[("ej", d)] += p
            route = xy_links(s, d)
            hops += p * len(route)
            for link in route:
                load[("link",) + link] += p
    worst = max(load.items(), key=lambda kv: kv[1])
    theta = min(1.0, 1.0 / worst[1])
    max_link = max((v for k, v in load.items() if k[0] == "link"), default=0.0)
    return {
        "pattern": PATTERNS[pattern],
        "mean_hops": hops / NODES,
        "max_channel_load": worst[1],
        "bottleneck": worst[0],
        "max_link_load": max_link,
        "theta_ideal": theta,
    }


def channels(s, d):
    return [("inj", s), ("ej", d)] + [("link",) + l for l in xy_links(s, d)]


def maxmin_accepted(pattern, offered):
    """Max-min fair flit rate per node for a per-source offered load."""
    flows = {}
    for s in range(NODES):
        for d, p in destinations(pattern, s).items():
            flows[(s, d)] = {"demand": offered * p, "rate": 0.0, "chs": channels(s, d)}
    active = set(flows)
    used = defaultdict(float)
    while active:
        # Largest equal increment before a flow meets its demand or a
        # channel saturates.
        step = min(flows[f]["demand"] - flows[f]["rate"] for f in active)
        users = defaultdict(int)
        for f in active:
            for ch in flows[f]["chs"]:
                users[ch] += 1
        for ch, n in users.items():
            step = min(step, (1.0 - used[ch]) / n)
        for f in active:
            flows[f]["rate"] += step
            for ch in flows[f]["chs"]:
                used[ch] += step
        done = set()
        for f in active:
            if flows[f]["rate"] >= flows[f]["demand"] - 1e-12:
                done.add(f)
            elif any(used[ch] >= 1.0 - 1e-12 for ch in flows[f]["chs"]):
                done.add(f)
        active -= done
    return sum(f["rate"] for f in flows.values()) / NODES


def fmt_channel(ch):
    kind = ch[0]
    if kind == "link":
        return "link %d->%d" % (ch[1], ch[2])
    return "%s node %d" % ("ejection" if kind == "ej" else "injection", ch[1])


def load_measured(path):
    rows = defaultdict(list)
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            key = (int(r["pattern"]), int(r["rate_pct"]), int(r["stall_pct"]))
            rows[key].append(r)
    return rows


def mean(values):
    values = list(values)
    return sum(values) / len(values) if values else float("nan")


def main():
    bounds = {p: analyse(p) for p in PATTERNS}
    measured = load_measured(sys.argv[1]) if len(sys.argv) > 1 else {}
    out_rows = []
    zero_load = {}
    for p, b in bounds.items():
        row = dict(b)
        row["bottleneck"] = fmt_channel(b["bottleneck"])
        if measured:
            low = measured.get((p, 2, 0), [])
            # Weighted by samples so both VCs count by their completed packets.
            num = sum(float(r["avg_latency"]) * int(r["cohort_samples"]) for r in low)
            den = sum(int(r["cohort_samples"]) for r in low)
            zero_load[p] = num / den if den else float("nan")
            row["t0_measured"] = zero_load[p]
            rates = sorted({k[1] for k in measured if k[0] == p and k[2] == 0})
            top = rates[-1]
            # Throughput columns are global; take one row per seed (VC0).
            acc = mean(float(r["flits_per_node_cycle"]) for r in measured[(p, top, 0)] if r["vc"] == "0")
            offered = PACKET_FLITS * top / 100.0
            limit = maxmin_accepted(p, offered)
            row.update({"top_rate_pct": top, "offered_flits": offered, "accepted_flits": acc,
                        "bound_flits": limit, "efficiency": acc / limit,
                        "saturated": limit < offered - 1e-9 or acc < 0.97 * offered})
        out_rows.append(row)

    fit = None
    if measured:
        pts = [(bounds[p]["mean_hops"], zero_load[p]) for p in bounds if p != 1]
        n = len(pts)
        sx = sum(h for h, _ in pts); sy = sum(t for _, t in pts)
        sxx = sum(h * h for h, _ in pts); sxy = sum(h * t for h, t in pts)
        b = (n * sxy - sx * sy) / (n * sxx - sx * sx)
        a = (sy - b * sx) / n
        fit = (a, b)
        for row, p in zip(out_rows, bounds):
            row["t0_model"] = a + b * bounds[p]["mean_hops"]

    print("| Pattern | Mean hops | Bottleneck channel | Max channel load | Max link load | theta* (flit/node/cycle) |"
          + ( " Offered @top | Accepted | Max-min fair bound | Efficiency | T0 measured | T0 model |" if measured else ""))
    print("|---|---:|---|---:|---:|---:|" + ("---:|---:|---:|---:|---:|---:|" if measured else ""))
    for r in out_rows:
        line = "| %s | %.3f | %s | %.3f | %.3f | %.3f |" % (r["pattern"], r["mean_hops"], r["bottleneck"],
                                                          r["max_channel_load"], r["max_link_load"], r["theta_ideal"])
        if measured:
            line += " %.2f | %.4f | %.4f | %.1f%%%s | %.2f | %.2f |" % (
                r["offered_flits"], r["accepted_flits"], r["bound_flits"], 100 * r["efficiency"],
                "" if r["saturated"] else " (not saturated)", r["t0_measured"], r["t0_model"])
        print(line)
    if fit:
        print("\nZero-load fit (patterns without hotspot): T0 = %.2f + %.2f * H cycles" % fit)
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(out_rows[0].keys()))
            w.writeheader()
            w.writerows(out_rows)


if __name__ == "__main__":
    main()
