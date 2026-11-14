#!/usr/bin/env python3
"""
===============================================================================
Script: run_regression.py
Description: Automated ASIC Verification Regression Runner for Parameterized
             Asynchronous FIFO (SystemVerilog).
Author: Senior ASIC Design & Verification Engineer
Features:
  - Compiles RTL and Testbench using Icarus Verilog (iverilog -g2012 -Wall)
  - Executes 4 directed tests and 10 randomized seeds (+SEED=1..10)
  - Regex parses simulation logs for pass/fail, transaction, and assertion metrics
  - Generates an executive regression report table with ANSI color coding
===============================================================================
"""

import sys
import os
import subprocess
import time
import re
from pathlib import Path

# Terminal ANSI Color Codes
CLR_RESET  = "\033[0m"
CLR_BOLD   = "\033[1m"
CLR_RED    = "\033[91m"
CLR_GREEN  = "\033[92m"
CLR_YELLOW = "\033[93m"
CLR_CYAN   = "\033[96m"
CLR_GRAY   = "\033[90m"

# Project Paths
ROOT_DIR = Path(__file__).resolve().parent.parent
RTL_DIR  = ROOT_DIR / "rtl"
TB_DIR   = ROOT_DIR / "tb"
SIM_DIR  = ROOT_DIR / "sim"
VVP_OUT  = SIM_DIR / "sim_tb.vvp"

RTL_FILES = [
    RTL_DIR / "fifomem.sv",
    RTL_DIR / "sync_r2w.sv",
    RTL_DIR / "sync_w2r.sv",
    RTL_DIR / "wptr_full.sv",
    RTL_DIR / "rptr_empty.sv",
    RTL_DIR / "async_fifo.sv",
]
TB_FILES = [
    TB_DIR / "tb_async_fifo.sv",
]

TEST_SUITE = [
    # Directed Tests
    {"name": "TEST_FULL_EMPTY",   "seed": 0,  "type": "Directed",   "dump": 1},
    {"name": "TEST_FAST_WRITE",   "seed": 0,  "type": "Directed",   "dump": 1},
    {"name": "TEST_FAST_READ",    "seed": 0,  "type": "Directed",   "dump": 1},
    {"name": "TEST_RANDOM_RESET", "seed": 0,  "type": "Directed",   "dump": 1},
    # Randomized Seeds
    {"name": "TEST_RANDOM", "seed": 1,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 2,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 3,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 4,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 5,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 6,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 7,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 8,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 9,  "type": "Randomized", "dump": 0},
    {"name": "TEST_RANDOM", "seed": 10, "type": "Randomized", "dump": 0},
]


def print_banner(title: str):
    width = 80
    print(f"\n{CLR_CYAN}{'=' * width}")
    print(f"   {title.center(width - 6)}")
    print(f"{'=' * width}{CLR_RESET}\n")


def compile_design() -> bool:
    """Compiles RTL and Testbench using iverilog."""
    print(f"{CLR_BOLD}[INFO] Step 1: Compiling RTL & Testbench using Icarus Verilog (-g2012)...{CLR_RESET}")
    SIM_DIR.mkdir(parents=True, exist_ok=True)

    cmd = [
        "iverilog",
        "-g2012",
        "-Wall",
        "-s", "tb_async_fifo",
        "-o", str(VVP_OUT),
        *[str(f) for f in RTL_FILES],
        *[str(f) for f in TB_FILES],
    ]

    start_time = time.time()
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    except FileNotFoundError:
        print(f"{CLR_RED}[ERROR] 'iverilog' not found in system PATH! Please install or add to PATH.{CLR_RESET}")
        return False

    elapsed = time.time() - start_time
    if proc.returncode != 0:
        print(f"{CLR_RED}[FAIL] Compilation failed with code {proc.returncode}:{CLR_RESET}")
        print(proc.stderr)
        return False

    if proc.stderr.strip():
        print(f"{CLR_YELLOW}[WARNINGS during compilation]:\n{proc.stderr}{CLR_RESET}")
    else:
        print(f"{CLR_GREEN}[PASS] Compilation completed with zero warnings ({elapsed:.2f}s).{CLR_RESET}\n")

    return True


def run_single_test(test_idx: int, test_cfg: dict) -> dict:
    """Runs a single simulation and parses the log."""
    name = test_cfg["name"]
    seed = test_cfg["seed"]
    dump = test_cfg["dump"]

    args = [f"+TESTNAME={name}"]
    if seed > 0:
        args.append(f"+SEED={seed}")
    args.append(f"+DUMP={dump}")

    cmd = ["vvp", str(VVP_OUT)] + args
    start_time = time.time()
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    duration = time.time() - start_time

    output = proc.stdout + proc.stderr
    log_file = SIM_DIR / f"{name}_s{seed}.log" if seed > 0 else SIM_DIR / f"{name}.log"
    with open(log_file, "w", encoding="utf-8") as f:
        f.write(output)

    # Parsing metrics
    passed = (proc.returncode == 0) and ("Status                           : [PASS]" in output or "STATUS: PASS" in output or "PASSED" in output)
    fatal_found = ("$fatal" in output or "FATAL:" in output or "ASSERTION FAILED" in output or "MISMATCH" in output)
    if fatal_found:
        passed = False

    writes_m = re.search(r"Total Successful Writes Verified\s*:\s*(\d+)", output)
    reads_m  = re.search(r"Total Successful Reads Verified\s*:\s*(\d+)", output)
    assert_m = re.search(r"Safety Assertions Verified\s*:\s*(\d+)", output)
    checks_m = re.search(r"Data Integrity Checks Passed\s*:\s*(\d+)", output)

    writes = int(writes_m.group(1)) if writes_m else 0
    reads  = int(reads_m.group(1))  if reads_m  else 0
    assertions = int(assert_m.group(1)) if assert_m else 0
    checks = int(checks_m.group(1)) if checks_m else 0

    return {
        "index": test_idx,
        "name": name,
        "seed": seed,
        "type": test_cfg["type"],
        "passed": passed,
        "writes": writes,
        "reads": reads,
        "checks": checks,
        "assertions": assertions,
        "duration": duration,
        "log": log_file.name,
    }


def main():
    print_banner("ASIC VERIFICATION REGRESSION: PARAMETERIZED ASYNC FIFO")
    print(f"Design Directory: {ROOT_DIR}")
    print(f"Simulator Target: Icarus Verilog 11.0 (IEEE 1800-2012)")
    print(f"Regression Tests: {len(TEST_SUITE)} (4 Directed + 10 Multi-Seed Random)\n")

    if not compile_design():
        sys.exit(1)

    print(f"{CLR_BOLD}[INFO] Step 2: Executing Test Suite...{CLR_RESET}\n")
    results = []
    total_start = time.time()

    for idx, test_cfg in enumerate(TEST_SUITE, start=1):
        test_display = f"{test_cfg['name']}" + (f" (Seed {test_cfg['seed']})" if test_cfg['seed'] > 0 else "")
        print(f"  [{idx:2d}/{len(TEST_SUITE)}] Running {test_display:<32} ... ", end="", flush=True)

        res = run_single_test(idx, test_cfg)
        results.append(res)

        if res["passed"]:
            print(f"{CLR_GREEN}[PASS]{CLR_RESET} ({res['duration']:.2f}s, {res['assertions']} assertions)")
        else:
            print(f"{CLR_RED}[FAIL]{CLR_RESET} (Check log: sim/{res['log']})")

    total_duration = time.time() - total_start

    # Summary Table
    print_banner("REGRESSION RESULTS SUMMARY")
    header = f"{'#':<3} | {'Test Name':<18} | {'Type':<10} | {'Seed':<5} | {'Writes':<7} | {'Reads':<7} | {'Assertions':<11} | {'Time':<7} | {'Status':<6}"
    sep = "-" * len(header)
    print(f"{CLR_BOLD}{header}")
    print(sep + CLR_RESET)

    total_writes = 0
    total_reads = 0
    total_assertions = 0
    all_passed = True

    for r in results:
        status_str = f"{CLR_GREEN}PASS{CLR_RESET}" if r["passed"] else f"{CLR_RED}FAIL{CLR_RESET}"
        if not r["passed"]:
            all_passed = False
        total_writes += r["writes"]
        total_reads += r["reads"]
        total_assertions += r["assertions"]

        seed_str = str(r["seed"]) if r["seed"] > 0 else "-"
        print(f"{r['index']:<3} | {r['name']:<18} | {r['type']:<10} | {seed_str:<5} | {r['writes']:<7} | {r['reads']:<7} | {r['assertions']:<11} | {r['duration']:<6.2f}s | {status_str}")

    print(sep)
    totals_line = f"{'TOT':<3} | {'14 Tests':<18} | {'All':<10} | {'-':<5} | {total_writes:<7} | {total_reads:<7} | {total_assertions:<11} | {total_duration:<6.2f}s | "
    if all_passed:
        totals_line += f"{CLR_GREEN}{CLR_BOLD}100% PASS{CLR_RESET}"
    else:
        totals_line += f"{CLR_RED}{CLR_BOLD}FAILED{CLR_RESET}"
    print(totals_line)
    print(f"{CLR_BOLD}{sep}{CLR_RESET}\n")

    print(f"Artifacts Generated:")
    print(f"  - Simulation Waves : {SIM_DIR / 'waves.vcd'}")
    print(f"  - Regression Logs  : {SIM_DIR}/*.log\n")

    if all_passed:
        print(f"{CLR_GREEN}{CLR_BOLD}>>> ALL 14 REGRESSION TESTS PASSED CLEANLY! <<<{CLR_RESET}\n")
        sys.exit(0)
    else:
        print(f"{CLR_RED}{CLR_BOLD}>>> REGRESSION FAILED. REVIEW LOGS IN sim/ <<<{CLR_RESET}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
