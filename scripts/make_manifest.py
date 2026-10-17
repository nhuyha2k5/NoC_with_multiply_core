"""Write a reproducibility manifest: SHA-256 of every source file plus tool versions.

Usage: python scripts/make_manifest.py <output.txt>
Hashes rtl/, tb/, sw/*.{c,h,S,ld}, scripts/, constraints/ and the FuseSoC core
file, so a result folder can be tied to the exact sources that produced it.
"""
import hashlib
import pathlib
import subprocess
import sys
import datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
PATTERNS = ["rtl/**/*.sv", "tb/**/*.sv", "sw/*.c", "sw/*.h", "sw/*.S", "sw/*.ld",
            "scripts/*", "constraints/*", "ibex_mesh_soc.core"]
TOOLS = [
    ("questa", ["vsim", "-version"]),
    ("vivado", ["cmd", "/c", "vivado", "-version"]),
    ("riscv-gcc", ["D:/xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe", "--version"]),
    ("fusesoc", ["fusesoc", "--version"]),
]


def tool_version(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        lines = [l.strip() for l in (out.stdout + out.stderr).splitlines() if l.strip()]
        return lines[0] if lines else "unknown"
    except (OSError, subprocess.SubprocessError) as exc:
        return "unavailable (%s)" % exc.__class__.__name__


def main():
    out = pathlib.Path(sys.argv[1])
    files = sorted({p for pat in PATTERNS for p in ROOT.glob(pat) if p.is_file()})
    digest_all = hashlib.sha256()
    lines = []
    for p in files:
        h = hashlib.sha256(p.read_bytes()).hexdigest()
        rel = p.relative_to(ROOT).as_posix()
        digest_all.update((rel + h).encode())
        lines.append("%s  %s" % (h, rel))
    with out.open("w", encoding="utf-8") as fh:
        fh.write("generated=%s\n" % datetime.datetime.now().isoformat(timespec="seconds"))
        fh.write("source_tree_sha256=%s\n" % digest_all.hexdigest())
        for name, cmd in TOOLS:
            fh.write("tool.%s=%s\n" % (name, tool_version(cmd)))
        fh.write("files=%d\n\n" % len(files))
        fh.write("\n".join(lines) + "\n")
    print("MANIFEST %s files=%d tree=%s" % (out, len(files), digest_all.hexdigest()[:16]))


if __name__ == "__main__":
    main()
