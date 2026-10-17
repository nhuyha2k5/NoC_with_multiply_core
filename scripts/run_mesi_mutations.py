"""Mutation testing for the MESI cache/coherence testbench.

Usage: python scripts/run_mesi_mutations.py [out_dir] [M1,M2,...]

Each mutation copies one RTL file, applies a single textual change (the
original text must match exactly once), recompiles a testbench environment
with the mutated copy and runs it. Two environments exist: "2core"
(tb_mesi_coherence, coherence_manager_2core wrapper) and "4core"
(tb_mesi_coherence_4core, coherence_manager with N_CORES=4). Each mutation
lists the environments that must detect it and the expected message in each.
A mutation is "killed" only if every listed run fails AND its log contains the
expected detection message, so a run that fails for an unrelated reason
(compile error, timeout) is reported as an error rather than counted as
detection. The unmutated design must PASS in every environment first. Exit
status is non-zero if any mutation survives or errors.
"""
import pathlib
import shutil
import subprocess
import sys
import datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMMON = [
    "rtl/router/router_pkg.sv", "rtl/router/vc_fifo.sv", "rtl/router/input_port_vc.sv",
    "rtl/router/packet_arbiter.sv", "rtl/router/router_vc.sv", "rtl/mesh_3x3/mesh_3x3_vc.sv",
    "rtl/cache/coherence_pkg.sv", "rtl/network_interface/axi_lite_if.sv",
    "rtl/network_interface/coherence_if.sv", "rtl/network_interface/axi_lite_to_mesh.sv",
    "rtl/network_interface/mesh_to_axi_lite.sv", "rtl/cache/coherence_manager.sv",
]
ENVS = {
    "2core": ("tb_mesi_coherence", COMMON + [
        "rtl/cache/coherence_manager_2core.sv", "rtl/cache/mesi_dcache.sv",
        "rtl/ip_core/axi_lite_ram.sv", "tb/tb_mesi_coherence.sv"]),
    "4core": ("tb_mesi_coherence_4core", COMMON + [
        "rtl/cache/mesi_dcache.sv", "rtl/ip_core/axi_lite_ram.sv",
        "tb/tb_mesi_coherence_4core.sv"]),
}
CACHE = "rtl/cache/mesi_dcache.sv"
MANAGER = "rtl/cache/coherence_manager.sv"
CONFLICT = "if (d != c && inflight_q[d] && inflight_addr_q[d] == req_addr_i[c][31:2])"

# (id, description, file, original text, mutated text, {env: expected detection message})
MUTATIONS = [
    ("M1", "snoop invalidate leaves the line Shared", CACHE,
     "line_state_q[snoop_index] <= MESI_INVALID;", "line_state_q[snoop_index] <= MESI_SHARED;",
     {"2core": "MESI duplicate exclusive/dirty ownership",
      "4core": "MESI duplicate exclusive/dirty ownership"}),
    ("M2", "pending UPGRADE not converted to GETM after invalidation", CACHE,
     "addr_q[31:2]==snoop_addr_q[31:2])req_cmd_q<=COH_GETM;",
     "addr_q[31:2]==snoop_addr_q[31:2])req_cmd_q<=COH_UPGRADE;",
     {"2core": "Concurrent MESI byte stores lost data",
      "4core": "Concurrent MESI byte stores lost data"}),
    ("M3", "dirty snoop acknowledged without write-back", CACHE,
     "snoop_state_d = snoop_needs_wb ? S_WB_SEND : S_APPLY;", "snoop_state_d = S_APPLY;",
     {"2core": "MESI shared copies differ", "4core": "MESI shared copies differ"}),
    ("M4", "no guard for snoop apply vs fill on the same index", CACHE,
     "!(main_install && cpu_index == snoop_index);", "1'b1;",
     {"2core": "lost its own store", "4core": "lost its own store"}),
    # Retargeted from the original 2-core manager (same fault: core 0 ignores
    # another core's in-flight transaction on the same word).
    ("M5", "manager ignores in-flight same-word conflict for core 0", MANAGER,
     CONFLICT, CONFLICT.replace("if (d != c", "if (c != 0 && d != c"),
     {"2core": "MESI snoop overlaps the in-flight miss address",
      "4core": "MESI snoop overlaps the in-flight miss address"}),
    ("M6", "dirty snoop allowed while the cache owns the NoC port", CACHE,
     "(!snoop_needs_wb || (!main_axi_active && main_state_q != M_COH_APPLY));", "1'b1;",
     {"2core": "MESI cache attempted two AXI operations at once",
      "4core": "MESI cache attempted two AXI operations at once"}),
    ("M7", "no tag re-check when applying a snoop", CACHE,
     "assign snoop_apply = (snoop_state_q == S_APPLY) && snoop_line_hit &&",
     "assign snoop_apply = (snoop_state_q == S_APPLY) && snoop_hit_q &&",
     {"2core": "lost its own store", "4core": "lost its own store"}),
    # Step 1 (shared data write port / shared accept index).
    ("M8", "upgrade merge reads the accept index instead of the line index", CACHE,
     "data_wdata = merge_bytes(data_q[cpu_index], wdata_q, wstrb_q);",
     "data_wdata = merge_bytes(accept_data, wdata_q, wstrb_q);",
     # Needs AXI payloads scrambled after handshake (both tbs do this);
     # otherwise the stale AWADDR equals the line address and the bug is masked.
     # In the 4-core tb the reference-model transfer check reports the
     # corrupted word before the SWMR data comparison does.
     {"2core": "MESI shared copies differ", "4core": "MESI random reference mismatch"}),
    ("M9", "accept index selects the wrong channel", CACHE,
     "assign accept_is_read  = s_axi.arvalid &&", "assign accept_is_read  = !s_axi.arvalid &&",
     {"2core": "MESI accept index not on AR for a read accept",
      "4core": "MESI accept index not on AR for a read accept"}),
    ("M10", "fill writes the data array on an error response", CACHE,
     "assign data_we_fill = (main_state_q == M_MEM_READ_DATA) && m_axi.rvalid && m_axi.rready &&\n"
     "                        cacheable(addr_q) && (m_axi.rresp == 2'b00);",
     "assign data_we_fill = (main_state_q == M_MEM_READ_DATA) && m_axi.rvalid && m_axi.rready &&\n"
     "                        cacheable(addr_q);",
     # Only the 2-core tb injects fill errors. The per-cycle SWMR invariant
     # fires first (the two Shared copies diverge).
     {"2core": "MESI shared copies differ"}),
    # Step 2: N-peer manager. "2-core leftover" faults are only visible with
    # three or more caches, so they are checked in the 4-core environment.
    ("M11", "snoop fan-out limited to cores 0-1 (2-core leftover)", MANAGER,
     "pending_d = ~(N_CORES'(1) << pick);", "pending_d = ~(N_CORES'(1) << pick) & N_CORES'(3);",
     {"4core": "MESI snoop fan-out wrong"}),
    ("M12", "grant after the first peer ack instead of all", MANAGER,
     "if (pending_d == '0)", "if (acked != '0)",
     {"4core": "MESI snoop fan-out wrong"}),
    ("M13", "grant_shared ignores peers 2-3", MANAGER,
     "peer_hit_d = peer_hit_q | (|(acked & snoop_hit_i));",
     "peer_hit_d = peer_hit_q | (|(acked[1:0] & snoop_hit_i[1:0]));",
     {"4core": "MESI duplicate exclusive/dirty ownership"}),
    ("M14", "grant_err ignores peers 2-3", MANAGER,
     "peer_err_d = peer_err_q | (|(acked & snoop_err_i));",
     "peer_err_d = peer_err_q | (|(acked[1:0] & snoop_err_i[1:0]));",
     {"4core": "MESI duplicate exclusive/dirty ownership"}),
    ("M15", "in-flight conflict checked only against cores 0-1", MANAGER,
     CONFLICT, CONFLICT.replace("if (d != c", "if (d < 2 && d != c"),
     {"4core": "MESI snoop overlaps the in-flight miss address"}),
    ("M16", "fixed priority instead of round robin", MANAGER,
     "c = int'(rr_q) + k;", "c = k;",
     {"4core": "MESI manager bypassed an eligible requester"}),
    ("M17", "requester snooped together with its peers", MANAGER,
     "pending_d = ~(N_CORES'(1) << pick);", "pending_d = '1;",
     {"4core": "MESI manager snooped the requester itself"}),
    ("M18", "one completion clears every in-flight entry", MANAGER,
     "if (complete_i[c]) inflight_q[c] <= 1'b0;", "if (complete_i[c]) inflight_q <= '0;",
     {"4core": "MESI snoop overlaps the in-flight miss address"}),
]


def run(cmd, cwd, log, timeout):
    with open(log, "w", encoding="utf-8", errors="replace") as fh:
        try:
            proc = subprocess.run(cmd, cwd=cwd, stdout=fh, stderr=subprocess.STDOUT, timeout=timeout)
            return proc.returncode
        except subprocess.TimeoutExpired:
            fh.write("\nMUTATION_RUNNER_TIMEOUT\n")
            return -1


def simulate(workdir, top, sources):
    workdir.mkdir(parents=True, exist_ok=True)
    lib = workdir / "work"
    if lib.exists():
        shutil.rmtree(lib)
    run(["vlib", "work"], workdir, workdir / "vlib.log", 60)
    rc = run(["vlog", "-sv"] + [str(s) for s in sources], workdir, workdir / "compile.log", 600)
    if rc != 0:
        return "COMPILE_ERROR", ""
    run(["vsim", "-c", "work." + top, "-do", "run -all; quit -f"], workdir,
        workdir / "simulation.log", 1800)
    text = (workdir / "simulation.log").read_text(errors="replace")
    passed = "TEST_PASS:" in text and "** Fatal" not in text and "** Error" not in text
    return ("PASS" if passed else "FAIL"), text


def main():
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = (pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / ("mesi_mutations_" + stamp)).resolve()
    only = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else None
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for env, (top, sources) in ENVS.items():
        status, _ = simulate(out / ("M0_unmutated_" + env), top, [ROOT / s for s in sources])
        print("M0 unmutated design (%s): %s" % (env, status))
        if status != "PASS":
            print("MUTATION_RUN_ABORTED: unmutated design does not pass in " + env)
            return 2
    bad = 0
    for mid, desc, rel, old, new, expects in MUTATIONS:
        if only and mid not in only:
            continue
        text = (ROOT / rel).read_text(encoding="utf-8")
        count = text.count(old)
        details = []
        verdict = "KILLED"
        if count != 1:
            verdict, details = "ERROR", ["original text matched %d times" % count]
        else:
            for env, expect in expects.items():
                top, sources = ENVS[env]
                wdir = out / mid / env
                wdir.mkdir(parents=True, exist_ok=True)
                mutated = wdir / pathlib.Path(rel).name
                mutated.write_text(text.replace(old, new), encoding="utf-8")
                srcs = [mutated if s == rel else ROOT / s for s in sources]
                status, log = simulate(wdir, top, srcs)
                first = next((l.strip() for l in log.splitlines() if "** Fatal" in l or "** Error" in l), "")
                if status == "PASS":
                    v, d = "SURVIVED", "testbench still passes"
                elif status == "COMPILE_ERROR":
                    v, d = "ERROR", "mutated design does not compile"
                elif expect in log:
                    v, d = "KILLED", first
                else:
                    v, d = "ERROR", "failed without expected message: " + (first or "no message")
                details.append("%s: %s" % (env, d))
                if v != "KILLED" and verdict == "KILLED":
                    verdict = v
        if verdict != "KILLED":
            bad += 1
        rows.append((mid, desc, "+".join(expects), verdict, " | ".join(details)))
        print("%-4s %-8s %s | %s" % (mid, verdict, desc, " | ".join(details)))
    with open(out / "summary.csv", "w", encoding="utf-8") as fh:
        fh.write("id,description,environments,verdict,detection\n")
        for r in rows:
            fh.write("%s,\"%s\",%s,%s,\"%s\"\n" % (r[0], r[1], r[2], r[3], r[4].replace('"', "'")))
    killed = sum(1 for r in rows if r[3] == "KILLED")
    print("MUTATION_SUMMARY killed=%d/%d out=%s" % (killed, len(rows), out))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
