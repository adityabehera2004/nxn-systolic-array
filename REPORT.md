# PPA Analysis

I evaluated the systolic array design across five array sizes (N=2,4,8,16,32) using the given test instruction sequence [32, 16, 64, 8, 16, 0] for power, performance, and area. This instruction sequence has 3 matrix-matrix multiplications and 53,248 multiply-accumulate operations.

## Methodology

**Power:** Dynamic power is estimated using the formula:
$$P_{\text{dynamic}} = \alpha \cdot C_{\text{total}} \cdot V^2 \cdot f$$

Where:
- $\alpha = 0.2$ (activity factor, 20% is a common activity factor)
- $C_{\text{total}} = N_{\text{gates}} \times 1 \text{ fF}$ (total switching capacitance, 1 fF per standard cell is typical for 22nm–28nm process nodes)
- $V = 1.0 \text{ V}$ (supply voltage)
- $f = 1.0 \text{ GHz}$ (clock frequency)

Static power is estimated at 10% of dynamic power, so total power is:
$$P_{\text{total}} = P_{\text{dynamic}} + 0.1 \cdot P_{\text{dynamic}} = 1.1 \cdot P_{\text{dynamic}}$$

**Performance:** Cycle count is outputted at the end of each simulation. Execution time is derived by dividing cycle count by clock frequency (assumed 1 GHz).

**Area:** Gate count is outputted at the end of each simulation by Yosys. During synthesis of each design, Yosys calculates the number of cells (gates).

## Results

| N | Cycles | Exec Time (μs) | Gates | Power (mW) | MACs/Cycle | Energy/MAC (pJ) |
|---|--------|----------------|-------|-----------|------------|---------------------|
| 2 | 132,172 | 132.2 | 13,969 | 3.07 | 0.403 | 7.6 |
| 4 | 66,652 | 66.7 | 40,486 | 8.91 | 0.799 | 11.1 |
| 8 | 36,256 | 36.3 | 146,144 | 32.15 | 1.469 | 21.9 |
| 16 | 26,128 | 26.1 | 591,445 | 130.12 | 2.038 | 63.8 |
| 32 | 22,640 | 22.6 | 2,311,510 | 508.53 | 2.352 | 216.2 |

## Conclusions

As N increases, execution time halves up to N=8, but then shows diminishing returns at N=16 and N=32. This makes sense for the instruction sequence used: the largest matrix dimension is 64, and several stages are smaller, so very large array sizes are not fully utilized. Increasing array size helps most when the workload contains many large matrices that can be run as one computation instead of being broken up and tiled to run on a smaller array. Gate count scales roughly with N^2, which is expected because the array itself grows as NxN. Power also scales roughly with N^2, which is expected since power is assumed to scale proportionally with gate count in my model. Energy per MAC increases significantly for larger N, indicating that very large arrays are very energy inefficient for this workload.

Future work could evaluate different instruction sequences (varying length and maximum matrix dimensions) to see how the workload itself affects power, performance, and area.