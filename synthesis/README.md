# Genus Synthesis Run

Logic synthesis of `cnn_top` with Cadence Genus 21.14-s082_1 (run on 2026-10-28).

| Item | Value |
|------|-------|
| Library | 90nm `fast.lib` (fast corner) |
| Clock | 10 ns (100 MHz), 0.2 ns uncertainty, 0.1 ns transition |
| I/O delay | 1.0 ns input and output |
| Worst setup slack | +5.652 ns (met) |
| Cell count | 11,956 |
| Cell area | 109,558 µm² |
| Total power | 10.79 mW (leakage 0.93 mW, internal 8.00 mW, switching 1.87 mW) |

Notes:
- RTL synthesized is identical to the files in the repo root (`control.sv` = `control_block.sv`, `systolic_array.sv` = `Systolicarray.sv`; only the file names differ in the run directory, see `syn.tcl`).
- Power is from Genus' default activity assumptions, not simulation-based switching activity.
- Not yet checked: LEC (Conformal), hold timing, and post-route numbers.

## Contents
- `syn.tcl` – Genus script
- `cnn_top.sdc` – constraints written by Genus
- `reports/` – `area.rpt`, `timing.rpt`, `power.rpt`
- `netlist/cnn_top_mapped.v` – mapped gate-level netlist
- `images/genus_schematic.png` – schematic from the Genus GUI
