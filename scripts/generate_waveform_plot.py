#!/usr/bin/env python3
"""
===============================================================================
Script: generate_waveform_plot.py
Description: Generates an executive dark-mode timing diagram PNG from VCD
             for GitHub repository documentation.
Author: Senior ASIC Design & Verification Engineer
===============================================================================
"""

import sys
import re
from pathlib import Path
import matplotlib.pyplot as plt
import matplotlib.patches as patches

ROOT_DIR = Path(__file__).resolve().parent.parent
VCD_FILE = ROOT_DIR / "sim" / "waves.vcd"
OUT_PNG  = ROOT_DIR / "docs" / "waveform.png"

def parse_vcd(vcd_path):
    sig_map = {}      # symbol -> name
    name_to_sym = {}  # name -> symbol
    
    # Target signals
    target_names = {
        "wclk": "wclk",
        "winc": "winc",
        "wdata": "wdata",
        "wfull": "wfull",
        "wptr": "wptr",
        "rclk": "rclk",
        "rinc": "rinc",
        "rdata": "rdata",
        "rempty": "rempty",
        "rptr": "rptr"
    }

    with open(vcd_path, "r", encoding="utf-8") as f:
        in_header = True
        for line in f:
            line = line.strip()
            if in_header:
                if line.startswith("$var"):
                    parts = line.split()
                    # format: $var wire/reg size symbol name [range] $end
                    if len(parts) >= 5:
                        size = int(parts[2])
                        sym = parts[3]
                        name = parts[4]
                        if name in target_names and name not in name_to_sym:
                            sig_map[sym] = {"name": name, "size": size}
                            name_to_sym[name] = sym
                elif line.startswith("$enddefinitions"):
                    in_header = False
                    break

    # Parse simulation data
    current_time = 0
    # records: name -> list of (time, val_int_or_str)
    history = {name: [] for name in target_names}
    current_vals = {name: 0 for name in target_names}

    with open(vcd_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                current_time = int(line[1:])
            elif line.startswith("$"):
                continue
            else:
                # Value change
                if line.startswith("b") or line.startswith("B"):
                    parts = line[1:].split()
                    if len(parts) == 2:
                        val_str, sym = parts
                        if sym in sig_map:
                            name = sig_map[sym]["name"]
                            try:
                                val_int = int(val_str, 2)
                            except ValueError:
                                val_int = 0
                            history[name].append((current_time, val_int))
                            current_vals[name] = val_int
                else:
                    val_char = line[0]
                    sym = line[1:]
                    if sym in sig_map:
                        name = sig_map[sym]["name"]
                        val_int = 1 if val_char == '1' else 0
                        history[name].append((current_time, val_int))
                        current_vals[name] = val_int

    return history

def plot_dark_waveform(history, out_path):
    OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    
    # We select time window covering writes to full and initial reads to empty
    # In TEST_FULL_EMPTY:
    # Reset settles at ~80ns (80,000 ps)
    # Writes occur ~90ns to ~420ns (wfull asserts at 420ns)
    # Overflow writes occur ~420ns to ~500ns
    # Reads start at ~510ns and drain to ~950ns
    t_start = 80000   # 80 ns
    t_end   = 1000000 # 1000 ns (1 us)
    time_scale = 1000.0 # Convert ps to ns

    # Signal display configuration
    signals = [
        {"name": "wclk",   "label": "WCLK (100MHz)",   "type": "1bit", "color": "#58a6ff", "domain": "Write Domain"},
        {"name": "winc",   "label": "WINC (Write Req)", "type": "1bit", "color": "#f0883e", "domain": "Write Domain"},
        {"name": "wdata",  "label": "WDATA [31:0]",     "type": "bus",  "color": "#79c0ff", "domain": "Write Domain"},
        {"name": "wptr",   "label": "WPTR [4:0] Gray",  "type": "bus",  "color": "#d2a8ff", "domain": "Write Domain"},
        {"name": "wfull",  "label": "WFULL (Flag)",     "type": "1bit", "color": "#ff7b72", "domain": "Write Domain"},
        {"name": "rclk",   "label": "RCLK (73MHz)",    "type": "1bit", "color": "#3fb950", "domain": "Read Domain"},
        {"name": "rinc",   "label": "RINC (Read Req)",  "type": "1bit", "color": "#f0883e", "domain": "Read Domain"},
        {"name": "rdata",  "label": "RDATA [31:0]",     "type": "bus",  "color": "#56d364", "domain": "Read Domain"},
        {"name": "rptr",   "label": "RPTR [4:0] Gray",  "type": "bus",  "color": "#bc8cff", "domain": "Read Domain"},
        {"name": "rempty", "label": "REMPTY (Flag)",    "type": "1bit", "color": "#e3b341", "domain": "Read Domain"},
    ]

    fig, ax = plt.subplots(figsize=(18, 11), dpi=220)
    fig.patch.set_facecolor("#0d1117")
    ax.set_facecolor("#0d1117")

    num_sigs = len(signals)
    row_height = 1.6
    y_spacing  = 1.9

    # Grid & Timeline setup
    t_start_ns = t_start / time_scale
    t_end_ns   = t_end / time_scale
    ax.set_xlim(t_start_ns - 5, t_end_ns + 15)
    ax.set_ylim(-1.0, num_sigs * y_spacing + 0.8)

    # Shaded Functional Regions
    ax.axvspan(90, 420, color="#1f6feb", alpha=0.08, label="FIFO Fill Phase (16 Writes)")
    ax.axvspan(420, 510, color="#da3633", alpha=0.10, label="Full & Overflow Invariant Check")
    ax.axvspan(510, 950, color="#238636", alpha=0.08, label="FIFO Drain Phase (16 Reads)")
    ax.axvspan(950, 995, color="#d29922", alpha=0.10, label="Empty & Underflow Invariant Check")

    # Annotations
    ax.text(255, num_sigs * y_spacing + 0.3, "BURST WRITES (16 Entries)", color="#79c0ff", fontsize=11, fontweight="bold", ha="center")
    ax.text(465, num_sigs * y_spacing + 0.3, "WFULL BLOCKS OVERFLOW", color="#ff7b72", fontsize=11, fontweight="bold", ha="center")
    ax.text(730, num_sigs * y_spacing + 0.3, "BURST READS (16 Entries)", color="#56d364", fontsize=11, fontweight="bold", ha="center")
    ax.text(972, num_sigs * y_spacing + 0.3, "REMPTY", color="#e3b341", fontsize=11, fontweight="bold", ha="center")

    for i, sig in enumerate(signals):
        # Y position inverted so first signal is at the top
        y_base = (num_sigs - 1 - i) * y_spacing
        name = sig["name"]
        color = sig["color"]
        stype = sig["type"]
        label = sig["label"]

        # Signal label on left
        domain_tag = " [W]" if "Write" in sig["domain"] else " [R]"
        ax.text(t_start_ns - 8, y_base + 0.45, label + domain_tag, color=color,
                fontsize=10.5, fontweight="bold", ha="right", va="center")

        # Baseline dashed guide
        ax.axhline(y_base, color="#21262d", linestyle="--", linewidth=0.7)

        # Build continuous time series
        events = history.get(name, [])
        # Filter events and ensure boundary values
        time_vals = []
        cur_val = 0
        for t, val in events:
            if t <= t_start:
                cur_val = val
            elif t > t_start and t <= t_end:
                if not time_vals:
                    time_vals.append((t_start, cur_val))
                time_vals.append((t, val))
                cur_val = val
            elif t > t_end:
                break
        if not time_vals:
            time_vals = [(t_start, cur_val), (t_end, cur_val)]
        else:
            time_vals.append((t_end, cur_val))

        # Plot 1-bit or bus
        if stype == "1bit":
            xs = []
            ys = []
            for j in range(len(time_vals) - 1):
                t0, v0 = time_vals[j]
                t1, v1 = time_vals[j+1]
                t0_ns = t0 / time_scale
                t1_ns = t1 / time_scale
                y_val = y_base + (0.9 if v0 == 1 else 0.05)
                
                if xs:
                    # Vertical step edge
                    xs.append(t0_ns)
                    ys.append(y_val)
                else:
                    xs.append(t0_ns)
                    ys.append(y_val)
                xs.append(t1_ns)
                ys.append(y_val)

            ax.plot(xs, ys, color=color, linewidth=1.6)
            # Subtle glow fill
            ax.fill_between(xs, y_base + 0.05, ys, color=color, alpha=0.18)

        elif stype == "bus":
            # Draw bus waveforms (hex envelopes)
            for j in range(len(time_vals) - 1):
                t0, v0 = time_vals[j]
                t1, v1 = time_vals[j+1]
                t0_ns = t0 / time_scale
                t1_ns = t1 / time_scale
                width_ns = t1_ns - t0_ns
                if width_ns < 0.2:
                    continue

                y_top = y_base + 0.95
                y_bot = y_base + 0.05
                y_mid = y_base + 0.50

                # Bus hexagon transition
                dx = min(2.0, width_ns * 0.15)
                poly_x = [t0_ns, t0_ns + dx, t1_ns - dx, t1_ns, t1_ns - dx, t0_ns + dx]
                poly_y = [y_mid, y_top, y_top, y_mid, y_bot, y_bot]
                ax.plot(poly_x + [poly_x[0]], poly_y + [poly_y[0]], color=color, linewidth=1.2)
                ax.fill(poly_x, poly_y, color=color, alpha=0.12)

                # Text label inside bus if wide enough
                if width_ns > 12:
                    if name in ["wdata", "rdata"]:
                        if v0 > 0:
                            hex_str = f"0x{v0:08X}"
                            ax.text(t0_ns + width_ns/2, y_mid, hex_str, color="#ffffff",
                                    fontsize=7.5, ha="center", va="center", family="monospace")
                    elif name in ["wptr", "rptr"]:
                        gray_bin = f"5'b{v0:05b}"
                        ax.text(t0_ns + width_ns/2, y_mid, gray_bin, color="#e6edf3",
                                fontsize=7.5, ha="center", va="center", family="monospace")

    # Titles and formatting
    ax.set_title("SyncBridge Asynchronous FIFO – Dual-Clock Timing Diagram (WCLK: 100MHz, RCLK: 73MHz)",
                 color="#f0f6fc", fontsize=15, fontweight="bold", pad=24)
    ax.set_xlabel("Simulation Time (ns)", color="#8b949e", fontsize=11, fontweight="bold", labelpad=10)

    # Style axes
    ax.tick_params(axis='x', colors='#8b949e', labelsize=10)
    ax.tick_params(axis='y', left=False, labelleft=False)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.spines['left'].set_visible(False)
    ax.spines['bottom'].set_color('#30363d')
    ax.grid(axis='x', color='#21262d', linestyle=':', linewidth=0.8)

    # Watermark / Legend
    plt.tight_layout()
    fig.savefig(out_path, facecolor=fig.get_facecolor(), edgecolor='none', bbox_inches='tight')
    plt.close(fig)
    print(f"[SUCCESS] Waveform diagram generated at: {out_path}")

if __name__ == "__main__":
    hist = parse_vcd(VCD_FILE)
    plot_dark_waveform(hist, OUT_PNG)
