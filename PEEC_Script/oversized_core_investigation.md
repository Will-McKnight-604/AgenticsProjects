# Oversized Core Recommendation — Root Cause Investigation

## Problem

The PyOpenMagnetics magnetic adviser recommends a **PQ 107/87** core for a **~57W two-switch forward converter**. This is absurdly oversized — a PQ40/45 handles ~2kW designs in practice. The core selection is off by roughly two orders of magnitude.

## Design Under Test

| Parameter | Value |
|-----------|-------|
| Topology | Two-Switch Forward |
| Vin | 36–74 V |
| Fsw | 110 kHz |
| Output 1 | ~12 V / 2 A |
| Output 2 | ~3.3 V / 10 A |
| Total Pout | ~57 W |
| Lm (computed) | 364.8 µH |
| Np:Ns1 | 1.276 : 1 |
| Np:Ns2 | 4.059 : 1 |
| Magnetizing Ipk | 0.202 A |

## Root Cause

The issue is **not** that PyOpenMagnetics treats transformers and inductors identically. The C++ code does distinguish them:

- **AreaProduct filter** (`MagneticFilter.cpp:137`): Uses a `primaryAreaFactor = 0.5` multiplier when `turns_ratios.size() > 0` (i.e., transformers get half the AP requirement).
- **EnergyStored filter** (`MagneticEnergy.cpp:132`): Correctly reads `magnetizingCurrent.processed.peak` from the operating point — it uses **only** the magnetizing current, not the full primary current.

The actual problem is in **`pm.process_inputs()`** (a PyOpenMagnetics/MKF C++ function). When it computes the `magnetizingCurrent` field from our input data, it produces **inflated values**:

### What process_inputs() produces

| Winding | magnetizingCurrent.peak | magnetizingCurrent.average | Actual expected |
|---------|------------------------|---------------------------|-----------------|
| Primary | 1.13 A | 1.09 A | ~0.07 A (ripple only) |
| Secondary 1 | 5.29 A | 5.28 A | N/A |
| Secondary 2 | 2.12 A | 2.11 A | N/A |

The `peak` values match the **DC load current** of each winding, not the small magnetizing ripple. The `peakToPeak` values (0.138 A, 0.011 A, 0.005 A) are the correct magnetizing ripple, but the `peak` includes a large DC offset.

### Impact on core sizing

The EnergyStored filter computes:

```
Energy = ½ × Lm × magnetizingCurrentPeak²
```

- **With inflated peak (1.13 A):** E = ½ × 1352 µH × 1.13² = **0.86 mJ**
- **With correct peak (0.07 A):** E = ½ × 1352 µH × 0.07² = **0.003 mJ**

This is a **~290× inflation** of the energy requirement, forcing the adviser to select cores large enough to store 0.86 mJ in an ungapped ferrite — which requires a massive core.

## Root Cause Detail — MKF C++ Source Analysis

### How `process_inputs()` computes magnetizing current (`Inputs.cpp`)

The function at line 1923 (`calculate_magnetizing_current`) does this for non-flyback topologies:

1. **Integrates the primary voltage waveform** — `i_m(t) = (1/Lm) × ∫v(t)dt` — this is physically correct (Faraday's law) and produces the small AC ripple.
2. **Adds a DC offset** extracted from the **primary current waveform's DC component** — this is where the inflation happens.

Our primary current waveform has a DC offset equal to the reflected load current (~1–4 A). `process_inputs()` adds this DC bias on top of the integrated voltage ripple, producing a magnetizing current with `peak ≈ load_current_DC + ripple/2` instead of `peak ≈ ripple/2`.

### Why this is arguably correct from MKF's perspective

For an inductor (single winding), the total current IS the magnetizing current, so adding the DC component makes sense. For a transformer, the DC component is the load current reflected through the turns ratio — it's NOT magnetizing current. MKF's `include_dc_offset_into_magnetizing_current()` function (line 225) has logic to decide this based on topology, but it appears to include the DC offset for our waveform configuration.

### The fix — pre-populate `magnetizingCurrent`

From `Inputs.cpp` line 2101:
```cpp
if (!excitation.get_magnetizing_current() && magnetizingInductance > 0) {
    // ... compute from voltage + Lm + dc_offset
}
```

**If `magnetizingCurrent` is already present in the excitation, `process_inputs()` skips the calculation entirely.** So the fix is to pre-populate the `magnetizingCurrent` field in our primary excitation with the correct small-ripple waveform before calling `process_inputs()`. This is not re-implementing their code — it's providing a more complete input so their function doesn't have to guess the DC offset.

### Implementation

In `build_operating_points()` (generate_om_topology.py), add a `magnetizingCurrent` field to the primary excitation with:
- A triangular waveform: ramps from `-i_mag_pp/2` to `+i_mag_pp/2` during on-time, resets during off-time
- `peakToPeak = i_mag_pp` (the small ripple, e.g. 0.4 A)
- `peak = i_mag_pp / 2` (e.g. 0.2 A)
- No DC offset (magnetizing current is purely AC for a forward converter)

## Related Bugs Fixed (2026-03-21)

### 1. stderr crash (`[Errno 22]`) — `call_pyopenmagnetics_api.py`
- Added `_log()` wrapper that catches `OSError` when stderr is closed by Octave
- Replaced all 30+ `print(..., file=sys.stderr)` calls with `_log()`

### 2. Primary current only reflecting first secondary — `generate_om_topology.py`
- `build_operating_points()` and `build_waveform_preview()` computed:
  ```python
  i_pri_pp = i_mag_pp + iout_list[0] * ns_np  # only first secondary!
  ```
- Fixed to sum reflected currents from **all** secondaries:
  ```python
  i_load_reflected = sum(iout_i * ns_np_i for all secondaries)
  i_pri_pp = i_mag_pp + i_load_reflected
  ```
- With the test config (0.05 A @ 12 V + 10 A @ 3.3 V): primary current was 0.435 A, now correctly 4.14 A
- Fixed in all 8 topology calculator classes

### 3. Output power miscalculation — `generate_om_topology.py`
- Used `pout = vout[0] * sum(all_currents)` instead of `sum(vout_i * iout_i)`
- For asymmetric outputs: computed 144 W instead of correct 57 W
- Fixed in all 7 topology calculator classes

### 4. `ns_np_list` not propagated — `generate_om_topology.py`
- Per-secondary Ns/Np ratio list was computed but not returned in `design_reqs`
- Added `ns_np_list` to all topology calculator return dicts
