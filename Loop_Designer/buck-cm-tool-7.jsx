import { useState, useMemo, useCallback, useRef, useEffect, Component } from "react";
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, ReferenceLine, ReferenceArea, Legend, Label
} from "recharts";

// ─── Complex Math ───────────────────────────────────────────
const C = (re, im = 0) => ({ re, im });
const cadd = (a, b) => C(a.re + b.re, a.im + b.im);
const cmul = (a, b) => C(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re);
const cdiv = (a, b) => {
  const d = b.re * b.re + b.im * b.im;
  return d === 0 ? C(1e12, 0) : C((a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d);
};
const cmag = (a) => Math.sqrt(a.re * a.re + a.im * a.im);
const cphase = (a) => Math.atan2(a.im, a.re) * (180 / Math.PI);
const cscale = (a, k) => C(a.re * k, a.im * k);
const dB = (x) => 20 * Math.log10(Math.max(x, 1e-30));
const sf = (v, d=1) => (v != null && isFinite(v)) ? v.toFixed(d) : "—";
const TWO_PI = 2 * Math.PI;

// Per-cap-type temperature derating (from investigation doc §6 / consolidated plan §2.5)
// Each type has ESR and capacitance multipliers at cold/hot extremes
const CAP_TYPE_DERATE = {
  electrolytic: { cold: { esr: 3.0, cap: 0.50 }, nominal: { esr: 1.0, cap: 1.0 }, hot: { esr: 0.6, cap: 0.80 } },
  polymer:      { cold: { esr: 1.5, cap: 0.95 }, nominal: { esr: 1.0, cap: 1.0 }, hot: { esr: 0.9, cap: 0.92 } },
  mlcc_x7r:     { cold: { esr: 1.1, cap: 0.80 }, nominal: { esr: 1.0, cap: 1.0 }, hot: { esr: 1.1, cap: 0.85 } },
  mlcc_x5r:     { cold: { esr: 1.1, cap: 0.60 }, nominal: { esr: 1.0, cap: 1.0 }, hot: { esr: 1.2, cap: 0.75 } },
};
// Inductor derating stays global (not cap-type dependent)
const TEMP_FACTORS = {
  nominal: { ind: 1.0, label: "25°C" },
  cold:    { ind: 1.02, label: "−40°C" },
  hot:     { ind: 0.97, label: "+125°C" },
};
// Helper: get per-type cap derating factors for a given temp corner
function getCapDerate(capType, tempCorner) {
  const typeFactors = CAP_TYPE_DERATE[capType] || CAP_TYPE_DERATE.electrolytic;
  return typeFactors[tempCorner] || typeFactors.nominal;
}

const logspace = (fmin, fmax, n) => {
  const a = []; const l0 = Math.log10(fmin), l1 = Math.log10(fmax);
  for (let i = 0; i < n; i++) a.push(10 ** (l0 + (l1 - l0) * i / (n - 1)));
  return a;
};

// ─── Capacitor Bank Impedance ────────────────────────────────
// Each cap: Zcap_i(s) = s·ESL + ESR + 1/(s·C)
// Bank: parallel combination of all caps
function evalZcapSingle(f, cap_F, esr_ohm, esl_H) {
  const w = TWO_PI * f;
  const re = esr_ohm;
  const im = (esl_H > 0 ? w * esl_H : 0) - 1 / (w * Math.max(cap_F, 1e-15));
  return C(re, im);
}

function evalZcapBank(f, bank) {
  if (!bank || bank.length === 0) return C(0.02, -1 / (TWO_PI * f * 220e-6));
  // Sum admittances: Y_total = sum_i(qty_i × Y_single_i)
  let Yre = 0, Yim = 0;
  for (let i = 0; i < bank.length; i++) {
    const { qty, cap_F, esr_ohm, esl_H } = bank[i];
    if (qty <= 0 || cap_F <= 0) continue;
    // Z of a single cap in this slot
    const z = evalZcapSingle(f, cap_F, esr_ohm, esl_H);
    // Y_single = 1/Z, then multiply by qty for parallel caps
    const d = z.re * z.re + z.im * z.im;
    if (d > 0) { Yre += qty * z.re / d; Yim += qty * (-z.im) / d; }
  }
  const d = Yre * Yre + Yim * Yim;
  return d > 0 ? C(Yre / d, -Yim / d) : C(1e-6, 0);
}

// Effective C and ESR for scalar estimates (getPlantInfo, auto-placer)
function getCapBankEffective(bank) {
  if (!bank || bank.length === 0) return { Ceff: 220e-6, ESReff: 0.02, hasESL: false };
  let Ceff = 0;
  for (const b of bank) Ceff += b.qty * b.cap_F;
  // Effective ESR: evaluate |Z| at a moderate frequency and subtract capacitive part
  // Simpler: ESR_eff = 1/sum(qty/ESR_i) (parallel ESRs)
  let invR = 0;
  let hasESL = false;
  for (const b of bank) {
    if (b.qty > 0 && b.esr_ohm > 0) invR += b.qty / b.esr_ohm;
    if (b.esl_H > 0) hasESL = true;
  }
  const ESReff = invR > 0 ? 1 / invR : 0.001;
  return { Ceff, ESReff, hasESL };
}

// ─── Impedance-curve-derived ESR zero ───────────────────────
// Sweeps |Zbank(f)| to find the frequency where impedance transitions
// from capacitive (falling) to flat/inductive (rising) — the impedance minimum.
// This is the "effective ESR zero" for plant pole/zero placement.
// For a single cap with no ESL, this equals 1/(2π·C·ESR).
// For mixed banks with split ESR zeros, this finds the dominant one from the actual curve.
function findBankEsrZero(bank) {
  if (!bank || bank.length === 0) return null;
  // Quick check: if all caps have zero ESL and same type, scalar formula is fine
  const hasMultipleTypes = new Set(bank.filter(b => b.qty > 0 && b.cap_F > 0).map(b => b.type)).size > 1;
  const hasESL = bank.some(b => b.esl_H > 0 && b.qty > 0);
  if (!hasMultipleTypes && !hasESL) return null; // scalar formula is adequate
  // Sweep from 10 Hz to 50 MHz to find |Z| minimum
  const N = 200;
  let minZ = Infinity, fAtMinZ = 1e3;
  const fLo = 10, fHi = 5e7;
  for (let i = 0; i < N; i++) {
    const f = fLo * Math.pow(fHi / fLo, i / (N - 1));
    const z = cmag(evalZcapBank(f, bank));
    if (z < minZ) { minZ = z; fAtMinZ = f; }
  }
  // Refine: narrow ±0.5 decade around the minimum
  const fRefLo = fAtMinZ / 3.16, fRefHi = fAtMinZ * 3.16;
  for (let i = 0; i < 100; i++) {
    const f = fRefLo * Math.pow(fRefHi / fRefLo, i / 99);
    const z = cmag(evalZcapBank(f, bank));
    if (z < minZ) { minZ = z; fAtMinZ = f; }
  }
  // The ESR zero for plant purposes is where |Zcap| transitions from
  // capacitive (−20dB/dec) to flat (ESR). Find where slope goes from negative
  // to ~0 by walking down from fAtMinZ toward lower frequencies.
  // Approximate: the −3dB point below the ESR floor on the capacitive side
  const esrFloor = minZ;
  const target = esrFloor * Math.SQRT2; // √2 × ESR = −3dB above floor
  let fzEsr = fAtMinZ;
  for (let i = 0; i < 150; i++) {
    const f = fAtMinZ * Math.pow(fLo / fAtMinZ, i / 149);
    const z = cmag(evalZcapBank(f, bank));
    if (z >= target) { fzEsr = f; break; }
  }
  return { fz_esr: fzEsr, zMin: minZ, fMin: fAtMinZ };
}

// Detect anti-resonance: find local impedance maximum between SRFs
function detectAntiResonance(bank) {
  if (!bank || bank.length < 2) return null;
  // Check SRFs of each cap type
  const srfs = bank.filter(b => b.qty > 0 && b.esl_H > 0 && b.cap_F > 0)
    .map(b => ({ f: 1 / (TWO_PI * Math.sqrt(b.esl_H / b.qty * b.cap_F * b.qty)), type: b.type }));
  if (srfs.length < 2) return null;
  // Sweep between min and max SRF to find impedance peak
  const fMin = Math.min(...srfs.map(s => s.f)) * 0.5;
  const fMax = Math.max(...srfs.map(s => s.f)) * 2;
  const pts = 200;
  let peakZ = 0, peakF = 0;
  for (let i = 0; i <= pts; i++) {
    const f = fMin * Math.pow(fMax / fMin, i / pts);
    const z = cmag(evalZcapBank(f, bank));
    if (z > peakZ) { peakZ = z; peakF = f; }
  }
  // Only report if peak is at least 2× the minimum impedance in that range
  let minZ = Infinity;
  for (let i = 0; i <= pts; i++) {
    const f = fMin * Math.pow(fMax / fMin, i / pts);
    minZ = Math.min(minZ, cmag(evalZcapBank(f, bank)));
  }
  if (peakZ > minZ * 2 && peakF > fMin * 1.1 && peakF < fMax * 0.9) {
    return { freq: peakF, impedance: peakZ, ratio: peakZ / minZ };
  }
  return null;
}

// ─── Impedance CSV Parser & Fitter ─────────────────────────
// Parses vendor impedance data (Murata SimSurfing, TDK SEAT, Kemet K-SIM, etc.)
// Accepts: freq,|Z|,phase or freq,|Z| (phase optional, degrees)
// Fits: Z(f) = j·w·ESL + ESR + 1/(j·w·C) → extract C, ESR, ESL
function parseImpedanceCSV(text) {
  const lines = text.trim().split(/\r?\n/).filter(l => l.trim() && !l.trim().startsWith('#'));
  const data = [];
  for (const line of lines) {
    const parts = line.split(/[\t,;]+/).map(s => s.trim());
    if (parts.length < 2) continue;
    const f = parseFloat(parts[0]);
    const z = parseFloat(parts[1]);
    const ph = parts.length >= 3 ? parseFloat(parts[2]) : null;
    if (isFinite(f) && isFinite(z) && f > 0 && z > 0) {
      data.push({ f, z, ph: isFinite(ph) ? ph : null });
    }
  }
  if (data.length < 3) return { error: "Need at least 3 valid data points (freq, |Z|)", data: [] };
  return { data, error: null };
}

function fitCapFromImpedance(data) {
  if (!data || data.length < 3) return null;
  // Find minimum |Z| → that's near ESR (at self-resonant frequency)
  let minZ = Infinity, minIdx = 0;
  for (let i = 0; i < data.length; i++) {
    if (data[i].z < minZ) { minZ = data[i].z; minIdx = i; }
  }
  const ESR = minZ;
  const f_srf = data[minIdx].f;
  // Below SRF: Z ≈ 1/(2π·f·C) → C = 1/(2π·f·Z)
  // Use a point well below SRF for C estimation
  const lowIdx = Math.max(0, Math.floor(minIdx * 0.2));
  const fLow = data[lowIdx].f;
  const zLow = data[lowIdx].z;
  const C = 1 / (TWO_PI * fLow * Math.sqrt(Math.max(zLow * zLow - ESR * ESR, ESR * ESR * 0.01)));
  // Above SRF: Z ≈ 2π·f·ESL → ESL = Z/(2π·f)
  const highIdx = Math.min(data.length - 1, Math.floor(minIdx + (data.length - minIdx) * 0.8));
  const fHigh = data[highIdx].f;
  const zHigh = data[highIdx].z;
  const ESL = Math.sqrt(Math.max(zHigh * zHigh - ESR * ESR, 0)) / (TWO_PI * fHigh);
  // Validate
  if (!isFinite(C) || C <= 0 || !isFinite(ESR) || ESR <= 0) return null;
  return {
    C_F: C, ESR_ohm: ESR, ESL_H: isFinite(ESL) && ESL > 0 ? ESL : 0,
    f_srf, nPoints: data.length,
  };
}

// ─── Current Sense Chain ────────────────────────────────────
// Shunt: Kcs(s) = (Rshunt + s·Lpar) · Gamp(s) · Gfilter(s)
// CT: Kcs(s) = (Ns/Np) · Rb · sLm / (sLm + Rb) · 1/(1+s²LlkCw)  [high-pass]
// For "simple" mode, Kcs = scalar Ri (backward compat)
function evalSenseChain(f, sp) {
  if (!sp || sp.mode === "simple") return C(sp ? sp.ri : 0.05, 0);
  const w = TWO_PI * f;
  if (sp.mode === "ct") {
    const { turnsRatio, rb, lm, llk, cw } = sp;
    // Midband gain = (Np/Ns) × burden = Rb / turnsRatio
    const gain = rb / turnsRatio;
    // High-pass from magnetizing inductance: sLm/(sLm + Rb) = jωLm/(Rb + jωLm)
    const num_hp = C(0, w * lm);           // jωLm
    const den_hp = C(rb, w * lm);          // Rb + jωLm
    const hp = cdiv(num_hp, den_hp);
    // High-frequency rolloff from leakage + winding capacitance
    // 1/(1 + s²·Llk·Cw) = 1/(1 - ω²·Llk·Cw)
    let hf = C(1, 0);
    if (llk > 0 && cw > 0) {
      const w2lc = w * w * llk * cw;
      hf = cdiv(C(1, 0), C(1 - w2lc, 0));
    }
    return cscale(cmul(hp, hf), gain);
  }
  // Shunt mode
  const { rshunt, lpar, gampDC, gampBW, rfilter, cfilter } = sp;
  const zShunt = C(rshunt, w * lpar);
  const amp = gampBW > 0
    ? cdiv(C(gampDC, 0), C(1, f / gampBW))
    : C(gampDC, 0);
  const tau = rfilter * cfilter;
  const filt = tau > 0 ? cdiv(C(1, 0), C(1, w * tau)) : C(1, 0);
  return cmul(cmul(zShunt, amp), filt);
}

// Key frequencies, power dissipation, CT diagnostics
function getSenseInfo(sp, placement, iout, vin, vout, L, fsw_hz) {
  if (!sp || sp.mode === "simple") return { fz_par: null, fp_amp: null, fp_filt: null, pDiss: null, placement: placement || "high_side" };
  const D = vout / Math.max(vin, 0.01);
  if (sp.mode === "ct") {
    const { turnsRatio, rb, lm, llk, cw } = sp;
    const ri_ct = rb / turnsRatio;  // Ri = (Np/Ns) × Rb. I_sec = I_pri × (Np/Ns), V_sense = I_sec × Rb.
    const fp_ct = rb / (TWO_PI * Math.max(lm, 1e-12));  // low-freq pole (high-pass corner)
    const Ton = D / Math.max(fsw_hz, 1);
    const tau_ct = lm / Math.max(rb, 1e-6);
    const droopPct = Ton / tau_ct * 100;   // ΔV/V as percentage
    // Volt-second reset check: self-reset needs Toff > Ton × (V_on/V_reset)
    // For simple self-reset through burden: reset ratio ≈ D/(1-D)
    const Toff = (1 - D) / Math.max(fsw_hz, 1);
    const resetMargin = Toff / Math.max(Ton, 1e-12);  // >1 means self-reset possible
    // HF resonance from leakage + winding cap
    const fres_hf = (llk > 0 && cw > 0) ? 1 / (TWO_PI * Math.sqrt(llk * cw)) : null;
    // Burden resistor dissipation: P = I_secondary² × Rb = (I_primary / (Ns/Np))² × Rb
    const dI = (vin - vout) * D / Math.max(L * fsw_hz, 1e-12);
    const Idc2 = iout * iout, Iac2 = dI * dI / 12;
    let Irms2_primary;
    if (placement === "inductor") Irms2_primary = Idc2 + Iac2;
    else Irms2_primary = D * (Idc2 + Iac2);  // high-side pulsed
    const pDiss = Irms2_primary / (turnsRatio * turnsRatio) * rb;
    return { isCT: true, fp_ct, droopPct, resetMargin, fres_hf, ri_ct, pDiss, placement, turnsRatio };
  }
  // Shunt mode
  const { rshunt, lpar, gampDC, gampBW, rfilter, cfilter } = sp;
  const fz_par = lpar > 0 ? rshunt / (TWO_PI * lpar) : null;
  const fp_amp = gampBW > 0 ? gampBW : null;
  const tau = rfilter * cfilter;
  const fp_filt = tau > 0 ? 1 / (TWO_PI * tau) : null;
  const dI = (vin - vout) * D / Math.max(L * fsw_hz, 1e-12);
  const Idc2 = iout * iout, Iac2 = dI * dI / 12;
  let Irms2;
  if (placement === "inductor") Irms2 = Idc2 + Iac2;
  else if (placement === "low_side") Irms2 = (1 - D) * (Idc2 + Iac2);
  else Irms2 = D * (Idc2 + Iac2);
  const pDiss = Irms2 * rshunt;
  return { fz_par, fp_amp, fp_filt, pDiss, placement };
}
function getIoCritical(vin, vout, L, fsw_hz) {
  const D = vout / Math.max(vin, 0.01);
  return (vin - vout) * D / (2 * L * fsw_hz);
}
// Flyback CCM/DCM boundary: different from buck because energy transfer is during D' only
function getIoCriticalFlyback(vin_eff, vout, Lm_H, n, fsw_hz) {
  const D = vout / Math.max(vout + vin_eff, 0.01);
  const Vin_pri = vin_eff / Math.max(n, 0.001);
  // Primary peak current at boundary: Ip_pk = Vin_pri × D / (Lm × fsw)
  // Output current at boundary: Iout = Ip_pk × n × D' / 2
  return Vin_pri * D * (1 - D) * n / (2 * Lm_H * fsw_hz);
}

// ─── Plant: Unified CCM/DCM model ──────────────────────────
// CCM: uses inner-loop closure Fm·Gid·Gvi/(1+Ti) which naturally
//   transitions from current-mode (Ti>>1) to voltage-mode (Ti<<1)
//   when slope comp is excessive. Includes He(s) sampling effects.
// DCM: single-pole model (inductor resets each cycle, no LC resonance,
//   no subharmonic instability)
// Flyback: uses Basso/Richtek closed-form with RHPZ (no sub-block decomposition)
function evalPlant(f, p) {
  // gm_ps mode: integrated converter (inner loop already closed inside IC)
  if (p.plantMode === "gmps") return evalPlantGmps(f, p);
  const { vin, vout, iout, fsw_hz, L, cout, esr, ri, se } = p;
  // Flyback dispatch — different plant structure (RHPZ, no output inductor)
  if (p.topology === "flyback") {
    const n = p.n || 1;
    const Lm_H = p.Lm_H || L;
    const Io_crit = getIoCriticalFlyback(vin, vout, Lm_H, n, fsw_hz);
    if (iout > Io_crit) {
      return evalPlantFlybackCCM(f, p);
    } else {
      return evalPlantFlybackDCM(f, p);
    }
  }
  const Io_crit = getIoCritical(vin, vout, L, fsw_hz);
  if (iout > Io_crit) {
    return evalPlantCCM(f, p);
  } else {
    return evalPlantDCM(f, p);
  }
}

// ─── CCM plant via inner-loop closure ───────────────────────
// Gvc(s) = Fm·Gid(s)·Gvi(s) / (1 + Fm·Gid(s)·Ri)
// Ti = Fm·Gid·Kcs(s) is the PHYSICAL inner loop gain (no He).
// Kcs(s) is the full sense chain transfer function (= scalar Ri when sense mode is "simple").
// He(s) is Ridley's analytical sampling correction — kept in the
// Ridley closed-form reference trace, not in the closure model.
// When Ti(0)>>1: reduces to ~Rload/Ri with single pole (current-mode)
// When Ti(0)<<1: reduces to Fm·Gvd(s) showing LC double-pole (voltage-mode)
function evalPlantCCM(f, p) {
  const Fm = getFm(p);
  const gid = evalGid(f, p);
  const gvi = evalGvi(f, p);
  // Sense chain: Kcs(f) = frequency-dependent sense gain
  const kcs = p.senseParams ? evalSenseChain(f, p.senseParams) : C(p.ri, 0);
  // Physical inner loop: Ti = Fm · Gid · Kcs(s)
  const ti = cmul(cscale(gid, Fm), kcs);
  const num = cscale(cmul(gid, gvi), Fm);
  return cdiv(num, cadd(C(1, 0), ti));
}

// ─── DCM plant: single-pole model ───────────────────────────
// In DCM the inductor current resets to zero each cycle.
// No LC double-pole, no He(s) sampling effects, no subharmonic instability.
// Loss-free resistor Re appears in parallel with Rload.
function evalPlantDCM(f, p) {
  const { vin, vout, iout, fsw_hz, L, ri } = p;
  const rload = vout / Math.max(iout, 0.001);
  const eff = p.capBank ? getCapBankEffective(p.capBank) : { Ceff: p.cout, ESReff: p.esr };
  const cout_eff = eff.Ceff, esr_eff = eff.ESReff;
  const D_dcm = Math.sqrt(Math.max(2 * L * Math.max(iout, 0.001) * fsw_hz / Math.max(vin - vout, 0.01), 1e-12));
  const D_clamped = Math.min(D_dcm, 0.95);
  const Re = 2 * L * fsw_hz / Math.max(D_clamped * D_clamped, 1e-9);
  const Reff = (rload * Re) / (rload + Re);
  const Gdc = Reff / Math.max(ri, 1e-6);
  const fp = 1 / (TWO_PI * Reff * cout_eff);
  const fz_esr = 1 / (TWO_PI * cout_eff * Math.max(esr_eff, 1e-6));
  const w = TWO_PI * f;
  const num = C(1, w / (TWO_PI * fz_esr));
  const den = C(1, w / (TWO_PI * fp));
  return cscale(cdiv(num, den), Gdc);
}

// ─── Flyback CCM plant: Basso/Richtek closed-form ───────────
// Gvc(s) = G0 × (1+s/ωz_esr) × (1-s/ωz_rhp) / ((1+s/ωp1) × He(s))
// Based on Christophe Basso model, validated by Richtek AN017 against Simplis.
// Key differences from buck:
//   - RHPZ: (1-s/ωz_rhp) gives +20dB/dec gain but -90° phase (phase-losing)
//   - Sn = Vin_pri / Lp (full Vin across primary during on-time)
//   - D = Vout / (Vout + Vin_eff) (not Vout/Vin)
//   - No separate output inductor — Lm is the energy storage element
// Sub-block decomposition (Gid×Gvi) not available for flyback due to
// d̂ coupling in both state equations. Use this closed-form instead.
function evalPlantFlybackCCM(f, p) {
  const { vin, vout, iout, fsw_hz, ri, se } = p;
  const n = p.n || 1;
  const Lm_H = p.Lm_H || p.L;
  const Vin_pri = vin / Math.max(n, 0.001);
  const D = vout / Math.max(vout + vin, 0.01);
  const Dprime = 1 - D;
  const R = vout / Math.max(iout, 0.001);
  const eff = p.capBank ? getCapBankEffective(p.capBank) : { Ceff: p.cout, ESReff: p.esr };
  const cout = eff.Ceff, esr = eff.ESReff;

  // DC gain (Ridley: Rload/Ri when Ti>>1)
  const Gdc = R / Math.max(ri, 1e-6);

  // Output pole: capacitor only charges during D', so fp1 = 1/(2π·R·D'·C)
  const fp1 = 1 / (TWO_PI * R * Dprime * cout);
  // ESR zero (LHP)
  const fz_esr = 1 / (TWO_PI * Math.max(esr, 1e-6) * cout);
  // Right-half-plane zero — the critical flyback feature
  // fz_rhp = R × D'² / (2π × D × Lm_sec) where Lm_sec = Lm/n²
  const Lm_sec = Lm_H * Math.max(n * n, 1e-6);
  const fz_rhp = R * Dprime * Dprime / (TWO_PI * D * Lm_sec);

  // He(s) sampling — same structure as buck, different Sn
  const Sn = Vin_pri / Math.max(Lm_H, 1e-9) * ri; // V/s at comparator
  const mc = 1 + (Sn > 0 ? se / Sn : 0);
  const factor = mc * Dprime - 0.5;
  const Qp = factor > 0.01 ? 1 / (Math.PI * factor) : 999;
  const wn = Math.PI * fsw_hz;
  const w = TWO_PI * f;

  // He(s) = 1 + s/(Qp·ωn) + s²/ωn²  →  at s=jω: (1 - ω²/ωn²) + jω/(Qp·ωn)
  const He = C(1 - (w * w) / (wn * wn), w / (Qp * wn));

  // Build transfer function
  // LHP ESR zero: (1 + jf/fz_esr)
  const zero_esr = C(1, f / fz_esr);
  // RHP zero: (1 - jf/fz_rhp) — NOTE MINUS for phase-losing behavior
  const zero_rhp = C(1, -f / fz_rhp);
  // Output pole: (1 + jf/fp1)
  const pole1 = C(1, f / fp1);

  // Gvc = Gdc × zero_esr × zero_rhp / (pole1 × He)
  return cdiv(cscale(cmul(zero_esr, zero_rhp), Gdc), cmul(pole1, He));
}

// ─── Flyback DCM plant: single-pole + RHPZ (at high frequency) ──
// In DCM the magnetizing current resets to zero each cycle.
// Structure: 1 pole + ESR zero + RHPZ (usually above fsw/2, often negligible)
// Based on Richtek AN017 eq.2 simplified (fp2 ≈ D'·fsw/2 → negligible)
function evalPlantFlybackDCM(f, p) {
  const { vin, vout, iout, fsw_hz, ri } = p;
  const n = p.n || 1;
  const Lm_H = p.Lm_H || p.L;
  const Vin_pri = vin / Math.max(n, 0.001);
  const D = vout / Math.max(vout + vin, 0.01);
  const Dprime = 1 - D;
  const R = vout / Math.max(iout, 0.001);
  const eff = p.capBank ? getCapBankEffective(p.capBank) : { Ceff: p.cout, ESReff: p.esr };
  const cout = eff.Ceff, esr = eff.ESReff;

  // DCM loss-free resistor (referred to secondary)
  const Lm_sec = Lm_H * Math.max(n * n, 1e-6);
  const D_dcm = Math.min(Math.sqrt(Math.max(2 * Lm_sec * iout * fsw_hz / Math.max(vout, 0.01), 1e-12)), 0.95);
  const Re = 2 * Lm_sec * fsw_hz / Math.max(D_dcm * D_dcm, 1e-9);
  const Reff = (R * Re) / (R + Re);
  const Gdc = Reff / Math.max(ri, 1e-6);
  const fp = 1 / (TWO_PI * Reff * cout);
  const fz_esr = 1 / (TWO_PI * Math.max(esr, 1e-6) * cout);

  const w = TWO_PI * f;
  const num = C(1, f / fz_esr);
  const den = C(1, f / fp);
  return cscale(cdiv(num, den), Gdc);
}

// ─── gm_ps plant: integrated converter model ────────────────
// For ICs with integrated FETs (TPS7H4011, etc.), TI provides gm_ps
// directly. The plant is: Gvc(s) = gm_ps_eff × Zout(s) × He(s)
// where Zout = Rload || Zcap(s). No Fm/Gid/Ti decomposition needed.
// He(s) = sampling effect double-pole at fsw/π with Qp from slope comp.
// Slope comp correction (optional): gm_ps_eff = gm_ps_table × Sn / (Sn + |SC|)
function evalPlantGmps(f, p) {
  const { vin, vout, iout, L } = p;
  const gm_ps_table = p.gm_ps || 20;
  const fsw_hz = p.fsw_hz || 500e3;
  // SC values: sc_aus is the gm_ps correction (may be 0 if toggle off)
  //            sc_aus_he is the REAL SC for He(s) (always physical value)
  const sc_gmps = Math.abs(p.sc_aus || 0);
  const sc_he = Math.abs(p.sc_aus_he != null ? p.sc_aus_he : p.sc_aus || 0);
  const Sn = L > 0 ? (vin - vout) / Math.max(L, 1e-12) / 1e6 : 999; // A/µs (L in H)
  // gm_ps correction (optional, controlled by toggle)
  const gm_ps = (sc_gmps > 0 && Sn > 0) ? gm_ps_table * Sn / (Sn + sc_gmps) : gm_ps_table;
  const rload = vout / Math.max(iout, 0.001);
  const w = TWO_PI * f;
  const zc = p.capBank ? evalZcapBank(f, p.capBank) : C(p.esr, -1 / (w * Math.max(p.cout, 1e-12)));
  const zr = C(rload, 0);
  const zout = cparallel(zr, zc);
  // He(s) sampling: ALWAYS uses real SC for mc (physical sampling effect)
  const D = vout / Math.max(vin, 0.01);
  const Dp = 1 - D;
  const mc_he = (sc_he > 0 && Sn > 0) ? 1 + sc_he / Sn : 1;
  const factor = mc_he * Dp - 0.5;
  const fn = fsw_hz / Math.PI;
  const wn = TWO_PI * fn;
  let He;
  if (factor > 0.01) {
    const Qp = 1 / (Math.PI * factor);
    const norm = w / wn;
    const den_re = 1 - norm * norm;
    const den_im = norm / Qp;
    He = cdiv(C(1, 0), C(den_re, den_im));
  } else {
    He = C(1, 0);
  }
  return cmul(cscale(zout, gm_ps), He);
}
function evalPlantRidley(f, p) {
  const { vin, vout, iout, fsw_hz, L, ri, se } = p;
  const eff = p.capBank ? getCapBankEffective(p.capBank) : { Ceff: p.cout, ESReff: p.esr };
  const cout = eff.Ceff, esr = eff.ESReff;
  const rload = vout / Math.max(iout, 0.001);
  const D = vout / Math.max(vin, 0.01);
  const Dprime = 1 - D;
  const sn = ((vin - vout) / Math.max(L, 1e-9)) * ri;
  const mc = 1 + (sn > 0 ? se / sn : 0);
  const factor = mc * Dprime - 0.5;
  const Qp = factor > 0.01 ? 1 / (Math.PI * factor) : 100;
  const fp1 = 1 / (TWO_PI * cout * rload);
  const fz_esr = 1 / (TWO_PI * cout * Math.max(esr, 1e-6));
  const Gvc0 = rload / Math.max(ri, 1e-6);
  const w = TWO_PI * f;
  const wn = TWO_PI * fsw_hz / Math.PI;
  const num = C(1, w / (TWO_PI * fz_esr));
  const den1 = C(1, w / (TWO_PI * fp1));
  const he = C(1 - (w / wn) ** 2, w / (Qp * wn));
  return cscale(cdiv(num, cmul(den1, he)), Gvc0);
}

function getPlantInfo(p) {
  const { vin, vout, iout, fsw_hz, L, ri, se } = p;
  const placement = p.placement || "high_side";
  const eff = p.capBank ? getCapBankEffective(p.capBank) : { Ceff: p.cout, ESReff: p.esr, hasESL: false };
  const cout = eff.Ceff, esr = eff.ESReff;
  const rload = vout / Math.max(iout, 0.001);

  // ─── Flyback topology: different D, Sn, RHPZ ─────────────
  if (p.topology === "flyback") {
    const n = p.n || 1;
    const Lm_H = p.Lm_H || L;
    const Vin_pri = vin / Math.max(n, 0.001);
    const D = vout / Math.max(vout + vin, 0.01); // flyback duty: D = Vout/(Vout + Vin×n)
    const Dprime = 1 - D;
    // Flyback output pole: capacitor only charges during D' (off-time)
    // fp1 = 1/(2π·R·D'·C) — moves up as D increases (Vorperian PWM switch model)
    const fp1 = 1 / (TWO_PI * cout * rload * Dprime);
    const fz_esr_scalar = 1 / (TWO_PI * cout * Math.max(esr, 1e-6));
    const bankZero = p.capBank ? findBankEsrZero(p.capBank) : null;
    const fz_esr = bankZero ? bankZero.fz_esr : fz_esr_scalar;
    const fz_esr_method = bankZero ? "curve" : "scalar";
    const Lm_sec = Lm_H * Math.max(n * n, 1e-6);
    const f0_LC = 1 / (TWO_PI * Math.sqrt(Lm_sec * cout)); // reference frequency
    // RHPZ: the critical flyback feature — phase-losing zero
    const fz_rhp = rload * Dprime * Dprime / (TWO_PI * D * Lm_sec);
    // CCM/DCM boundary
    const Io_crit = getIoCriticalFlyback(vin, vout, Lm_H, n, fsw_hz);
    const mode = iout > Io_crit ? "CCM" : "DCM";
    // Slope: Sn = Vin_pri / Lm (full Vin across Lm during on-time, NOT (Vin-Vout)/L)
    const sn_inductor = Vin_pri / Math.max(Lm_H, 1e-9); // A/s on primary
    const sn = sn_inductor * ri; // V/s at comparator
    const mc = 1 + (sn > 0 ? se / sn : 0);
    const factor = mc * Dprime - 0.5;
    const ctrlMode = "peak";
    const Qp = factor > 0.01 ? 1 / (Math.PI * factor) : 999;
    const Gvc0_dB = dB(rload / Math.max(ri, 1e-6));
    const Fm = fsw_hz / Math.max(sn * mc, 1e-12);
    const Ti0 = isFinite(Fm) ? Fm * (Vin_pri / rload) * ri : 999;
    // DCM parameters
    let fp_dcm = undefined, Reff_dcm = undefined;
    if (mode === "DCM") {
      const D_dcm = Math.min(Math.sqrt(Math.max(2 * Lm_sec * iout * fsw_hz / Math.max(vout, 0.01), 1e-12)), 0.95);
      const Re = 2 * Lm_sec * fsw_hz / Math.max(D_dcm * D_dcm, 1e-9);
      Reff_dcm = (rload * Re) / (rload + Re);
      fp_dcm = 1 / (TWO_PI * Reff_dcm * cout);
    }
    return { D, Dprime, mc, Qp, fp1, fz_esr, fz_esr_scalar, fz_esr_method, fz_rhp,
      Gvc0_dB, rload, factor, sn, sn_inductor, sn_mag: 0, Io_crit, mode, Ti0, f0_LC, Fm,
      fp_dcm, Reff_dcm, ctrlMode, placement, topology: "flyback" };
  }

  // ─── Buck / 2SW Forward common path ───────────────────────
  const D = vout / Math.max(vin, 0.01);
  const Dprime = 1 - D;
  const fp1 = 1 / (TWO_PI * cout * rload);
  const fz_esr_scalar = 1 / (TWO_PI * cout * Math.max(esr, 1e-6));
  const bankZero = p.capBank ? findBankEsrZero(p.capBank) : null;
  const fz_esr = bankZero ? bankZero.fz_esr : fz_esr_scalar;
  const fz_esr_method = bankZero ? "curve" : "scalar";
  const f0_LC = 1 / (TWO_PI * Math.sqrt(L * cout));
  const Io_crit = getIoCritical(vin, vout, L, fsw_hz);
  const mode = iout > Io_crit ? "CCM" : "DCM";

  // gm_ps mode: integrated converter — inner loop already closed inside IC
  if (p.plantMode === "gmps") {
    const gm_ps_table = p.gm_ps || 20;
    // SC: sc_aus for gm_ps correction (may be 0 if toggle off)
    //     sc_aus_he for He(s) (always real physical SC value)
    const sc = Math.abs(p.sc_aus || 0);
    const sc_he = Math.abs(p.sc_aus_he != null ? p.sc_aus_he : p.sc_aus || 0);
    const Sn_inductor_Aus = L > 0 ? (vin - vout) / Math.max(L, 1e-12) / 1e6 : 999;
    const n_xfmr = p.n || 1;
    const Lm_H = p.Lm_H || 0;
    const Sn_mag_Aus = (p.lmAffectsSn && Lm_H > 0 && n_xfmr > 0)
      ? vin / (n_xfmr * n_xfmr * Lm_H) / 1e6 : 0;
    // Sn_Aus for display: total slope (inductor + mag)
    const Sn_Aus = Sn_inductor_Aus + Sn_mag_Aus;
    // Aux secondary contributions (A/µs, same frame as Sn_Aus)
    let Sn_aux_Aus = 0;
    if (p.lmAffectsSn && p.topology !== "flyback" && p.auxSecondaries && p.auxSecondaries.length > 0 && n_xfmr > 0) {
      const Vin_pri = vin / n_xfmr;
      for (const aux of p.auxSecondaries) {
        const nj = (aux.ns || 0) / Math.max(p.Np || 1, 1);
        const Lj = (aux.lout_uH || 0) * 1e-6;
        const Vj = aux.vout || 0;
        if (nj > 0 && Lj > 1e-9 && Vj > 0) {
          const sn_j = (Vin_pri * nj - Vj) / Lj * nj / n_xfmr / 1e6;
          if (sn_j > 0) Sn_aux_Aus += sn_j;
        }
      }
    }
    // gm_ps correction: Lm ramp + aux slopes are equivalent external slope
    const mc_gmps = (Sn_inductor_Aus > 0) ? (Sn_inductor_Aus + sc + Sn_mag_Aus + Sn_aux_Aus) / Sn_inductor_Aus : 1;
    const gm_ps = (mc_gmps > 1 && Sn_inductor_Aus > 0) ? gm_ps_table / mc_gmps : gm_ps_table;
    const Gvc0_dB = dB(gm_ps * rload);
    // He(s) sampling: ALWAYS uses real SC + Lm + aux equivalent for mc (physical effect)
    const mc_he = Sn_inductor_Aus > 0 ? 1 + (sc_he + Sn_mag_Aus + Sn_aux_Aus) / Sn_inductor_Aus : 1;
    const factor_he = mc_he * Dprime - 0.5;
    const Qp_he = factor_he > 0.01 ? 1 / (Math.PI * factor_he) : 999;
    const fn_he = fsw_hz / Math.PI;
    return { D, Dprime, mc: mc_he, Qp: Qp_he, fp1, fz_esr, fz_esr_scalar, fz_esr_method,
      Gvc0_dB, rload, factor: factor_he, sn: Sn_Aus, sn_inductor: Sn_inductor_Aus, sn_mag: Sn_mag_Aus, Io_crit, mode, Ti0:999,
      f0_LC, Fm:0, fp_dcm:undefined, Reff_dcm:undefined,
      ctrlMode:"gmps", placement, gm_ps, gm_ps_table, sc_aus: sc, sc_aus_he: sc_he, Sn_Aus, fn_he, mc_gmps };
  }

  // Standard decomposed model
  const sn_inductor = (vin - vout) / Math.max(L, 1e-9); // A/s of secondary inductor current
  // Lm correction (Chen, Huang & Chen 2007; IET Power Electronics 2013):
  // When sensing on primary, the magnetizing ramp adds to the comparator slope.
  // This acts as EQUIVALENT EXTERNAL SLOPE (like Se), NOT as part of the natural inductor slope.
  // Sn_mag = Vin_eff / (n² × Lm) — magnetizing current ramp referred to secondary
  const n_xfmr = p.n || 1;
  const Lm_H = p.Lm_H || 0;
  const sn_mag = (p.lmAffectsSn && Lm_H > 0 && n_xfmr > 0)
    ? vin / (n_xfmr * n_xfmr * Lm_H) : 0; // A/s referred to secondary
  // Sn at comparator (V/s) — inductor only (this is the "natural" slope)
  const sn = sn_inductor * ri;
  // Equivalent external slope from magnetizing ramp (V/s)
  const se_mag = sn_mag * ri;
  // Equivalent external slope from auxiliary (unregulated) secondary windings
  // Each aux secondary contributes additional primary current slope the comparator sees
  // NOTE: Only applies to forward converter. Flyback aux windings carry zero current during on-time.
  let se_aux = 0;
  if (p.lmAffectsSn && p.topology !== "flyback" && p.auxSecondaries && p.auxSecondaries.length > 0 && n_xfmr > 0) {
    const Vin_pri = vin / n_xfmr; // primary-side Vin
    for (const aux of p.auxSecondaries) {
      const nj = (aux.ns || 0) / Math.max(p.Np || 1, 1);
      const Lj = (aux.lout_uH || 0) * 1e-6;
      const Vj = aux.vout || 0;
      if (nj > 0 && Lj > 1e-9 && Vj > 0) {
        // Aux inductor slope at secondary j, reflected to regulated secondary frame
        const sn_aux_j = (Vin_pri * nj - Vj) / Lj * nj / n_xfmr;
        if (sn_aux_j > 0) se_aux += sn_aux_j * ri;
      }
    }
  }
  // mc = 1 + (Se_external + Se_magnetizing + Se_aux) / Sn_inductor
  // When Se=0 but Lm is finite: mc > 1 → free slope comp from magnetizing current
  const mc = 1 + (sn > 0 ? (se + se_mag + se_aux) / sn : 0);
  const factor = mc * Dprime - 0.5;
  const ctrlMode = "peak";
  const Qp = factor > 0.01 ? 1 / (Math.PI * factor) : 999;
  const Gvc0_dB = dB(rload / Math.max(ri, 1e-6));
  const Fm = fsw_hz / Math.max(sn * mc, 1e-12);
  const Ti0 = isFinite(Fm) ? Fm * (vin / rload) * ri : 999;
  let fp_dcm = undefined, Reff_dcm = undefined;
  if (mode === "DCM") {
    const D_dcm = Math.sqrt(Math.max(2 * L * iout * fsw_hz / Math.max(vin - vout, 0.01), 1e-12));
    const Re = 2 * L * fsw_hz / Math.max(D_dcm * D_dcm, 1e-9);
    Reff_dcm = (rload * Re) / (rload + Re);
    fp_dcm = 1 / (TWO_PI * Reff_dcm * cout);
  }
  return { D, Dprime, mc, Qp, fp1, fz_esr, fz_esr_scalar, fz_esr_method, Gvc0_dB, rload, factor, sn, sn_inductor, sn_mag, Io_crit, mode, Ti0, f0_LC, Fm, fp_dcm, Reff_dcm, ctrlMode, placement };
}

function evalCompType2(f, fz_c, fp_c, fi) {
  const w = TWO_PI * f;
  const num = C(1, w / (TWO_PI * fz_c));
  const den = C(1, w / (TWO_PI * fp_c));
  const integ = cdiv(C(TWO_PI * fi, 0), C(0, w));
  return cmul(integ, cdiv(num, den));
}

// Type-III: integrator + two zeros + two poles
// Gc(s) = (fi/s) · (1+s/ωz1)(1+s/ωz2) / ((1+s/ωp1)(1+s/ωp2))
function evalCompType3(f, fz1, fz2, fp1, fp2, fi) {
  const w = TWO_PI * f;
  const nz1 = C(1, w / (TWO_PI * fz1));
  const nz2 = C(1, w / (TWO_PI * fz2));
  const dp1 = C(1, w / (TWO_PI * fp1));
  const dp2 = C(1, w / (TWO_PI * fp2));
  const integ = cdiv(C(TWO_PI * fi, 0), C(0, w));
  return cmul(integ, cdiv(cmul(nz1, nz2), cmul(dp1, dp2)));
}

// Generic comp evaluator
function evalComp(f, comp) {
  if (comp.type === "type3") {
    return evalCompType3(f, comp.fz1, comp.fz2, comp.fp1, comp.fp2, comp.fi);
  }
  return evalCompType2(f, comp.fz_c, comp.fp_c, comp.fi);
}

// ─── Error Amplifier Models ──────────────────────────────────
// Op-amp EA: Gea(s) = Aol / ((1 + s/ωp1) · (1 + s/ωp2))
function evalEA_opamp(f, Aol_dB, GBW_MHz, PM_ea_deg) {
  const Aol = Math.pow(10, Aol_dB / 20);
  const GBW = GBW_MHz * 1e6;
  const fp1 = GBW / Aol; // dominant pole
  const PM_ea_rad = (PM_ea_deg || 60) * Math.PI / 180;
  const fp2 = GBW * Math.tan(PM_ea_rad); // HF pole sets EA's own phase margin
  const w = TWO_PI * f;
  const den1 = C(1, w / (TWO_PI * fp1));
  const den2 = C(1, w / (TWO_PI * fp2));
  return cdiv(C(Aol, 0), cmul(den1, den2));
}

// OTA/gm EA: Gea(s) = gm · Zout(s) = gm · Rout / (1 + s·Rout·Cout)
function evalEA_ota(f, gm_uAV, Rout_MOhm, Cout_pF) {
  const gm = gm_uAV * 1e-6;
  const Rout = Rout_MOhm * 1e6;
  const Cout_ea = Cout_pF * 1e-12;
  const w = TWO_PI * f;
  const Zout = cdiv(C(Rout, 0), C(1, w * Rout * Cout_ea));
  return cscale(Zout, gm);
}

// OTA EA output impedance as complex Z(s) — needed for OTA comp loading
function evalEA_ota_Zout(f, Rout_MOhm, Cout_pF) {
  const Rout = Rout_MOhm * 1e6;
  const Cout_ea = Cout_pF * 1e-12;
  const w = TWO_PI * f;
  return cdiv(C(Rout, 0), C(1, w * Rout * Cout_ea));
}

function evalEA(f, ea) {
  if (ea.type === "opamp") return evalEA_opamp(f, ea.Aol_dB, ea.GBW_MHz, ea.PM_ea_deg);
  if (ea.type === "ota") return evalEA_ota(f, ea.gm_uAV, ea.Rout_MOhm, ea.Cout_pF);
  return C(1e12, 0);
}

// ─── Impedance-Based Compensator ─────────────────────────────
// Type-II network impedance: (R2 + 1/sC2) || (1/sC1)
// This is the physical comp network seen from the COMP pin to GND
function evalZcomp_type2(f, R1, R2, C1, C2) {
  const w = TWO_PI * f;
  // Branch A: R2 in series with C2 → Z_a = R2 + 1/(sC2)
  const Za = C(R2, -1 / (w * C2));
  // Branch B: C1 alone → Z_b = 1/(sC1)
  const Zb = C(0, -1 / (w * C1));
  // Parallel: Za || Zb = Za·Zb/(Za+Zb)
  return cdiv(cmul(Za, Zb), cadd(Za, Zb));
}

// Type-III network impedance: (R2+1/sC2)||(1/sC1) for feedback, plus R3+1/sC3 path
// For OTA: Zcomp = (R2+1/sC2) || (1/sC1) || (R3+1/sC3)
function evalZcomp_type3(f, R1, R2, R3, C1, C2, C3) {
  const w = TWO_PI * f;
  const Za = C(R2, -1 / (w * C2));      // R2 + 1/sC2
  const Zb = C(0, -1 / (w * C1));        // 1/sC1
  const Zc = C(R3, -1 / (w * C3));       // R3 + 1/sC3
  // Three-way parallel: 1/Ztotal = 1/Za + 1/Zb + 1/Zc
  const Ya = cdiv(C(1,0), Za);
  const Yb = cdiv(C(1,0), Zb);
  const Yc = cdiv(C(1,0), Zc);
  return cdiv(C(1,0), cadd(cadd(Ya, Yb), Yc));
}

// Complex parallel: Za || Zb = Za·Zb / (Za+Zb)
function cparallel(Za, Zb) {
  return cdiv(cmul(Za, Zb), cadd(Za, Zb));
}

// EA-corrected compensator — architecture-dependent
function evalCompWithEA(f, comp, ea) {
  const Gc = evalComp(f, comp);
  if (ea.type === "ideal") return Gc;

  if (ea.type === "ota") {
    // OTA: Gc_real = gm × (Zcomp || Zout_ea)
    // Zcomp must use OTA component decomposition (RCOMP/CCOMP/CHF), NOT op-amp R1/R2/C1/C2
    const gm = ea.gm_uAV * 1e-6;
    const w = TWO_PI * f;

    // OTA Type-II: CCOMP = gmEA/(2π·fi), RCOMP = 1/(2π·fz·CCOMP), CHF = 1/(2π·fp·RCOMP)
    // OTA Type-III: same gmEA-based decomposition
    let Zcomp;
    if (comp.type === "type3") {
      // Type-III with OTA: use abstract params to derive OTA network
      // For now, fall back to ideal (Type-III with OTA is uncommon)
      return Gc;
    } else {
      // OTA Type-II: RCOMP + CCOMP in series, CHF in parallel
      const CCOMP = gm / (TWO_PI * Math.max(comp.fi, 1));
      const RCOMP = 1 / (TWO_PI * Math.max(comp.fz_c, 1) * CCOMP);
      const CHF = 1 / (TWO_PI * Math.max(comp.fp_c, 1) * RCOMP);
      // Z_series = RCOMP + 1/(s·CCOMP)
      const Zseries = C(RCOMP, -1 / (w * CCOMP));
      // Z_chf = 1/(s·CHF)
      const Zchf = C(0, -1 / (w * CHF));
      // Zcomp = Zseries || Zchf
      Zcomp = cparallel(Zseries, Zchf);
    }

    // EA output impedance: Zout_ea = Rout / (1 + s·Rout·Cout)
    // When Cout is 0 or very small, Zout_ea ≈ Rout (negligible loading)
    const Rout = ea.Rout_MOhm * 1e6;
    const Cout_ea = (ea.Cout_pF || 0) * 1e-12;
    let Ztotal;
    if (Cout_ea > 0) {
      const Zout_ea = cdiv(C(Rout, 0), C(1, w * Rout * Cout_ea));
      Ztotal = cparallel(Zcomp, Zout_ea);
    } else {
      // No internal Cout — Rout is so large it's negligible vs Zcomp
      Ztotal = Rout > 1e6 ? Zcomp : cparallel(Zcomp, C(Rout, 0));
    }
    return cscale(Ztotal, gm);
  }

  // Op-amp: standard loading correction Gc_real = Gc / (1 + Gc/Gea_ol)
  const Gea = evalEA(f, ea);
  const ratio = cdiv(Gc, Gea);
  return cdiv(Gc, cadd(C(1, 0), ratio));
}

function getEAInfo(ea) {
  if (ea.type === "opamp") {
    const Aol = Math.pow(10, ea.Aol_dB / 20);
    const GBW = ea.GBW_MHz * 1e6;
    const fp1 = GBW / Aol;
    const Aol_dB = ea.Aol_dB;
    return { Aol_dB, GBW_Hz: GBW, fp1_ea: fp1, type: "opamp" };
  }
  if (ea.type === "ota") {
    const gm = ea.gm_uAV * 1e-6;
    const Rout = ea.Rout_MOhm * 1e6;
    const Cout_ea = (ea.Cout_pF || 0) * 1e-12;
    const Aol = gm * Rout;
    const Aol_dB = dB(Aol);
    if (Cout_ea > 0) {
      const fp1 = 1 / (TWO_PI * Rout * Cout_ea);
      const GBW = Aol * fp1;
      return { Aol_dB, GBW_Hz: GBW, fp1_ea: fp1, gm, Rout, type: "ota" };
    } else {
      // No internal Cout — OTA has no dominant pole. GBW is gm transconductance BW (if known) or effectively infinite.
      return { Aol_dB, GBW_Hz: 1e12, fp1_ea: 1e9, gm, Rout, type: "ota", noCout: true };
    }
  }
  return { Aol_dB: 999, GBW_Hz: 1e12, fp1_ea: 1e9, type: "ideal" };
}

// CS-to-output propagation delay: first-order Padé
// Gdelay(s) ≈ (1 - s·td/2) / (1 + s·td/2)
function evalDelay(f, td_ns) {
  if (!td_ns || td_ns <= 0) return C(1, 0);
  const td = td_ns * 1e-9;
  const w = TWO_PI * f;
  const half_wtd = w * td / 2;
  return cdiv(C(1, -half_wtd), C(1, half_wtd));
}

function evalFeedback(vref, vout) { return vref / Math.max(vout, 0.01); }

// Frequency-dependent feedback for isolated topologies with opto pole
// H(f) = H_dc / (1 + jf/fp_opto)  — Basso APEC 2010, slide 99–100
// When fp_opto = 0 or non-isolated, returns scalar H_dc as complex [H_dc, 0]
function evalOptoH(f, H_dc, fp_opto) {
  if (!fp_opto || fp_opto <= 0) return C(H_dc, 0);
  const w = TWO_PI * f;
  const wp = TWO_PI * fp_opto;
  // H_dc × wp / (wp + jw) = H_dc / (1 + jw/wp)
  return cdiv(C(H_dc * wp, 0), C(wp, w));
}

// ─── Individual inner-loop sub-blocks (for visualization) ───
// These are the PHYSICAL blocks from the block diagram.
// The Ridley model absorbs them into Gvc(s) analytically.

// Fm: Modulator gain. d̂/v̂c = fsw / (total_slope_at_comparator)
// Peak CM: Sn = (Vin−Vout)/L · Ri is the natural inductor slope
// Flyback: Sn = Vin_pri / Lm · Ri (full Vin across Lm during on-time)
// For 2SW forward with primary sensing: Lm ramp acts as equivalent Se
// Fm = fsw / (Sn_inductor × mc) where mc = 1 + (Se + Se_mag) / Sn
function getFm(p) {
  const { vin, vout, fsw_hz, L, ri, se } = p;
  // Flyback: Sn = Vin_pri / Lm (not (Vin-Vout)/L)
  if (p.topology === "flyback") {
    const n = p.n || 1;
    const Lm_H = p.Lm_H || L;
    const Vin_pri = vin / Math.max(n, 0.001);
    const Sn = (Vin_pri / Math.max(Lm_H, 1e-9)) * ri;
    const mc = 1 + (Sn > 0 ? se / Sn : 0);
    return fsw_hz / Math.max(Sn * mc, 1e-12);
  }
  // Buck / 2SW forward path
  const sn_inductor = (vin - vout) / Math.max(L, 1e-9);
  const n_xfmr = p.n || 1;
  const Lm_H = p.Lm_H || 0;
  const sn_mag = (p.lmAffectsSn && Lm_H > 0 && n_xfmr > 0)
    ? vin / (n_xfmr * n_xfmr * Lm_H) : 0;
  const Sn = sn_inductor * ri;  // V/s — inductor only
  const se_mag = sn_mag * ri;   // V/s — Lm equivalent external slope
  // Aux secondary contributions (same as in getPlantInfo)
  let se_aux = 0;
  if (p.lmAffectsSn && p.topology !== "flyback" && p.auxSecondaries && p.auxSecondaries.length > 0 && n_xfmr > 0) {
    const Vin_pri = vin / n_xfmr;
    for (const aux of p.auxSecondaries) {
      const nj = (aux.ns || 0) / Math.max(p.Np || 1, 1);
      const Lj = (aux.lout_uH || 0) * 1e-6;
      const Vj = aux.vout || 0;
      if (nj > 0 && Lj > 1e-9 && Vj > 0) {
        const sn_aux_j = (Vin_pri * nj - Vj) / Lj * nj / n_xfmr;
        if (sn_aux_j > 0) se_aux += sn_aux_j * ri;
      }
    }
  }
  const mc = 1 + (Sn > 0 ? (se + se_mag + se_aux) / Sn : 0);
  return fsw_hz / Math.max(Sn * mc, 1e-12);
}

// Gid(s): Duty-to-inductor-current. Buck CCM: îL/d̂ = Vin/(sL + Zo(s))
function evalGid(f, p) {
  const { vin, vout, iout, L } = p;
  const rload = vout / Math.max(iout, 0.001);
  const w = TWO_PI * f;
  const zc = p.capBank ? evalZcapBank(f, p.capBank) : C(p.esr, -1 / (w * Math.max(p.cout, 1e-12)));
  const zr = C(rload, 0);
  const zo = cparallel(zr, zc);
  const sL = C(0, w * L);
  return cdiv(C(vin, 0), cadd(sL, zo));
}

// Gvi(s): Inductor-current-to-output-voltage. v̂o/îL = Zo(s) = Rload||(1/sCout+ESR)
function evalGvi(f, p) {
  const { vout, iout } = p;
  const rload = vout / Math.max(iout, 0.001);
  const w = TWO_PI * f;
  const zc = p.capBank ? evalZcapBank(f, p.capBank) : C(p.esr, -1 / (w * Math.max(p.cout, 1e-12)));
  const zr = C(rload, 0);
  return cparallel(zr, zc);
}

// Gvd(s): Duty-to-output voltage (pure voltage-mode, no current feedback)
// Gvd = Vin · (1 + s·Cout·ESR) / (s²·L·Cout + s·(L/Rload + Cout·ESR) + 1)
// This is what the plant looks like with NO current sensing — pure LC double-pole
function evalGvd(f, p) {
  const { vin, vout, iout, L } = p;
  const rload = vout / Math.max(iout, 0.001);
  const w = TWO_PI * f;
  // Gvd = Vin · Zo(s) / (sL + Zo(s)) where Zo = Rload || Zcap
  const zc = p.capBank ? evalZcapBank(f, p.capBank) : C(p.esr, -1 / (w * Math.max(p.cout, 1e-12)));
  const zr = C(rload, 0);
  const zo = cparallel(zr, zc);
  const sL = C(0, w * L);
  return cscale(cdiv(zo, cadd(sL, zo)), vin);
}

// He(s): Sampled-data correction only (separated from Ri)
// Peak CM: factor = mc·D' − 0.5 (instability at D > 50%)
function evalHe(f, p) {
  const { vin, vout, fsw_hz, L, ri, se } = p;
  const Dprime = 1 - vout / Math.max(vin, 0.01);
  const sn = ((vin - vout) / Math.max(L, 1e-9)) * ri;
  const mc = 1 + (sn > 0 ? se / sn : 0);
  const factor = mc * Dprime - 0.5;
  const Qp = factor > 0.01 ? 1 / (Math.PI * factor) : 100;
  const w = TWO_PI * f;
  const wn = TWO_PI * fsw_hz / Math.PI;
  return C(1 - (w / wn) ** 2, w / (Qp * wn));
}

// ─── Phase 6: Audio Susceptibility ──────────────────────────
// Zout_open(s): open-loop output impedance (no voltage feedback)
// Standard: Zout_open = Gvi(s) / (1 + Ti(s))
//   where Ti = Fm·Gid·Kcs is the inner current loop gain
// gm_ps: Zout_open ≈ Rload || Zcap (current source has infinite output impedance)
function evalZout_open(f, p) {
  if (p.plantMode === "gmps" || p.topology === "flyback") {
    // gm_ps or flyback: inner loop makes converter act as current source
    // Zout_open ≈ Rload || Zcap(s)
    // (flyback has no valid Gvi/Gid sub-block decomposition)
    const rload = p.vout / Math.max(p.iout, 0.001);
    const w = TWO_PI * f;
    const zc = p.capBank ? evalZcapBank(f, p.capBank) : C(p.esr, -1 / (w * Math.max(p.cout, 1e-12)));
    return cparallel(C(rload, 0), zc);
  }
  // Standard: Gvi / (1 + Ti)
  const gvi = evalGvi(f, p);
  const kcs = p.senseParams ? evalSenseChain(f, p.senseParams) : C(p.ri, 0);
  const Fm = getFm(p);
  const gid = evalGid(f, p);
  const ti = cmul(cscale(gid, Fm), kcs);
  return cdiv(gvi, cadd(C(1, 0), ti));
}

// Zout_closed(s): closed-loop output impedance (with voltage feedback)
// Zout_cl = Zout_open / (1 + T(s))
function evalZout_closed(f, p, comp, ea, td_ns) {
  const zo = evalZout_open(f, p);
  const Gp = evalPlant(f, p);
  const Gc = evalCompWithEA(f, comp, ea || {type:"ideal"});
  const Gd = evalDelay(f, td_ns || 0);
  const H_dc = evalFeedback(p.vref, p.vout) * (p.optoGain || 1);
  const Hf = evalOptoH(f, H_dc, p.fp_opto || 0);
  const cg = p.compGain || 1;
  const T = cmul(cmul(cmul(Gc, cscale(Gp, cg)), Gd), Hf);
  return cdiv(zo, cadd(C(1, 0), T));
}

// Gvg_open(s): open-loop audio susceptibility (vin-to-vout, no voltage feedback)
// Standard: Gvg_ol = D · Gvi(s) / (1 + Ti(s))
//   Current loop rejects Vin disturbances. At DC: Gvg ≈ D·Rload / (1 + Ti(0))
// gm_ps: Gvg_ol ≈ D · Zout(s) / (1 + gm_ps · Zout(s) · He(s))
//   At DC: gm_ps · Rload ≫ 1 → Gvg ≈ 0 (excellent line rejection)
//   At HF: He(s) rolls off → Gvg increases (degraded rejection)
function evalGvg_open(f, p) {
  const D = p.vout / Math.max(p.vin, 0.01);

  if (p.plantMode === "gmps") {
    // gm_ps model: Gvg ≈ D · Zout / (1 + gm_ps_eff · Zout · He)
    const rload = p.vout / Math.max(p.iout, 0.001);
    const w = TWO_PI * f;
    const zc = p.capBank ? evalZcapBank(f, p.capBank) : C(p.esr, -1 / (w * Math.max(p.cout, 1e-12)));
    const zout = cparallel(C(rload, 0), zc);
    const gm_ps_table = p.gm_ps || 20;
    const fsw_hz = p.fsw_hz || 500e3;
    const sc_gmps = Math.abs(p.sc_aus || 0);
    const sc_he = Math.abs(p.sc_aus_he != null ? p.sc_aus_he : p.sc_aus || 0);
    const L = p.L || 1e-6;
    const Sn = L > 0 ? (p.vin - p.vout) / Math.max(L, 1e-12) / 1e6 : 999;
    const gm_ps = (sc_gmps > 0 && Sn > 0) ? gm_ps_table * Sn / (Sn + sc_gmps) : gm_ps_table;
    // He(s) for inner loop rejection
    const Dp = 1 - D;
    const mc_he = (sc_he > 0 && Sn > 0) ? 1 + sc_he / Sn : 1;
    const factor = mc_he * Dp - 0.5;
    const fn = fsw_hz / Math.PI;
    const wn = TWO_PI * fn;
    let He;
    if (factor > 0.01) {
      const Qp = 1 / (Math.PI * factor);
      const norm = w / wn;
      He = cdiv(C(1, 0), C(1 - norm * norm, norm / Qp));
    } else {
      He = C(1, 0);
    }
    // Gvg = D · Zout / (1 + gm_ps · Zout · He)
    const inner = cmul(cscale(zout, gm_ps), He);
    return cdiv(cscale(zout, D), cadd(C(1, 0), inner));
  }

  // Standard decomposed: Gvg = D · Gvi / (1 + Ti)
  const gvi = evalGvi(f, p);
  const kcs = p.senseParams ? evalSenseChain(f, p.senseParams) : C(p.ri, 0);
  const Fm = getFm(p);
  const gid = evalGid(f, p);
  const ti = cmul(cscale(gid, Fm), kcs);
  let gvg = cdiv(cscale(gvi, D), cadd(C(1, 0), ti));
  // Feedforward correction from magnetizing inductance (Chen, Huang & Chen 2007)
  // When sensing on primary, Vin perturbation changes magnetizing slope → shifts duty
  // kf = (1 - 2D) / (2·fsw·Lm) [1/V·s units at primary]
  // Effect: modifies D_eff in Gvg numerator by adding Vin→d feedforward path
  // kf > 0 for D < 0.5: feedforward partially cancels Vin disturbance (helps PSRR)
  // kf < 0 for D > 0.5: feedforward adds to Vin disturbance (hurts PSRR)
  // Approximation: multiply by (1 + kf × Vin_pri × Ri / (Sn × mc × D))
  if (p.lmAffectsSn && p.Lm_H > 0 && p.n > 0) {
    const Vin_pri = p.vin / p.n;
    const Lm_H = p.Lm_H;
    const Sn = Vin_pri / Math.max(Lm_H, 1e-9) * p.ri; // V/s at comparator from Lm
    const sn_ind = (p.vin - p.vout) / Math.max(p.L, 1e-9) * p.ri;
    const mc = 1 + (sn_ind > 0 ? (p.se + Sn) / sn_ind : 0);
    const kf = (1 - 2 * D) / (2 * p.fsw_hz * Lm_H);
    const kf_factor = kf * Vin_pri * p.ri / Math.max(sn_ind * mc * D, 1e-12);
    gvg = cscale(gvg, 1 + kf_factor);
  }
  return gvg;
}

// Gvg_closed(s): closed-loop audio susceptibility (with voltage feedback)
// Gvg_cl = Gvg_ol / (1 + T(s))
function evalGvg_closed(f, p, comp, ea, td_ns) {
  const gvg = evalGvg_open(f, p);
  const Gp = evalPlant(f, p);
  const Gc = evalCompWithEA(f, comp, ea || {type:"ideal"});
  const Gd = evalDelay(f, td_ns || 0);
  const H_dc = evalFeedback(p.vref, p.vout) * (p.optoGain || 1);
  const Hf = evalOptoH(f, H_dc, p.fp_opto || 0);
  const cg = p.compGain || 1;
  const T = cmul(cmul(cmul(Gc, cscale(Gp, cg)), Gd), Hf);
  return cdiv(gvg, cadd(C(1, 0), T));
}

// Ti(s): Physical inner current-loop gain = Fm · Gid(s) · Kcs(s)
// NO He(s) — He is Ridley's analytical sampling correction, not part of the physical loop.
function evalTi(f, p) {
  const Fm = getFm(p);
  const gid = evalGid(f, p);
  const kcs = p.senseParams ? evalSenseChain(f, p.senseParams) : C(p.ri, 0);
  return cmul(cscale(gid, Fm), kcs);
}

// Gvc_ridley(s): Ridley closed-form for comparison (sub-blocks view)
// Only valid when Ti(0)>>1. Shows deviation from closure model at high mc.
function evalGvcRidley(f, p) {
  return evalPlantRidley(f, p);
}

function evalInputFilterZout(f, lin, cin, rd) {
  const w = TWO_PI * f;
  const zl = C(0, w * lin);
  const zc = C(rd, -1 / (w * Math.max(cin, 1e-12)));
  return cdiv(cmul(zl, zc), cadd(zl, zc));
}
function converterZin(vin, vout, iout) {
  const pout = vout * iout;
  return pout < 0.01 ? 1e6 : vin * vin / pout;
}

// ─── Phase 7: Averaged Nonlinear Time-Domain Simulation ─────
// State vector: [iL, vC, xc1, xc2]
//   iL   = inductor current (A)
//   vC   = capacitor voltage (V) — Vout ≈ vC + ESR·iC
//   xc1  = compensator state 1 (integrator accumulator)
//   xc2  = compensator state 2 (lead-lag filter)
//
// Compensator state-space (Type-II, controllable canonical form):
//   Gc(s) = ωi·(1+s/ωz) / (s·(1+s/ωp))
//   dxc1/dt = xc2
//   dxc2/dt = −ωp·xc2 + error
//   vcomp   = K1·xc1 + K2·xc2   where K1=ωi·ωp, K2=ωi·ωp/ωz
//
// Plant (averaged CCM buck):
//   D = f(vcomp, iL, Sn, Se, fsw)  — peak CM comparator equation
//   diL/dt = (Vin·D − vC − ESR·(iL − iout)) / L
//   dvC/dt = (iL − iout) / C

function simTimeDomain(cfg) {
  const {
    vin: vin0, vout_nom, iout: iout0, L, Ceff, ESR, fsw_hz,
    ri, se_vs, vref, H,
    comp, ea,
    clampLow, clampHigh,
    slewSource_Aus, slewSink_Aus,
    plantMode, gm_ps: gm_ps_val,
    Dmax,
    stimulus,
    tTotal_us, nPts,
  } = cfg;

  // ─── Compensator: direct parallel decomposition ─────────
  // Gc(s) = (ωi/s) × (1+s/ωz)/(1+s/ωp) = Ki/s + Kp/(s+ωp)
  // where Ki = ωi, Kp = ωi×(ωp−ωz)/ωz
  //
  // For Type-III: Gc = Ki/s + Kp1/(s+ωp1) + Kp2/(s+ωp2)
  //
  // Both paths see full error signal directly — no cascade attenuation.
  // States: [iL, vC, x_filt1, x_filt2, x_int]
  //   x_int: integrator (carries DC operating point)
  //   x_filt1: first-order filter for pole 1
  //   x_filt2: first-order filter for pole 2 (Type-III only)
  //   vcomp = x_int + x_filt1 + x_filt2
  //
  const isType3 = comp.type === "type3";
  const ωi = TWO_PI * (comp.fi || 1e3);
  const ωz1 = TWO_PI * (isType3 ? (comp.fz1 || 1e3) : (comp.fz_c || 1e3));
  const ωp1 = TWO_PI * (isType3 ? (comp.fp1 || 50e3) : (comp.fp_c || 50e3));
  const ωz2 = isType3 ? TWO_PI * (comp.fz2 || 5e3) : 0;
  const ωp2 = isType3 ? TWO_PI * (comp.fp2 || 150e3) : 0;

  // Integrator gain (same for both types)
  const Ki = ωi;

  // Filter gains via partial fractions
  let Kp1, Kp2;
  if (isType3) {
    // Gc(s) = K_total × (s+ωz1)(s+ωz2) / (s(s+ωp1)(s+ωp2))
    // K_total = ωi × ωp1×ωp2 / (ωz1×ωz2)
    const Kt = ωi * ωp1 * ωp2 / (ωz1 * ωz2);
    Kp1 = Kt * (ωp1 - ωz1) * (ωp1 - ωz2) / (ωp1 * (ωp1 - ωp2));
    Kp2 = Kt * (ωp2 - ωz1) * (ωp2 - ωz2) / (ωp2 * (ωp2 - ωp1));
  } else {
    // Type-II: Kp = ωi × (ωp − ωz) / ωz
    Kp1 = ωi * (ωp1 - ωz1) / ωz1;
    Kp2 = 0;
  }

  const slewUp = slewSource_Aus > 0 ? slewSource_Aus : 1e15;
  const slewDn = slewSink_Aus > 0 ? slewSink_Aus : 1e15;

  // Current-mode modulator
  const isFlyback_td = cfg.topology === "flyback";
  const n_td = cfg.n || 1;
  const Lm_td = cfg.Lm_H || L;
  const Sn_vs = isFlyback_td
    ? (vin0 / Math.max(n_td, 1e-6)) / Math.max(Lm_td, 1e-12) * ri  // Vin_pri/Lm × Ri
    : (vin0 - vout_nom) / Math.max(L, 1e-12) * ri;                   // (Vin-Vout)/L × Ri
  const mc = 1 + (Sn_vs > 0 ? se_vs / Sn_vs : 0);
  const Sn_total = Sn_vs + se_vs; // total on-slope at comparator = Sn + Se

  // gm_ps sampling delay modeled via reduced tracker BW (fsw/6)
  // This first-order lag adds realistic compensator propagation time
  const bw_inner = fsw_hz / 6;

  // Time stepping
  const tTotal = (tTotal_us || 500) * 1e-6;
  const N = nPts || 600;
  const dt = Math.min(tTotal / N, 1 / (fsw_hz * 20));
  const steps = Math.ceil(tTotal / dt);
  const decimation = Math.max(1, Math.floor(steps / N));

  // Stimulus
  const stim = stimulus || { type: "load_step", amplitude: 2, riseTime_us: 1, tStart_us: 50 };
  const tStim = (stim.tStart_us || 50) * 1e-6;
  const tRise = Math.max((stim.riseTime_us || 1) * 1e-6, dt);
  const stimAmp = stim.amplitude != null ? stim.amplitude : 2;
  function getStimulus(t) {
    if (t < tStim) return 0;
    return stimAmp * Math.min((t - tStim) / tRise, 1);
  }

  // Duty cycle from COMP voltage
  function computeD(vcomp, iL, vin_now) {
    if (plantMode === "gmps") {
      const iL_target = gm_ps_val * Math.max(vcomp - (clampLow || 0), 0);
      const error_i = iL_target - iL;
      const diL_target = TWO_PI * bw_inner * error_i;
      const D = (L * diL_target + vout_nom) / Math.max(vin_now, 0.1);
      return Math.max(0, Math.min(Dmax || 0.95, D));
    }
    if (Sn_total <= 0) return 0.5;
    const D = (vcomp - ri * iL) * fsw_hz / Sn_total;
    return Math.max(0, Math.min(Dmax || 0.95, D));
  }

  // State: [iL, vC, x_filt1, x_filt2, x_int]
  function deriv(state, vin_now, iout_now) {
    const iL = state[0], vC = state[1], xf1 = state[2], xf2 = state[3], xint = state[4];
    const vcomp = Math.max(clampLow || 0, Math.min(clampHigh || 5, xint + xf1 + xf2));

    // Compute topology-correct output voltage for feedback
    let iC, vout_sense, diL, dvC;
    if (isFlyback_td) {
      const D = computeD(vcomp, iL, vin_now);
      const Dp = 1 - D;
      iC = iL * Dp - iout_now;  // flyback: secondary current only flows during D'
      vout_sense = vC + ESR * iC;
      const Lm_sec = Lm_td * n_td * n_td;
      diL = (vin_now * D - vout_sense * Dp) / Math.max(Lm_sec > 0 ? Lm_sec : L, 1e-12);
      dvC = iC / Math.max(Ceff, 1e-12);
    } else if (plantMode === "gmps") {
      iC = iL - iout_now;
      vout_sense = vC + ESR * iC;
      const iL_target_raw = gm_ps_val * Math.max(vcomp - (clampLow || 0), 0);
      const iL_limit = Math.max(3 * iout_now, iout_now + 10);
      const iL_target = Math.min(iL_target_raw, iL_limit);
      const tau_track = 1 / (TWO_PI * bw_inner);
      diL = (iL_target - iL) / tau_track;
      dvC = iC / Math.max(Ceff, 1e-12);
    } else {
      iC = iL - iout_now;
      vout_sense = vC + ESR * iC;
      const D = computeD(vcomp, iL, vin_now);
      diL = (vin_now * D - vC - ESR * iC) / Math.max(L, 1e-12);
      dvC = iC / Math.max(Ceff, 1e-12);
    }

    // Error signal: must be zero at operating point (vout = vout_nom)
    // H × (Vout_nom − Vout) gives correct equilibrium AND same linearized gain as Bode
    // (For non-isolated with optoGain=1: H×Vout_nom = vref, so this equals vref − H×Vout)
    const error = H * (vout_nom - vout_sense);
    const dxf1 = -ωp1 * xf1 + Kp1 * error;
    const dxf2 = isType3 ? (-ωp2 * xf2 + Kp2 * error) : 0;
    const dxint = Ki * error;

    return [diL, dvC, dxf1, dxf2, dxint];
  }

  // ─── Steady-state initial conditions ───────────────────
  const D_ss = isFlyback_td ? vout_nom / Math.max(vout_nom + vin0, 0.01) : vout_nom / Math.max(vin0, 0.01);
  const Dp_ss = 1 - D_ss;
  // Flyback: iL state is secondary-referred magnetizing current. At SS: iL×D' = Iout → iL = Iout/D'
  const iL_ss = isFlyback_td ? iout0 / Math.max(Dp_ss, 0.01) : iout0;
  let vcomp_ss;
  if (plantMode === "gmps") {
    vcomp_ss = (clampLow || 0) + iout0 / Math.max(gm_ps_val, 0.01);
  } else {
    vcomp_ss = ri * iL_ss + Sn_total * D_ss / fsw_hz;
  }
  vcomp_ss = Math.max(clampLow || 0, Math.min(clampHigh || 5, vcomp_ss));
  // At SS: error=0 → x_filt1=x_filt2=0, x_int=vcomp_ss
  let state = [iL_ss, vout_nom, 0, 0, vcomp_ss];

  // RK4 integrator (delay is applied externally, not inside deriv)
  function rk4(state, vin_now, iout_now) {
    const k1 = deriv(state, vin_now, iout_now);
    const s2 = state.map((s,i) => s + k1[i]*dt/2);
    const k2 = deriv(s2, vin_now, iout_now);
    const s3 = state.map((s,i) => s + k2[i]*dt/2);
    const k3 = deriv(s3, vin_now, iout_now);
    const s4 = state.map((s,i) => s + k3[i]*dt);
    const k4 = deriv(s4, vin_now, iout_now);
    return state.map((s,i) => s + (k1[i]+2*k2[i]+2*k3[i]+k4[i])*dt/6);
  }

  // ─── Warmup: run closed-loop to true numerical SS ──────
  const fp1_warm = 1 / (TWO_PI * Ceff * (vout_nom / Math.max(iout0, 0.01)));
  const warmupTime = Math.max(5 / Math.max(fp1_warm, 1), 200e-6);
  const warmupSteps = Math.ceil(warmupTime / dt);
  for (let step = 0; step < warmupSteps; step++) {
    let newState = rk4(state, vin0, iout0);
    if (newState[4] > (clampHigh || 5)) newState[4] = clampHigh || 5;
    else if (newState[4] < (clampLow || 0)) newState[4] = clampLow || 0;
    if (newState[0] < 0) newState[0] = 0;
    state = newState;
  }

  // ─── Main loop ─────────────────────────────────────────
  const data = [];
  let clamped = false, dcm_entered = false;
  let slewLimited_src = false, slewLimited_snk = false;
  let peakSlewUp_actual = 0, peakSlewDn_actual = 0;
  let lastSlewState = 0; // 0=none, 1=source, -1=sink

  for (let step = 0; step <= steps; step++) {
    const t = step * dt;
    const stimVal = getStimulus(t);
    let vin_now = vin0, iout_now = iout0;
    if (stim.type === "load_step") iout_now = iout0 + stimVal;
    else if (stim.type === "line_step") vin_now = vin0 + stimVal;

    if (step % decimation === 0) {
      const [iL, vC, xf1, xf2, xint] = state;
      const D_rec = computeD(Math.max(clampLow||0, Math.min(clampHigh||5, xint+xf1+xf2)), iL, vin_now);
      const iC = isFlyback_td ? iL * (1 - D_rec) - iout_now : iL - iout_now;
      const vout = vC + ESR * iC;
      const vcomp = Math.max(clampLow || 0, Math.min(clampHigh || 5, xint + xf1 + xf2));
      data.push({
        t_us: parseFloat((t * 1e6).toFixed(3)),
        vout_mv: parseFloat(((vout - vout_nom) * 1e3).toFixed(2)),
        vout_V: parseFloat(vout.toFixed(4)),
        iL_A: parseFloat(iL.toFixed(4)),
        vcomp_V: parseFloat(vcomp.toFixed(4)),
        D_pct: parseFloat((D_rec * 100).toFixed(2)),
        iout_A: parseFloat(iout_now.toFixed(3)),
        vin_V: parseFloat(vin_now.toFixed(3)),
        slew: lastSlewState, // 0=free, 1=source-limited, -1=sink-limited
      });
    }

    let newState = rk4(state, vin_now, iout_now);

    // Slew rate limiting on total vcomp = x_int + x_filt1 + x_filt2
    const vcomp_old = state[4] + state[2] + state[3];
    const vcomp_new = newState[4] + newState[2] + newState[3];
    const dvcomp_dt = (vcomp_new - vcomp_old) / dt;
    // Track peak actual slew rates
    if (dvcomp_dt > peakSlewUp_actual) peakSlewUp_actual = dvcomp_dt;
    if (dvcomp_dt < -peakSlewDn_actual) peakSlewDn_actual = -dvcomp_dt;

    if (dvcomp_dt > slewUp) {
      slewLimited_src = true;
      lastSlewState = 1;
      const scale = slewUp * dt / Math.abs(vcomp_new - vcomp_old);
      newState[2] = state[2] + (newState[2] - state[2]) * scale;
      newState[3] = state[3] + (newState[3] - state[3]) * scale;
      newState[4] = state[4] + (newState[4] - state[4]) * scale;
    } else if (dvcomp_dt < -slewDn) {
      slewLimited_snk = true;
      lastSlewState = -1;
      const scale = slewDn * dt / Math.abs(vcomp_new - vcomp_old);
      newState[2] = state[2] + (newState[2] - state[2]) * scale;
      newState[3] = state[3] + (newState[3] - state[3]) * scale;
      newState[4] = state[4] + (newState[4] - state[4]) * scale;
    } else {
      lastSlewState = 0;
    }

    // Anti-windup: clamp integrator to keep vcomp in range
    const vcomp_final = newState[4] + newState[2] + newState[3];
    if (vcomp_final > (clampHigh || 5)) {
      clamped = true;
      newState[4] = (clampHigh || 5) - newState[2] - newState[3];
    } else if (vcomp_final < (clampLow || 0)) {
      clamped = true;
      newState[4] = (clampLow || 0) - newState[2] - newState[3];
    }

    // DCM: iL >= 0
    if (newState[0] < 0) { newState[0] = 0; dcm_entered = true; }

    state = newState;
  }

  // ─── Extract metrics ───────────────────────────────────
  let peakUndershoot = 0, peakOvershoot = 0, settlingTime = null;
  const stimIdx = data.findIndex(d => d.t_us >= (stim.tStart_us || 50));
  if (stimIdx >= 0) {
    for (let i = stimIdx; i < data.length; i++) {
      if (data[i].vout_mv < peakUndershoot) peakUndershoot = data[i].vout_mv;
      if (data[i].vout_mv > peakOvershoot) peakOvershoot = data[i].vout_mv;
    }
    const band = vout_nom * 0.02 * 1e3;
    for (let i = data.length - 1; i >= stimIdx; i--) {
      if (Math.abs(data[i].vout_mv) > band) { settlingTime = data[i].t_us - (stim.tStart_us || 50); break; }
    }
  }

  return { data, peakUndershoot, peakOvershoot, settlingTime, clamped, dcm_entered, stimType: stim.type,
    slewLimited_src, slewLimited_snk,
    peakSlewUp_Vms: peakSlewUp_actual / 1e3,  // V/ms for display
    peakSlewDn_Vms: peakSlewDn_actual / 1e3,
    slewLimit_src_Vms: slewUp < 1e14 ? slewUp / 1e3 : null,  // null = unlimited
    slewLimit_snk_Vms: slewDn < 1e14 ? slewDn / 1e3 : null,
  };
}

function autoPlace(pinfo, fc_target, fsw_hz, params) {
  // RHPZ clamping for flyback: fc must stay well below the RHPZ
  if (pinfo.fz_rhp && pinfo.fz_rhp > 0) {
    fc_target = Math.min(fc_target, pinfo.fz_rhp / 5);
  }
  const { fp1, fz_esr } = pinfo;
  const fz_c = fp1;
  const fp_c = Math.min(fz_esr, fsw_hz / 2);
  const Gp_fc = cmag(evalPlant(fc_target, params));
  // H(fc) includes opto pole rolloff: |H| = H_dc / sqrt(1 + (fc/fp_opto)²)
  const H_dc = evalFeedback(params.vref, params.vout) * (params.optoGain || 1);
  const H_fc = cmag(evalOptoH(fc_target, H_dc, params.fp_opto || 0));
  const cg = params.compGain || 1;
  const Gc_needed = 1 / (Gp_fc * cg * Math.max(H_fc, 1e-6));
  const num_mag = Math.sqrt(1 + (fc_target / fz_c) ** 2);
  const den_mag = Math.sqrt(1 + (fc_target / fp_c) ** 2);
  const fi = Gc_needed * fc_target / (num_mag / den_mag);
  return { type: "type2", fz_c, fp_c, fi };
}

function autoPlaceType3(pinfo, fc_target, fsw_hz, params) {
  // RHPZ clamping for flyback
  if (pinfo.fz_rhp && pinfo.fz_rhp > 0) {
    fc_target = Math.min(fc_target, pinfo.fz_rhp / 5);
  }
  const { fz_esr, f0_LC } = pinfo;
  // Two zeros straddle the LC resonance for maximum phase boost
  const k = 2.0; // spread factor
  const fz1 = f0_LC / k;
  const fz2 = f0_LC * k;
  // Two poles: one at ESR zero, one at fsw/2
  const fp1 = Math.min(fz_esr, fsw_hz / 2);
  const fp2 = fsw_hz / 2;
  // Compute needed gain at fc
  const Gp_fc = cmag(evalPlant(fc_target, params));
  const H_dc = evalFeedback(params.vref, params.vout) * (params.optoGain || 1);
  const H_fc = cmag(evalOptoH(fc_target, H_dc, params.fp_opto || 0));
  const cg = params.compGain || 1;
  const Gc_needed = 1 / (Gp_fc * cg * Math.max(H_fc, 1e-6));
  // |Gc(fc)| = (fi/fc) · |(1+jfc/fz1)(1+jfc/fz2)| / |(1+jfc/fp1)(1+jfc/fp2)|
  const nz1 = Math.sqrt(1 + (fc_target / fz1) ** 2);
  const nz2 = Math.sqrt(1 + (fc_target / fz2) ** 2);
  const dp1m = Math.sqrt(1 + (fc_target / fp1) ** 2);
  const dp2m = Math.sqrt(1 + (fc_target / fp2) ** 2);
  const fi = Gc_needed * fc_target / ((nz1 * nz2) / (dp1m * dp2m));
  return { type: "type3", fz1, fz2, fp1, fp2, fi };
}

function analyzeLoop(vin, vout, iout, fsw_hz, L, capBankDerated, ri, se, vref, comp, ea, td_ns, placement, senseParams, plantMode_arg, gmps_arg, sc_aus_arg, sc_aus_he_arg, optoGain_arg, fp_opto_arg, topoParams) {
  const eff = getCapBankEffective(capBankDerated);
  const pp = { vin, vout, iout, fsw_hz, L, cout: eff.Ceff, esr: eff.ESReff, ri, se, vref, capBank: capBankDerated, placement: placement || "high_side", senseParams, plantMode: plantMode_arg || "standard", gm_ps: gmps_arg || 20, sc_aus: sc_aus_arg || 0, sc_aus_he: sc_aus_he_arg != null ? sc_aus_he_arg : (sc_aus_arg || 0), optoGain: optoGain_arg || 1, fp_opto: fp_opto_arg || 0, ...(topoParams || {}) };
  const topo = topoParams?.topology || "buck";
  const isFlyback = topo === "flyback";
  // Flyback: D = Vout/(Vout+Vin_eff), Sn = Vin_pri/Lm × Ri
  // Buck/Forward: D = Vout/Vin_eff, Sn = (Vin-Vout)/L × Ri
  const D = isFlyback ? vout / Math.max(vout + vin, 0.01) : vout / Math.max(vin, 0.01);
  const Dprime = 1 - D;
  const n_tp = topoParams?.n || 1;
  const Lm_tp = topoParams?.Lm_H || L;
  const sn = isFlyback
    ? (vin / Math.max(n_tp, 1e-6)) / Math.max(Lm_tp, 1e-9) * ri  // Vin_pri/Lm × Ri
    : ((vin - vout) / Math.max(L, 1e-9)) * ri;                     // (Vin-Vout)/L × Ri
  const mc = 1 + (sn > 0 ? se / sn : 0);
  const factor = mc * Dprime - 0.5;
  const subharmStable = factor > 0;

  const H_dc = evalFeedback(vref, vout) * (optoGain_arg || 1);
  const freqs = logspace(1, 2e6, 500);
  let crossoverFreq = 0, phaseAtCrossover = null, gainAt180 = null;
  let prevG = null, prevPhUnwrap = null, foundCrossover = false;

  for (let i = 0; i < freqs.length; i++) {
    const f = freqs[i];
    const Gp = evalPlant(f, pp);
    const Gc = evalCompWithEA(f, comp, ea || {type:"ideal"});
    const Gd = evalDelay(f, td_ns || 0);
    const Hf = evalOptoH(f, H_dc, fp_opto_arg || 0);
    // Kcs(s) is inside plant closure (Ti = Fm·Gid·Kcs), not multiplied separately
    const cg = pp.compGain || 1;
    const T = cmul(cmul(cmul(Gc, cscale(Gp, cg)), Gd), Hf);
    const g = dB(cmag(T));
    let ph = cphase(T);

    // Unwrap phase continuously
    if (prevPhUnwrap !== null) {
      while (ph - prevPhUnwrap > 180) ph -= 360;
      while (ph - prevPhUnwrap < -180) ph += 360;
    }

    // First downward 0dB crossing only
    if (!foundCrossover && prevG !== null && prevG > 0 && g <= 0) {
      foundCrossover = true;
      const frac = prevG / (prevG - g);
      crossoverFreq = freqs[i - 1] * (freqs[i] / freqs[i - 1]) ** frac;
      // Interpolate phase at crossover from unwrapped values
      phaseAtCrossover = prevPhUnwrap + frac * (ph - prevPhUnwrap);
    }
    // Gain at -180° (using unwrapped phase)
    if (prevPhUnwrap !== null) {
      if (prevPhUnwrap > -180 && ph <= -180) gainAt180 = g;
    }
    prevG = g;
    prevPhUnwrap = ph;
  }
  const pm = phaseAtCrossover !== null ? 180 + phaseAtCrossover : null;
  const gm = gainAt180 !== null ? -gainAt180 : null;
  return { fc: crossoverFreq, pm, gm, subharmStable, factor };
}

function stepResponse(fc, pm, tmax, npts) {
  const wn = TWO_PI * fc; const pmR = (pm * Math.PI) / 180;
  const z = Math.min(pmR / (Math.PI / 2) * 0.8, 0.99);
  const wd = wn * Math.sqrt(Math.max(1 - z * z, 0.001));
  // settling time (2% band) ≈ 4/(z·wn), use 2× for visible recovery
  const tSettle = 4 / (z * wn) * 2;
  const tTotal = Math.max(tSettle, tmax);
  const tPre = tTotal * 0.10;
  const tPost = tTotal * 0.12; // flat tail after settling
  const tFull = tPre + tTotal + tPost;
  const d = [];
  const N = npts;
  for (let i = 0; i <= N; i++) {
    const tRaw = tFull * i / N;
    const t_us = parseFloat((tRaw * 1e6).toFixed(2));
    let y;
    if (tRaw < tPre) {
      y = 0;
    } else {
      const t = tRaw - tPre;
      if (z >= 1) {
        const s1 = -wn * (z - Math.sqrt(z * z - 1)), s2 = -wn * (z + Math.sqrt(z * z - 1));
        y = 1 - (s1 * Math.exp(s2 * t) - s2 * Math.exp(s1 * t)) / (s1 - s2);
      } else {
        y = 1 - (1 / Math.sqrt(1 - z * z)) * Math.exp(-z * wn * t) * Math.sin(wd * t + Math.acos(z));
      }
    }
    d.push({ t_us, y });
  }
  return d;
}

function loadStepResponse(fc, pm, cout, esr, deltaI, tmax, npts) {
  const wn = TWO_PI * fc; const pmR = (pm * Math.PI) / 180;
  const z = Math.min(pmR / (Math.PI / 2) * 0.8, 0.99);
  const wd = wn * Math.sqrt(Math.max(1 - z * z, 0.001));
  // Two time constants in this model:
  //   Oscillatory: τ1 = 1/(z·wn)        — the main ring-down
  //   ESR decay:   τ2 = 1/(0.3·z·wn)    — ~3.3× slower envelope
  // Need ~4× the slower one to see full recovery to <2%
  const tau_slow = 1 / (0.3 * z * wn);
  const tSettle = tau_slow * 5; // 5τ of the slow term → <1% remaining
  const tTotal = Math.max(tSettle, tmax);
  const tPre = tTotal * 0.10;   // 10% flat before step
  const tPost = tTotal * 0.12;  // 12% flat after settle to show recovery
  const tFull = tPre + tTotal + tPost;
  const d = [];
  const N = npts;
  for (let i = 0; i <= N; i++) {
    const tRaw = tFull * i / N;
    const t_us = parseFloat((tRaw * 1e6).toFixed(2));
    let dv;
    if (tRaw < tPre) {
      dv = 0;
    } else {
      const t = tRaw - tPre;
      dv = -deltaI * esr * Math.exp(-z * wn * t * 0.3)
        - (deltaI / (cout * wn)) * (1 / Math.sqrt(1 - z * z + 0.001))
          * Math.exp(-z * wn * t) * Math.sin(wd * t);
    }
    d.push({ t_us, dv_mv: parseFloat((dv * 1000).toFixed(2)) });
  }
  return d;
}

function validate(fc, pm, gm, pinfo, fsw_hz, ea, eaPhaseLoss, compUnityGain, csDelay_ns, sInfo, tLEB_ns) {
  const errs = [], warns = [], info = [];
  if (!pinfo) return { errors: ["Plant info unavailable"], warnings: [], info: [] };
  const { D, Dprime, mc, Qp, fp1, fz_esr, fz_esr_scalar, fz_esr_method, factor, sn, mode, Ti0, Io_crit, f0_LC, fp_dcm, ctrlMode, placement, topology: piTopo } = pinfo;
  const isFlybackPlant = piTopo === "flyback";
  const placementLabel = { high_side: "High-side", inductor: "Inductor" }[placement || "high_side"] || placement;

  if (ctrlMode === "gmps") {
    // Integrated converter — gm_ps plant model (§9.3.10.2)
    const gm_ps = pinfo.gm_ps || 0;
    const gm_ps_table = pinfo.gm_ps_table || gm_ps;
    const sc = pinfo.sc_aus || 0;
    const Sn = pinfo.Sn_Aus || 0;
    const rload = pinfo.rload || 1;
    info.push(`Integrated converter: gm_ps(eff) = ${sf(gm_ps,2)} S, Gvc(0) = ${sf(gm_ps*rload,2)} V/V (${sf(dB(gm_ps*rload),1)} dB)`);
    if (sc > 0 && gm_ps_table !== gm_ps) {
      info.push(`SC correction: gm_ps(table) = ${sf(gm_ps_table,1)} S × Sn/(Sn+SC) = ${sf(gm_ps_table,1)} × ${sf(Sn,2)}/(${sf(Sn,2)}+${sf(sc,2)}) = ${sf(gm_ps,2)} S`);
      info.push(`Sn = (Vin−Vout)/L = ${sf(Sn,2)} A/µs, SC = ${sf(sc,2)} A/µs, mc = ${sf(pinfo.mc,2)}`);
      if (sc > Sn * 2) warns.push(`SC (${sf(sc,1)} A/µs) > 2× Sn (${sf(Sn,1)} A/µs). Excessive slope comp reduces gm_ps by ${sf((1 - gm_ps/gm_ps_table)*100,0)}% — may degrade transient response.`);
    }
    info.push(`D = ${sf(D*100,1)}%, fp1 = ${fmtFreq(fp1)}, fz(ESR) = ${fmtFreq(fz_esr)}`);
    info.push(`He(s) sampling: fn = ${fmtFreq(pinfo.fn_he)}, Qp = ${sf(Qp,2)}, factor(mc·D'−0.5) = ${sf(factor,3)}`);
    if (factor <= 0) errs.push(`CRITICAL: Subharmonic instability! mc·D'−0.5 = ${sf(factor,3)} ≤ 0. Increase slope compensation (RSC).`);
    else if (factor < 0.15) warns.push(`Marginal slope comp: mc·D'−0.5 = ${sf(factor,3)}. Qp = ${sf(Qp,1)} — expect peaking near fsw/2.`);
    if (D > 0.5 && mc <= 1.01) errs.push(`D = ${sf(D*100,1)}% > 50% with no slope comp!`);
    info.push(`Plant model: T(s) = gmEA × Zcomp(s) × gm_ps × Zout(s) × He(s) × H (§9.3.10).`);
  } else if (mode === "CCM") {
    info.push(`Operating mode: ${mode}. Peak CM (${placementLabel} sense). Io_crit = ${fmtSI(Io_crit, "A")}`);
    if (factor <= 0) errs.push(`CRITICAL: Subharmonic instability! mc·D'−0.5 = ${sf(factor,3)} ≤ 0. Increase slope compensation.`);
    else if (factor < 0.15) warns.push(`Marginal slope comp: mc·D'−0.5 = ${sf(factor,3)}. Qp = ${sf(Qp,1)} — expect peaking near fsw/2.`);
    // Ti(0) check: only meaningful for buck/forward (decomposed Gvi/(1+Ti) model)
    // For flyback, the Basso/Richtek closed-form plant doesn't use Ti decomposition
    if (!isFlybackPlant) {
      if (Ti0 < 1) errs.push(`Ti(0) = ${sf(Ti0,2)} < 1. Plant is voltage-mode — LC double-pole present. Type-II CANNOT stabilize this. Use Type-III or reduce slope comp.`);
      else if (Ti0 < 3) warns.push(`Ti(0) = ${sf(Ti0,2)} < 3. Emerging VM characteristics. Type-III recommended, or reduce slope comp.`);
      else info.push(`Ti(0) = ${sf(Ti0,1)} — inner current loop has good gain.`);
    }
    if (D > 0.5 && mc <= 1.01) errs.push(`D = ${sf(D*100,1)}% > 50% with no slope comp!`);
    info.push(`D = ${sf(D*100,1)}%, mc = ${sf(mc,2)}, Sn = ${sf((sn||0)/1e3,1)} mV/µs`);
    const esrNote = fz_esr_method === "curve"
      ? `fz(ESR) = ${fmtFreq(fz_esr)} (from |Zbank| curve; scalar approx = ${fmtFreq(fz_esr_scalar)})`
      : `fz(ESR) = ${fmtFreq(fz_esr)}`;
    info.push(`fp1 = ${fmtFreq(fp1)}, f0(LC) = ${fmtFreq(f0_LC)}, ${esrNote}`);
    info.push(`He Qp = ${sf(Qp,2)}, fsw/π = ${fmtFreq(fsw_hz / Math.PI)}`);
  } else {
    info.push(`DCM: single-pole plant at fp = ${fmtFreq(fp_dcm || 0)}. No subharmonic instability in DCM.`);
    info.push(`D = ${sf(D*100,1)}%, fz(ESR) = ${fmtFreq(fz_esr)}`);
    warns.push(`Operating in DCM. Compensation designed for CCM may give unexpected margins.`);
  }
  const ratio = fc / fsw_hz;
  if (ratio > 0.201) errs.push(`fc/fsw = ${sf(ratio*100,1)}% exceeds 20%. Averaged model unreliable.`);
  else if (ratio > 0.101) warns.push(`fc/fsw = ${sf(ratio*100,1)}%. Above typical 10% guideline.`);
  else info.push(`fc/fsw = ${sf(ratio*100,1)}% — within ≤10% guideline.`);
  if (pm !== null) {
    if (pm < 30) errs.push(`Phase margin ${sf(pm,1)}° < 30°. Unstable or heavily ringing.`);
    else if (pm < 45) warns.push(`Phase margin ${sf(pm,1)}° < 45°. Target ≥ 45°.`);
    else info.push(`Phase margin ${sf(pm,1)}° — good.`);
  }
  if (gm !== null) {
    if (gm < 6) errs.push(`Gain margin ${sf(gm,1)} dB < 6 dB.`);
    else if (gm < 10) warns.push(`Gain margin ${sf(gm,1)} dB < 10 dB.`);
    else info.push(`Gain margin ${sf(gm,1)} dB — adequate.`);
  } else {
    info.push(`Gain margin = ∞ (phase never reaches −180°).`);
  }
  // ─── EA validation ──────────────────────────────────────
  if (ea && ea.type !== "ideal") {
    const eaI = getEAInfo(ea);
    info.push(`EA: ${ea.type==="ota"?"OTA gm":"Op-amp"}, Aol=${sf(eaI.Aol_dB,1)} dB, GBW=${fmtFreq(eaI.GBW_Hz)}, fp1(EA)=${fmtFreq(eaI.fp1_ea)}`);
    if (eaPhaseLoss > 15) errs.push(`EA+delay erodes PM by ${sf(eaPhaseLoss,1)}° — severe. Reduce crossover or use higher-GBW EA.`);
    else if (eaPhaseLoss > 8) warns.push(`EA+delay erodes PM by ${sf(eaPhaseLoss,1)}°. Your effective PM is reduced by this amount.`);
    else if (eaPhaseLoss > 2) info.push(`EA+delay erodes PM by ${sf(eaPhaseLoss,1)}° — acceptable.`);
    if (compUnityGain && eaI.GBW_Hz < compUnityGain)
      errs.push(`EA GBW (${fmtFreq(eaI.GBW_Hz)}) < comp unity-gain (${fmtFreq(compUnityGain)}). EA cannot support this compensation.`);
    else if (compUnityGain && eaI.GBW_Hz < compUnityGain * 3)
      warns.push(`EA GBW only ${sf(eaI.GBW_Hz/compUnityGain,1)}× comp unity-gain. Phase accuracy degraded.`);
  }
  if (csDelay_ns > 0 && fc > 0) {
    const delayPh = 360 * fc * csDelay_ns * 1e-9;
    if (delayPh > 10) warns.push(`CS delay (${csDelay_ns} ns) adds ${sf(delayPh,1)}° phase loss at fc.`);
    else if (delayPh > 3) info.push(`CS delay (${csDelay_ns} ns) adds ${sf(delayPh,1)}° phase loss at fc.`);
  }
  // Sense chain diagnostics
  if (sInfo && sInfo.isCT) {
    // CT-specific diagnostics
    info.push(`CT sense: ${sf(sInfo.turnsRatio,0)}:1, Ri_eff = ${sf(sInfo.ri_ct,3)} V/A, HP corner fp_CT = ${fmtFreq(sInfo.fp_ct)}`);
    if (sInfo.droopPct > 10) errs.push(`CT droop ${sf(sInfo.droopPct,1)}% exceeds 10%. Increases effective slope comp and distorts peak detection. Increase Lm or reduce Rb.`);
    else if (sInfo.droopPct > 5) warns.push(`CT droop ${sf(sInfo.droopPct,1)}%. May affect slope comp accuracy. Consider higher Lm.`);
    else info.push(`CT droop: ${sf(sInfo.droopPct,1)}% — acceptable.`);
    if (sInfo.resetMargin < 1 && tLEB_ns >= 0) {
      if (sInfo.placement === "inductor") errs.push(`CT on inductor: continuous current prevents self-reset in CCM. Use forced-reset circuit or switch to shunt.`);
      else errs.push(`CT self-reset impossible: Toff/Ton = ${sf(sInfo.resetMargin,2)} < 1. D = ${sf(pinfo.D*100,1)}% too high for self-reset. Use forced-reset or reduce D.`);
    } else if (sInfo.resetMargin < 1.5) warns.push(`CT reset margin ${sf(sInfo.resetMargin,2)}× — marginal. Core may not fully reset at temperature extremes.`);
    if (sInfo.fres_hf) info.push(`CT HF resonance (Llk×Cw): ${fmtFreq(sInfo.fres_hf)}`);
    if (sInfo.pDiss !== null) {
      info.push(`Burden dissipation: ${sf(sInfo.pDiss*1000,0)} mW`);
      if (sInfo.pDiss > 0.5) warns.push(`Burden power ${sf(sInfo.pDiss,2)} W exceeds 500 mW.`);
    }
    if (sInfo.placement === "high_side") info.push(`High-side CT: galvanic isolation from power path. LEB still recommended for leakage spike.`);
  } else if (sInfo && sInfo.fz_par !== null) {
    info.push(`Sense chain: parasitic zero fz_par = ${fmtFreq(sInfo.fz_par)}, amp BW = ${sInfo.fp_amp ? fmtFreq(sInfo.fp_amp) : "∞"}${sInfo.fp_filt ? ", filter pole = " + fmtFreq(sInfo.fp_filt) : ""}`);
    if (sInfo.fz_par < fsw_hz * 10) warns.push(`Parasitic zero (${fmtFreq(sInfo.fz_par)}) < 10×fsw. May cause noise on CS pin. Consider RC filter or lower-inductance shunt.`);
    if (sInfo.fp_amp && fc > 0 && sInfo.fp_amp < fc * 5) warns.push(`Amp bandwidth (${fmtFreq(sInfo.fp_amp)}) < 5× crossover (${fmtFreq(fc)}). Sense chain rolloff degrades loop accuracy.`);
    if (sInfo.pDiss !== null) {
      info.push(`Shunt dissipation: ${sf(sInfo.pDiss*1000,0)} mW (${sInfo.placement.replace("_"," ")} placement)`);
      if (sInfo.pDiss > 0.5) warns.push(`Shunt power ${sf(sInfo.pDiss,2)} W exceeds 500 mW. Consider lower Rshunt or CT sensing.`);
    }
    // Placement-specific notes
    if (sInfo.placement === "high_side") {
      info.push(`High-side sense: LEB required to blank leading-edge switch noise. Common-mode voltage = Vin.`);
    } else if (sInfo.placement === "inductor") {
      info.push(`Inductor sense: continuous current — highest shunt dissipation. No LEB needed. CT cannot self-reset in CCM.`);
    }
  }
  // LEB / min on-time check
  if (tLEB_ns > 0 && fc > 0) {
    const D = pinfo.D;
    const tOn_ns = D / Math.max(fsw_hz, 1) * 1e9;
    if (tOn_ns < tLEB_ns) errs.push(`Min on-time (${sf(tOn_ns,0)} ns) < LEB (${tLEB_ns} ns). Controller will miss current ramp entirely at this operating point.`);
    else if (tOn_ns < tLEB_ns * 1.5) warns.push(`On-time (${sf(tOn_ns,0)} ns) only ${sf(tOn_ns/tLEB_ns,1)}× LEB (${tLEB_ns} ns). Marginal current sense window.`);
  }
  return { errors: errs, warnings: warns, info };
}

// IC-specific validation (called separately in the component with IC context)
function validateIC(ic, fsw_hz, pinfo) {
  const warns = [], errs = [];
  if (!ic || ic.id === "custom") return { errors: errs, warnings: warns };
  if (!pinfo) return { errors: errs, warnings: warns };
  if (ic.fsw_max_kHz && fsw_hz > ic.fsw_max_kHz * 1e3)
    errs.push(`fsw (${sf(fsw_hz/1e3,0)} kHz) exceeds ${ic.name} max (${ic.fsw_max_kHz} kHz).`);
  if (ic.Dmax && pinfo.D > ic.Dmax)
    errs.push(`D = ${sf(pinfo.D*100,1)}% exceeds ${ic.name} Dmax (${sf(ic.Dmax*100,0)}%).`);
  if (ic.Dmax && pinfo.D > ic.Dmax * 0.95 && pinfo.D <= ic.Dmax)
    warns.push(`D = ${sf(pinfo.D*100,1)}% is within 5% of ${ic.name} Dmax (${sf(ic.Dmax*100,0)}%). Marginal.`);
  return { errors: errs, warnings: warns };
}

const fmtFreq = (f) => { if (f == null || !isFinite(f)) return "—"; return f >= 1e6 ? (f/1e6).toFixed(2)+" MHz" : f >= 1e3 ? (f/1e3).toFixed(2)+" kHz" : f.toFixed(1)+" Hz"; };
const fmtSI = (v, u) => {
  if (v == null || !isFinite(v)) return "— "+u;
  const a = Math.abs(v);
  if (a >= 1e6) return (v/1e6).toFixed(2)+" M"+u;
  if (a >= 1e3) return (v/1e3).toFixed(2)+" k"+u;
  if (a >= 1) return v.toFixed(3)+" "+u;
  if (a >= 1e-3) return (v*1e3).toFixed(2)+" m"+u;
  if (a >= 1e-6) return (v*1e6).toFixed(2)+" µ"+u;
  if (a >= 1e-9) return (v*1e9).toFixed(2)+" n"+u;
  return (v*1e12).toFixed(2)+" p"+u;
};
const logTicks = [10, 100, 1e3, 1e4, 1e5, 1e6];
const logTickFmt = (v) => v >= 1e6 ? (v/1e6)+"M" : v >= 1e3 ? (v/1e3)+"k" : v+"";

// ─── String-based numeric input ─────────────────────────────
function NumInput({ label, unit, val, onVal }) {
  const [text, setText] = useState(String(val));
  const skipSync = useRef(false);

  useEffect(() => {
    if (skipSync.current) { skipSync.current = false; return; }
    setText(String(val));
  }, [val]);

  const handleChange = (e) => {
    const raw = e.target.value;
    // Allow empty, minus, dots, and numbers freely while typing
    if (raw === "" || raw === "-" || raw === "." || raw === "-.") {
      setText(raw);
      return;
    }
    // Allow trailing dot or minus for continued typing
    if (/^-?\d*\.?\d*$/.test(raw)) {
      setText(raw);
      const n = parseFloat(raw);
      if (!isNaN(n)) {
        skipSync.current = true;
        onVal(n);
      }
    }
  };

  const handleBlur = () => {
    const n = parseFloat(text);
    if (isNaN(n) || text.trim() === "") {
      setText(String(val));
    } else {
      const clean = String(n);
      setText(clean);
      skipSync.current = true;
      onVal(n);
    }
  };

  return (
    <div style={{ marginBottom: 6 }}>
      <label style={sLabel}><span style={{textTransform:"uppercase"}}>{label}</span>{unit ? ` [${unit}]` : ""}</label>
      <input type="text" inputMode="decimal" value={text}
        onChange={handleChange} onBlur={handleBlur} style={sInput} />
    </div>
  );
}

// ─── Phase 8: SPICE Netlist Generator ────────────────────────
// Generates LTspice/Qspice/NGspice compatible .cir file
// Two analysis modes: .ac (Bode) and .tran (load step)
function generateSpiceNetlist(cfg) {
  const {
    vin, vinMin, vinMax, vout, iout, fsw_hz, L, vref,
    ri, se, capBank, esr_eff, cout_eff,
    comp, compComponents, eaParams,
    plantMode, gm_ps, sc_aus, sc_aus_he,
    csDelay_ns, compClampLow, compClampHigh,
    fc, pm, gm_margin,
    ic, deltaI, stimRiseTime, rise1090, stimType, stimDeltaVin,
    simMode, // "ac" or "tran"
    date,
  } = cfg;

  const fsw_kHz = fsw_hz / 1e3;
  const isFlyback = cfg.topology === "flyback";
  const n_sp = cfg.n || 1;
  const Lm_sp = (cfg.xfmrLm || 0) * 1e-6;
  const D = isFlyback ? vout / Math.max(vout + vin, 0.01) : vout / Math.max(vin, 0.01);
  const Dprime = 1 - D;
  const rload = vout / Math.max(iout, 0.001);
  const H = vref / vout * (cfg.optoGain || 1);
  const Sn = isFlyback
    ? (vin / Math.max(n_sp, 1e-6)) / Math.max(Lm_sp, 1e-12) * ri  // Vin_pri/Lm × Ri
    : (vin - vout) / Math.max(L, 1e-12) * ri;
  const mc = 1 + (Sn > 0 ? se / Sn : 0);
  const Fm = fsw_hz / Math.max(Sn * mc, 1e-12);
  const cc = compComponents || {};
  const cg_sp = cfg.compGain || 1; // IC signal conditioning gain

  // SI formatter for netlist values
  const spv = (v) => {
    const a = Math.abs(v);
    if (a >= 1e6) return (v/1e6).toPrecision(5) + "Meg";
    if (a >= 1e3) return (v/1e3).toPrecision(5) + "k";
    if (a >= 1) return v.toPrecision(5);
    if (a >= 1e-3) return (v*1e3).toPrecision(5) + "m";
    if (a >= 1e-6) return (v*1e6).toPrecision(5) + "u";
    if (a >= 1e-9) return (v*1e9).toPrecision(5) + "n";
    return (v*1e12).toPrecision(5) + "p";
  };

  let lines = [];
  const p = (s) => lines.push(s);

  // ------ Header ----------------------------------------------------------------------------------------
  const topoLabel = cfg.topology === "2sw_fwd" ? "Two-Switch Forward" : isFlyback ? "Flyback" : "Buck";
  p(`* ===================================================================`);
  p(`* ${topoLabel} Peak CM Control Loop -- SPICE Netlist`);
  p(`* Generated by Power Electronics Control Loop Analyzer -- ${date || new Date().toISOString().slice(0,10)}`);
  p(`* Compatible with LTspice / Qspice / NGspice`);
  p(`* ===================================================================`);
  p(`*`);
  if (cfg.topology === "2sw_fwd" || isFlyback) {
    p(`* Transformer:`);
    p(`*   Np=${cfg.xfmrNp||"?"}  Ns=${cfg.xfmrNs||"?"}  n=Ns/Np=${cfg.n?.toFixed(4)||"?"}  Lm=${cfg.xfmrLm||"?"}uH`);
    p(`*   Vin_primary=${vinMin?((vinMin/(cfg.n||1)).toFixed(1)):""}..${ vinMax?((vinMax/(cfg.n||1)).toFixed(1)):""}V`);
    p(`*   Vin_eff(secondary)=${vin.toFixed(2)}V`);
    if (isFlyback) {
      p(`*   Flyback: Lm is energy storage. Lm_sec = Lm × n² = ${((cfg.xfmrLm||0)*(cfg.n||1)*(cfg.n||1)).toFixed(3)}uH`);
      p(`*   RHPZ = R·D'²/(D·Lm_sec·2π)`);
    }
    p(`*`);
  }
  p(`* Operating Point:`);
  p(`*   Vin=${vin}V (${vinMin||""}..${vinMax||""}V)  Vout=${vout}V  Iout=${iout}A`);
  p(`*   fsw=${fsw_kHz}kHz  L=${spv(L)}H  D=${(D*100).toFixed(1)}%`);
  p(`*   Cout_eff=${spv(cout_eff)}F  ESR_eff=${spv(esr_eff)}R`);
  p(`*   Ri=${spv(ri)}R  Vref=${vref}V`);
  if (ic && ic.id !== "custom") p(`*   IC: ${ic.name} (${ic.mfg})`);
  p(`*`);
  p(`* Tool Results: fc=${fc?Math.round(fc)+"Hz":"--"}  PM=${pm?pm.toFixed(1):"--"}deg  GM=${gm_margin?gm_margin.toFixed(1)+"dB":"inf"}`);
  p(`*`);
  p(`* ===================================================================`);
  p(``);

  // Compute vcomp_ss for initial conditions
  let vcomp_ic;
  if (plantMode === "gmps") {
    vcomp_ic = (compClampLow || 0) + iout / Math.max(gm_ps, 0.01);
  } else {
    const iL_ss = isFlyback ? iout / Math.max(Dprime, 0.01) : iout;
    const Sn_total_loc = Sn + se;
    vcomp_ic = ri * iL_ss + Sn_total_loc * D / fsw_hz;
  }
  vcomp_ic = Math.max(compClampLow || 0, Math.min(compClampHigh || 5, vcomp_ic));
  const vfb_ic = vref; // At SS the FB node = Vref

  const isTran = simMode === "tran";
  // ------ Simulation Commands --------------------------------------------------------------
  p(`* --- ANALYSIS: ${isTran ? "TRANSIENT" : "AC (Bode)"} ---`);
  if (isTran) {
    p(`.tran ${spv(10/Math.max(fc||30e3,100))}s uic`);
    p(`.options reltol=0.001 gmin=1e-12 cshunt=1e-15`);
  } else {
    p(`.ac dec 200 1 2e6`);
  }
  p(``);

  // ------ Input Voltage --------------------------------------------------------------------------
  p(`* ------ INPUT ------`);
  p(`Vin vin gnd DC ${vin}`);
  p(`Rvin_dummy vin gnd 1e9`);
  p(``);

  // ------ Output Load ------------------------------------------------------------------------------
  p(`* ------ OUTPUT LOAD ------`);
  p(`Rload vout gnd ${spv(rload)}`);
  const riseTime_s = ((stimRiseTime || 1) * (rise1090 ? 1/0.8 : 1)) * 1e-6;
  const riseNote = rise1090 ? ` (${stimRiseTime}us 10-90%)` : "";
  const stepDelay = spv(2 / Math.max(fc || 30e3, 100));
  if (isTran) {
    if (stimType === "line_step") {
      p(`* Line step${riseNote}:`);
      if (rise1090) p(`* 10-90% of ${stimDeltaVin||3}V in ${stimRiseTime}us (0-100% ramp = ${(riseTime_s*1e6).toFixed(1)}us)`);
      p(`Vstep vin gnd PULSE(${vin} ${vin + (stimDeltaVin||3)} ${stepDelay} ${spv(riseTime_s)} ${spv(riseTime_s)} 1 2)`);
    } else {
      p(`* Load step${riseNote}:`);
      if (rise1090) p(`* 10-90% of ${deltaI||2}A in ${stimRiseTime}us (0-100% ramp = ${(riseTime_s*1e6).toFixed(1)}us)`);
      p(`Istep vout gnd PULSE(0 ${deltaI||2} ${stepDelay} ${spv(riseTime_s)} ${spv(riseTime_s)} 1 2)`);
    }
  } else {
    p(`* Load step (for .tran mode):`);
    p(`* Istep vout gnd PULSE(0 ${deltaI||2} ${stepDelay} ${spv(riseTime_s)} ${spv(riseTime_s)} 1 2)`);
  }
  p(``);

  // ------ Output Capacitor Bank ----------------------------------------------------------
  p(`* ------ OUTPUT CAPACITOR BANK ------`);
  if (capBank && capBank.length > 0) {
    capBank.forEach((b, i) => {
      if (b.qty <= 0 || b.cap_F <= 0) return;
      const totalC = b.cap_F * b.qty;
      const totalESR = b.esr_ohm / b.qty;
      const totalESL = b.esl_H / b.qty;
      p(`* Cap group ${i+1}: ${b.qty}x ${spv(b.cap_F)}F, ESR=${spv(b.esr_ohm)}R${b.esl_H>0?", ESL="+spv(b.esl_H)+"H":""}`);
      const node_esr = `vout_esr${i}`;
      const node_esl = totalESL > 0 ? `vout_esl${i}` : "gnd";
      p(`Cout${i} vout ${node_esr} ${spv(totalC)}`);
      if (totalESL > 0) {
        p(`Resr${i} ${node_esr} ${node_esl} ${spv(totalESR)}`);
        p(`Lesl${i} ${node_esl} gnd ${spv(totalESL)}`);
      } else {
        p(`Resr${i} ${node_esr} gnd ${spv(totalESR)}`);
      }
    });
  } else {
    p(`Cout0 vout vout_esr0 ${spv(cout_eff)}`);
    p(`Resr0 vout_esr0 gnd ${spv(esr_eff)}`);
  }
  p(``);

  if (plantMode === "gmps") {
    // ------ gm_ps Plant Model + He(s) --------------------------------------------------------
    p(`* ------ PLANT: gm_ps AVERAGED MODEL + He(s) SAMPLING ------`);
    p(`* gm_ps = ${gm_ps} S (power stage transconductance)`);
    p(`* Signal path: EA -> comp -> He(s) -> comp_he -> Bps -> vout`);
    p(``);

    // He(s) parameters
    const D_val = vout / Math.max(vin, 0.01);
    const Dprime = 1 - D_val;
    const Sn_Aus = (vin - vout) / Math.max(L, 1e-12) / 1e6;
    const sc_he_Aus = sc_aus_he || 0;
    const mc_he = 1 + (Sn_Aus > 0 ? sc_he_Aus / Sn_Aus : 0);
    const factor_he = mc_he * Dprime - 0.5;
    const fn_he = fsw_hz / Math.PI;
    const wn_he = TWO_PI * fn_he;
    const Qp_he = factor_he > 0.01 ? 1 / (Math.PI * factor_he) : 50;
    p(`* He(s) = 1/(1 + s/(Qp*wn) + s^2/wn^2)`);
    p(`* fn = fsw/pi = ${Math.round(fn_he)}Hz  Qp = ${Qp_he.toPrecision(4)}  mc = ${mc_he.toPrecision(4)}`);
    const qw_s = (Qp_he * wn_he).toPrecision(6);
    p(`Ehe comp_he gnd LAPLACE {V(comp)} = {1/(1 + s/${qw_s} + s*s/${(wn_he*wn_he).toPrecision(6)})}`);
    p(``);

    // Plant current source
    if (isTran) {
      p(`Bps gnd vout I=${gm_ps}*max(V(comp_he)-${compClampLow||0}, 0)`);
    } else {
      p(`Bps gnd vout I=${gm_ps}*(V(comp_he)-${compClampLow||0})`);
    }
    p(``);

    // OTA Compensator
    p(`* ------ COMPENSATOR: OTA Type-II ------`);
    p(`* RCOMP=${cc.RCOMP?spv(cc.RCOMP)+"R":"?"}  CCOMP=${cc.CCOMP?spv(cc.CCOMP)+"F":"?"}  CHF=${cc.CHF?spv(cc.CHF)+"F":"?"}`);
    p(``);
    const fz = comp.fz_c || 1000;
    const fp = comp.fp_c || 50000;
    const fi = comp.fi || 1000;
    const wz_val = (TWO_PI * fz).toPrecision(6);
    const wp_val = (TWO_PI * fp).toPrecision(6);
    const wi_val = (TWO_PI * fi).toPrecision(6);
    const eps = (TWO_PI * 0.01).toPrecision(4);

    if (isTran) {
      p(`* Behavioral Laplace compensator (numerically stable for .tran)`);
      p(`Ecomp_gc comp_raw gnd LAPLACE {V(vref_node)-V(vfb_inj)} = {${wi_val}*(1+s/${wz_val}) / ((s+${eps})*(1+s/${wp_val}))}`);
      p(`Bcomp comp gnd V=limit(V(comp_raw)+${vcomp_ic.toPrecision(4)}, ${compClampLow||0.4}, ${compClampHigh||2.0})`);
      p(`Ric comp gnd 1e9`);
    } else {
      p(`* Physical OTA + comp network (linearizes for .ac)`);
      p(`Gea comp gnd vref_node vfb_inj ${spv((eaParams.gm_uAV||1650)*1e-6)}`);
      p(`Rout_ea comp gnd ${spv((eaParams.Rout_MOhm||7)*1e6)}`);
      if (cc.RCOMP) {
        p(`Rcomp comp comp_rc ${spv(cc.RCOMP)}`);
        p(`Ccomp comp_rc gnd ${spv(cc.CCOMP)}`);
        p(`Chf comp gnd ${spv(cc.CHF)}`);
      }
      p(`* COMP voltage clamps`);
      p(`Dclamp_hi comp comp_clhi DCLAMP`);
      p(`Dclamp_lo comp_cllo comp DCLAMP`);
      p(`Vclamp_hi comp_clhi gnd ${compClampHigh||2.0}`);
      p(`Vclamp_lo comp_cllo gnd ${compClampLow||0.4}`);
      p(`.model DCLAMP D(N=0.1)`);
    }
    p(``);

  } else if (isFlyback) {
    // ------ Flyback Averaged Plant (Basso/Richtek) ------
    p(`* ------ PLANT: FLYBACK AVERAGED CM MODEL (Basso/Richtek) ------`);
    const Lm_sec = Lm_sp * n_sp * n_sp;
    const fp1_fly = 1 / (TWO_PI * rload * Dprime * cout_eff);
    const fz_esr_fly = 1 / (TWO_PI * esr_eff * cout_eff);
    const fz_rhp = rload * Dprime * Dprime / (TWO_PI * D * Math.max(Lm_sec, 1e-12));
    const fn_he = fsw_hz / Math.PI;
    const wn_he = TWO_PI * fn_he;
    const factor_he = mc * Dprime - 0.5;
    const Qp_he = factor_he > 0.01 ? 1 / (Math.PI * factor_he) : 50;
    const Gvc0 = rload / ri * cg_sp;
    p(`* D=${(D*100).toFixed(1)}%  D'=${(Dprime*100).toFixed(1)}%  Rload=${rload.toFixed(3)}R`);
    p(`* Lm_sec=${spv(Lm_sec)}H  mc=${mc.toPrecision(4)}  Qp_He=${Qp_he.toPrecision(4)}`);
    p(`* Gvc(0) = Rload/Ri${cg_sp<1?" x cg("+cg_sp.toPrecision(3)+")":""} = ${Gvc0.toPrecision(4)} (${(20*Math.log10(Gvc0)).toFixed(1)}dB)`);
    p(`* fp1=${fp1_fly.toFixed(1)}Hz  fz_esr=${fz_esr_fly.toFixed(0)}Hz  RHPZ=${fz_rhp.toFixed(0)}Hz`);
    p(`* fn_He=${fn_he.toFixed(0)}Hz  Qp_He=${Qp_he.toPrecision(4)}`);
    p(`*`);
    const wp1_f = (TWO_PI * fp1_fly).toPrecision(6);
    const wz_esr_f = (TWO_PI * fz_esr_fly).toPrecision(6);
    const wz_rhp_f = (TWO_PI * fz_rhp).toPrecision(6);
    const qw_f = (Qp_he * wn_he).toPrecision(6);
    const wn2_f = (wn_he * wn_he).toPrecision(6);

    if (isTran) {
      // Averaged nonlinear flyback for .tran
      const Fm_sp = Fm.toPrecision(6);
      p(`* Averaged nonlinear flyback for .tran`);
      p(`* D = Fm × (Vcomp×cg - Ri×iL), Fm=${Fm_sp}`);
      p(`Bd_fly d_node gnd V=limit(${Fm_sp}*(V(comp)*${cg_sp.toPrecision(4)}-${spv(ri)}*I(Lfly)), 0, ${cfg.Dmax || 0.65})`);
      p(`Bsw_fly sw_fly gnd V=V(vin)*V(d_node)-V(vout)*(1-V(d_node))`);
      p(`Lfly sw_fly vout_il ${spv(Lm_sec)}`);
      p(`Rfly_dcr vout_il gnd 1m`);
      p(`Bout_fly gnd vout I=I(Lfly)*(1-V(d_node))`);
      p(`Rd_dummy d_node gnd 1e9`);
    } else {
      // Behavioral Laplace plant for .ac
      p(`* Gvc(s) = Gvc0×(1+s/wz_esr)×(1-s/wz_rhp)/[(1+s/wp1)×He(s)]`);
      p(`Efly fly_out gnd LAPLACE {V(comp)*${cg_sp.toPrecision(4)}} = {${Gvc0.toPrecision(6)}*(1+s/${wz_esr_f})*(1-s/${wz_rhp_f})/((1+s/${wp1_f})*(1+s/${qw_f}+s*s/${wn2_f}))}`);
      p(`Bfly_i gnd vout I=V(fly_out)/${spv(rload)}`);
    }
    p(``);

    // Compensator (same structure as buck)
    if (cc.topology === "opamp") {
      p(`* ------ COMPENSATOR: Op-amp ${cc.type==="type3"?"Type-III":"Type-II"} ------`);
      if (cc.type === "type3") {
        p(`* R1=${spv(cc.R1)} R2=${spv(cc.R2)} R3=${spv(cc.R3)} C1=${spv(cc.C1)} C2=${spv(cc.C2)} C3=${spv(cc.C3)}`);
        p(`Eea comp_raw gnd vref_node vfb_inj ${1e6}`);
        p(`Roa comp_raw comp 1`);
        p(`R1_comp vfb_inj comp ${spv(cc.R1)}`);
        p(`R2_comp comp comp_z ${spv(cc.R2)}`);
        p(`C2_comp comp_z gnd ${spv(cc.C2)}`);
        p(`C3_comp comp comp_z ${spv(cc.C3)}`);
        p(`R3_comp vfb_inj comp_p ${spv(cc.R3)}`);
        p(`C1_comp comp_p gnd ${spv(cc.C1)}`);
      } else {
        p(`* R1=${spv(cc.R1)} R2=${spv(cc.R2)} C1=${spv(cc.C1)} C2=${spv(cc.C2)}`);
        p(`Eea comp_raw gnd vref_node vfb_inj ${1e6}`);
        p(`Roa comp_raw comp 1`);
        p(`R1_comp vfb_inj comp ${spv(cc.R1)}`);
        p(`R2_comp comp comp_z ${spv(cc.R2)}`);
        p(`C2_comp comp_z gnd ${spv(cc.C2)}`);
        p(`C1_comp comp gnd ${spv(cc.C1)}`);
      }
    } else if (cc.topology === "ota") {
      p(`* ------ COMPENSATOR: OTA Type-II ------`);
      p(`Gea comp gnd vref_node vfb_inj ${spv((eaParams.gm_uAV||1650)*1e-6)}`);
      p(`Rout_ea comp gnd ${spv((eaParams.Rout_MOhm||7)*1e6)}`);
      if (cc.RCOMP) {
        p(`Rcomp comp comp_rc ${spv(cc.RCOMP)}`);
        p(`Ccomp comp_rc gnd ${spv(cc.CCOMP)}`);
        p(`Chf comp gnd ${spv(cc.CHF)}`);
      }
    }
    p(``);

  } else {
    // ------ Standard Averaged Plant (Buck / Forward) ------
    p(`* ------ PLANT: STANDARD AVERAGED CM MODEL ------`);
    p(`* Modulator gain Fm = ${Fm.toPrecision(4)}`);
    p(`* Duty-to-inductor: Gid = Vin / (sL + Zo)`);
    p(`* Using behavioral averaged switch model:`);
    p(``);
    p(`* Averaged inductor: V = VinxD - Vout`);
    p(`* D = Fm x (Vcomp - RixiL)  [peak CM]`);
    p(`L1 sw_out vout ${spv(L)}`);
    p(`* Averaged switch: Vsw = Vin x D`);
    p(`Bsw sw_out gnd V=V(vin)*limit(${Fm.toPrecision(4)}*(V(comp)-${spv(ri)}*I(L1)), 0, ${D>0.9?0.95:0.95})`);
    p(``);

    // ------ Compensator --------------------------------------------------------------------------
    if (cc.topology === "opamp") {
      p(`* ------ COMPENSATOR: Op-amp ${cc.type === "type3" ? "Type-III" : "Type-II"} ------`);
      if (cc.type === "type3") {
        p(`* R1=${spv(cc.R1)}  R2=${spv(cc.R2)}  R3=${spv(cc.R3)}`);
        p(`* C1=${spv(cc.C1)}  C2=${spv(cc.C2)}  C3=${spv(cc.C3)}`);
        p(``);
        p(`* Op-amp EA (ideal for now)`);
        p(`Eea comp_raw gnd vref_node vfb_inj ${1e6}`);
        p(`Roa comp_raw comp 1`);
        p(`* Feedback network`);
        p(`R1_comp vfb_inj comp ${spv(cc.R1)}`);
        p(`R2_comp comp comp_z ${spv(cc.R2)}`);
        p(`C2_comp comp_z gnd ${spv(cc.C2)}`);
        p(`C3_comp comp comp_z ${spv(cc.C3)}`);
        p(`R3_comp vfb_inj comp_p ${spv(cc.R3)}`);
        p(`C1_comp comp_p gnd ${spv(cc.C1)}`);
      } else {
        p(`* R1=${spv(cc.R1)}  R2=${spv(cc.R2)}`);
        p(`* C1=${spv(cc.C1)}  C2=${spv(cc.C2)}`);
        p(``);
        p(`* Op-amp EA (ideal for now)`);
        p(`Eea comp_raw gnd vref_node vfb_inj ${1e6}`);
        p(`Roa comp_raw comp 1`);
        p(`* Feedback network`);
        p(`R1_comp vfb_inj comp ${spv(cc.R1)}`);
        p(`R2_comp comp comp_z ${spv(cc.R2)}`);
        p(`C2_comp comp_z gnd ${spv(cc.C2)}`);
        p(`C1_comp comp gnd ${spv(cc.C1)}`);
      }
    } else if (cc.topology === "ota") {
      p(`* ------ COMPENSATOR: OTA Type-II ------`);
      p(`* RCOMP=${spv(cc.RCOMP)}  CCOMP=${spv(cc.CCOMP)}  CHF=${spv(cc.CHF)}`);
      p(``);
      p(`Gea comp gnd vref_node vfb_inj ${spv((eaParams.gm_uAV||1650)*1e-6)}`);
      p(`Rout_ea comp gnd ${spv((eaParams.Rout_MOhm||7)*1e6)}`);
      p(`Rcomp comp comp_rc ${spv(cc.RCOMP)}`);
      p(`Ccomp comp_rc gnd ${spv(cc.CCOMP)}`);
      p(`Chf comp gnd ${spv(cc.CHF)}`);
    }
    p(``);
  }

  // ------ COMP Clamps (both modes) ------------------------------------------
  // ------ COMP Clamps (skip for behavioral Laplace which has limit() built in) ------
  const needsDiodeClamps = !(plantMode === "gmps" && (cc.RCOMP || cc.topology === "ota"));
  if (needsDiodeClamps) {
    p(`* ------ COMP VOLTAGE CLAMPS ------`);
    p(`Dclamp_hi comp comp_clhi DCLAMP`);
    p(`Dclamp_lo comp_cllo comp DCLAMP`);
    p(`Vclamp_hi comp_clhi gnd ${compClampHigh||5}`);
    p(`Vclamp_lo comp_cllo gnd ${compClampLow||0}`);
    p(`.model DCLAMP D(N=0.1)`);
  }
  p(``);

  // ------ Feedback Divider + Loop Injection ----------------------------------
  p(`* ------ FEEDBACK DIVIDER + LOOP INJECTION ------`);
  p(`* H = Vref/Vout = ${H.toPrecision(4)}`);
  const Rfb_top = 10e3 * (1/H - 1);
  const Rfb_bot = 10e3;
  p(`Rfb_top vout vfb ${spv(Rfb_top)}`);
  p(`Rfb_bot vfb gnd ${spv(Rfb_bot)}`);
  p(``);

  p(`* ------ LOOP INJECTION (Middlebrook method) ------`);
  p(`* Inject between feedback node and EA input.`);
  p(`* For .ac: Vloop injects small-signal perturbation.`);
  p(`* T(s) = V(vfb)/V(vfb_inj)  (loop gain)`);
  p(`* PM = 180deg + phase(T) at |T|=0dB`);
  p(`Vloop vfb vfb_inj AC 1`);
  p(``);

  // ------ Reference ----------------------------------------------------------------------------------
  p(`* ------ REFERENCE ------`);
  p(`Vref vref_node gnd DC ${vref}`);
  p(`* (Reference connects to non-inverting EA input internally)`);
  p(``);

  // ------ Operating Point ----------------------------------------------------------------------
  p(`* --- INITIAL CONDITIONS (for .tran uic) ---`);
  p(`.ic V(vout)=${vout} V(comp)=${vcomp_ic.toPrecision(4)} V(comp_he)=${vcomp_ic.toPrecision(4)} V(comp_rc)=${vcomp_ic.toPrecision(4)} V(vfb)=${vfb_ic.toPrecision(4)} V(vfb_inj)=${vfb_ic.toPrecision(4)}`);
  p(``);

  // ------ Measurement ------------------------------------------------------------------------------
  p(`* ------ MEASUREMENTS ------`);
  p(`.meas ac fc WHEN mag(V(vfb)/V(vfb_inj))=1 CROSS=1`);
  p(`.meas ac loop_phase FIND phase(V(vfb)/V(vfb_inj)) WHEN mag(V(vfb)/V(vfb_inj))=1 CROSS=1`);
  p(`* Phase margin = 180 + loop_phase`);
  p(``);

  // ------ LTspice Plot Commands ----------------------------------------------------------
  p(`* ------ PLOT HINTS (LTspice) ------`);
  p(`* Bode: Plot V(vfb)/V(vfb_inj) as dB magnitude and phase`);
  p(`* Transient: Plot V(vout), I(L1), V(comp)`);
  p(``);

  p(`.end`);

  return lines.join("\n");
}

// ─── Phase 8.5: NGspice WASM Netlist Generator ────────────────────────
// Produces an NGspice-compatible behavioral netlist for client-side WASM simulation.
// Uses parallel decomposition compensator (same as simTimeDomain).
// Input: same cfg as simTimeDomain(). Output: { netlist, params }.
function generateNGspiceNetlist(cfg) {
  const {
    vin, vout_nom, iout, L, Ceff, ESR, fsw_hz,
    vref, comp, clampLow, clampHigh,
    gm_ps, stimulus, tTotal_us,
    slewSource_Aus, slewSink_Aus,
  } = cfg;

  const isType3 = comp.type === "type3";
  const wi = TWO_PI * (comp.fi || 1e3);
  const wz1 = TWO_PI * (isType3 ? (comp.fz1 || 1e3) : (comp.fz_c || 1e3));
  const wp1 = TWO_PI * (isType3 ? (comp.fp1 || 50e3) : (comp.fp_c || 50e3));
  const wz2 = isType3 ? TWO_PI * (comp.fz2 || 5e3) : 0;
  const wp2 = isType3 ? TWO_PI * (comp.fp2 || 150e3) : 0;

  const Ki = wi;
  let Kp1, Kp2;
  if (isType3) {
    const Kt = wi * wp1 * wp2 / (wz1 * wz2);
    Kp1 = Kt * (wp1 - wz1) * (wp1 - wz2) / (wp1 * (wp1 - wp2));
    Kp2 = Kt * (wp2 - wz1) * (wp2 - wz2) / (wp2 * (wp2 - wp1));
  } else {
    Kp1 = wi * (wp1 - wz1) / wz1;
    Kp2 = 0;
  }

  const H = vref / vout_nom;
  const Rfb_bot = 10e3;
  const Rfb_top = Rfb_bot * (vout_nom / vref - 1);
  const vcomp_ic = Math.max(clampLow, Math.min(clampHigh, clampLow + iout / Math.max(gm_ps, 0.01)));
  const rload = vout_nom / Math.max(iout, 0.001);

  const stim = stimulus || { type: "load_step", amplitude: 2, riseTime_us: 1, tStart_us: 50 };
  const tStart_s = (stim.tStart_us || 50) * 1e-6;
  const tRise_s = Math.max((stim.riseTime_us || 1) * 1e-6, 1e-8);
  const tTotal_s = (tTotal_us || 500) * 1e-6;
  const maxStep_s = 1 / (fsw_hz * 4);

  // Slew rate limiting
  const hasSlewUp = slewSource_Aus && slewSource_Aus > 0 && slewSource_Aus < 1e14;
  const hasSlewDn = slewSink_Aus && slewSink_Aus > 0 && slewSink_Aus < 1e14;
  const hasSlew = hasSlewUp || hasSlewDn;
  const slewUp = hasSlewUp ? slewSource_Aus : 1e15;
  const slewDn = hasSlewDn ? slewSink_Aus : 1e15;

  const lines = [];
  const p = (s) => lines.push(s);

  p(`Buck gm_ps WASM sim`);
  p(`* Vin=${vin}V Vout=${vout_nom}V Iout=${iout}A fsw=${fsw_hz/1e3}kHz`);
  p(`* gm_ps=${gm_ps}S L=${(L*1e6).toFixed(1)}uH C=${(Ceff*1e6).toFixed(0)}uF ESR=${(ESR*1e3).toFixed(1)}mR`);
  if (hasSlew) p(`* EA slew: src=${(slewUp/1e3).toFixed(1)}V/ms snk=${(slewDn/1e3).toFixed(1)}V/ms`);
  p(``);

  if (stim.type === "line_step") {
    p(`Vin vin 0 PULSE(${vin} ${vin + (stim.amplitude || 3)} ${tStart_s} ${tRise_s} ${tRise_s} 1 2)`);
  } else {
    p(`Vin vin 0 DC ${vin}`);
  }
  p(`Rvin_dummy vin 0 1e9`);
  p(``);

  p(`Rload vout 0 ${rload.toPrecision(6)}`);
  if (stim.type === "load_step") {
    p(`Istep vout 0 PULSE(0 ${stim.amplitude || 2} ${tStart_s} ${tRise_s} ${tRise_s} 1 2)`);
  }
  p(``);

  p(`Cout0 vout vout_esr ${Ceff.toPrecision(6)} ic=${vout_nom}`);
  p(`Resr0 vout_esr 0 ${ESR.toPrecision(6)}`);
  p(``);

  p(`Rfb_top vout vfb ${Rfb_top.toPrecision(6)}`);
  p(`Rfb_bot vfb 0 ${Rfb_bot.toPrecision(6)}`);
  p(``);

  p(`Berror error 0 V=${vref}-V(vfb)`);
  p(``);

  // Integrator: dV/dt = Ki * error → Bint pushes Ki*Cint*V(error) into Cint
  const Cint = 1e-6;
  p(`Bint 0 x_int I=${(Ki * Cint).toPrecision(6)}*V(error)`);
  p(`Cint x_int 0 ${Cint} ic=0`);
  p(`Rint x_int 0 1e12`);
  p(``);

  // Filter 1: first-order pole at wp1
  const Cfilt1 = 1e-9;
  const Rfilt1 = 1 / (wp1 * Cfilt1);
  p(`Bfilt1 0 x_filt1 I=${(Kp1 * Cfilt1).toPrecision(6)}*V(error)`);
  p(`Cfilt1 x_filt1 0 ${Cfilt1} ic=0`);
  p(`Rfilt1 x_filt1 0 ${Rfilt1.toPrecision(6)}`);
  p(``);

  // Filter 2 (Type-III only)
  if (isType3 && Kp2 !== 0) {
    const Cfilt2 = 1e-9;
    const Rfilt2 = 1 / (wp2 * Cfilt2);
    p(`Bfilt2 0 x_filt2 I=${(Kp2 * Cfilt2).toPrecision(6)}*V(error)`);
    p(`Cfilt2 x_filt2 0 ${Cfilt2} ic=0`);
    p(`Rfilt2 x_filt2 0 ${Rfilt2.toPrecision(6)}`);
    p(``);
    p(`Bcomp_raw comp_raw 0 V=V(x_int)+V(x_filt1)+V(x_filt2)+${vcomp_ic.toPrecision(6)}`);
  } else {
    p(`Bcomp_raw comp_raw 0 V=V(x_int)+V(x_filt1)+${vcomp_ic.toPrecision(6)}`);
  }
  p(`Rcd_raw comp_raw 0 1e9`);
  p(``);

  // Slew rate limiter + voltage clamp → comp node
  if (hasSlew) {
    // Rate limiter: capacitor charged by clamped current source
    // dV(comp_slew)/dt = I/Cslew, where I is clamped to ±slewRate×Cslew
    // Gtrack (1e6) makes comp_slew track comp_raw closely when not slew-limited
    const Cslew = 1e-9;
    const Imax_src = slewUp * Cslew;  // max charging current for +slew
    const Imax_snk = slewDn * Cslew;  // max discharging current for -slew
    p(`* EA slew rate limiter: ↑${(slewUp/1e3).toFixed(1)} V/ms, ↓${(slewDn/1e3).toFixed(1)} V/ms`);
    p(`Bslew 0 comp_slew I=min(max((V(comp_raw)-V(comp_slew))*1e-3, -${Imax_snk.toPrecision(6)}), ${Imax_src.toPrecision(6)})`);
    p(`Cslew comp_slew 0 ${Cslew} ic=${vcomp_ic.toPrecision(6)}`);
    p(`Rslew comp_slew 0 1e12`);
    p(`Bcomp comp 0 V=min(max(V(comp_slew), ${clampLow}), ${clampHigh})`);
  } else {
    p(`Bcomp comp 0 V=min(max(V(comp_raw), ${clampLow}), ${clampHigh})`);
  }
  p(`Rcd comp 0 1e9`);
  p(``);

  p(`Bps 0 vout I=${gm_ps}*max(V(comp)-${clampLow}, 0)`);
  p(``);

  const icNodes = `V(vout)=${vout_nom} V(comp)=${vcomp_ic.toPrecision(6)} V(vfb)=${(H * vout_nom).toPrecision(6)}`;
  const icSlew = hasSlew ? ` V(comp_slew)=${vcomp_ic.toPrecision(6)}` : ``;
  p(`.ic ${icNodes}${icSlew}`);
  p(`.tran ${maxStep_s.toPrecision(4)} ${tTotal_s.toPrecision(6)} uic`);
  p(`.end`);

  return { netlist: lines.join("\n"), params: { vcomp_ic, Ki, Kp1, Kp2, hasSlew, slewUp, slewDn } };
}

// ─── Parse WASM NGspice results into tdSim data contract ──────────
function parseNGspiceResults(res, cfg) {
  const { vout_nom, iout, vin, gm_ps, clampLow, clampHigh, stimulus, slewSource_Aus, slewSink_Aus,
          L, fsw_hz } = cfg;
  const stim = stimulus || { type: "load_step", amplitude: 2, riseTime_us: 1, tStart_us: 50 };

  const time = res.data.find(d => d.name === "time");
  const voutVec = res.data.find(d => d.name === "v(vout)");
  const compVec = res.data.find(d => d.name === "v(comp)");
  const vinVec = res.data.find(d => d.name === "v(vin)");

  if (!time || !voutVec) return null;

  const N = time.values.length;
  const tStart_us = stim.tStart_us || 50;
  const tRise_us = stim.riseTime_us || 1;
  function getStimVal(t_us) {
    if (t_us < tStart_us) return 0;
    return (stim.amplitude || 2) * Math.min((t_us - tStart_us) / tRise_us, 1);
  }

  const targetPts = 600;
  const decimation = Math.max(1, Math.floor(N / targetPts));

  // First pass: extract raw iL and smooth with LP filter matching analytical tracker BW (fsw/6)
  const bw_inner = (fsw_hz || 800e3) / 6;
  const tau = 1 / (TWO_PI * bw_inner);  // ~1.2 µs at 800kHz
  const L_val = L || 4.7e-6;
  const Dmax = 0.92;

  let iL_smooth = iout; // start at steady-state
  const rawData = []; // collect all points first

  let clamped = false, dcm_entered = false;
  let slewLimited_src = false, slewLimited_snk = false;
  let peakSlewUp_actual = 0, peakSlewDn_actual = 0;
  let prevComp = null, prevT_s = null;
  const slewUp = (slewSource_Aus && slewSource_Aus > 0) ? slewSource_Aus : 1e15;
  const slewDn = (slewSink_Aus && slewSink_Aus > 0) ? slewSink_Aus : 1e15;

  for (let i = 0; i < N; i++) {
    const t_s = time.values[i];
    const t_us = t_s * 1e6;
    const vout_V = voutVec.values[i];
    const vcomp_V = compVec ? compVec.values[i] : 0;
    const vin_V = vinVec ? vinVec.values[i] : vin;

    // Slew detection
    let slewState = 0;
    if (prevComp !== null && prevT_s !== null) {
      const dt_s = t_s - prevT_s;
      if (dt_s > 0) {
        const dvdt = (vcomp_V - prevComp) / dt_s;
        if (dvdt > 0 && dvdt > peakSlewUp_actual) peakSlewUp_actual = dvdt;
        if (dvdt < 0 && -dvdt > peakSlewDn_actual) peakSlewDn_actual = -dvdt;
        if (dvdt > slewUp) { slewLimited_src = true; slewState = 1; }
        if (dvdt < -slewDn) { slewLimited_snk = true; slewState = -1; }
      }
    }
    prevComp = vcomp_V;
    prevT_s = t_s;

    if (vcomp_V <= clampLow * 1.001 || vcomp_V >= clampHigh * 0.999) clamped = true;

    // Raw algebraic iL from gm_ps plant (same as Bps in netlist)
    const iL_target = gm_ps * Math.max(vcomp_V - clampLow, 0);

    // LP-filter iL to model inner current loop bandwidth (matches analytical tracker)
    const dt_s = (prevT_s !== null && i > 0) ? (t_s - (time.values[i-1])) : 1e-7;
    const alpha = Math.min(dt_s / tau, 1);
    iL_smooth = iL_smooth + alpha * (iL_target - iL_smooth);
    if (iL_smooth < 0) { iL_smooth = 0; dcm_entered = true; }
    if (iL_smooth <= 0.001 && t_us > tStart_us) dcm_entered = true;

    // Compute D from same relationship as analytical model:
    // D = (L × diL/dt_target + Vout) / Vin
    const error_i = iL_target - iL_smooth;
    const diL_target = TWO_PI * bw_inner * error_i;
    const D = Math.max(0, Math.min(Dmax, (L_val * diL_target + vout_nom) / Math.max(vin_V, 0.1)));
    const D_pct = D * 100;

    const stimVal = getStimVal(t_us);
    const iout_A = stim.type === "load_step" ? iout + stimVal : iout;
    const vin_val = stim.type === "line_step" ? vin + stimVal : vin_V;

    if (i % decimation === 0) {
      rawData.push({
        t_us: parseFloat(t_us.toFixed(3)),
        vout_mv: parseFloat(((vout_V - vout_nom) * 1e3).toFixed(2)),
        vout_V: parseFloat(vout_V.toFixed(4)),
        iL_A: parseFloat(iL_smooth.toFixed(4)),
        vcomp_V: parseFloat(vcomp_V.toFixed(4)),
        D_pct: parseFloat(D_pct.toFixed(2)),
        iout_A: parseFloat(iout_A.toFixed(3)),
        vin_V: parseFloat(vin_val.toFixed(3)),
        slew: slewState,
      });
    }
  }

  const data = rawData;

  let peakUndershoot = 0, peakOvershoot = 0, settlingTime = null;
  const stimIdx = data.findIndex(d => d.t_us >= tStart_us);
  if (stimIdx >= 0) {
    for (let i = stimIdx; i < data.length; i++) {
      if (data[i].vout_mv < peakUndershoot) peakUndershoot = data[i].vout_mv;
      if (data[i].vout_mv > peakOvershoot) peakOvershoot = data[i].vout_mv;
    }
    const band = vout_nom * 0.02 * 1e3;
    for (let i = data.length - 1; i >= stimIdx; i--) {
      if (Math.abs(data[i].vout_mv) > band) { settlingTime = data[i].t_us - tStart_us; break; }
    }
  }

  return {
    data, peakUndershoot, peakOvershoot, settlingTime, clamped, dcm_entered,
    stimType: stim.type, slewLimited_src, slewLimited_snk,
    peakSlewUp_Vms: peakSlewUp_actual / 1e3,
    peakSlewDn_Vms: peakSlewDn_actual / 1e3,
    slewLimit_src_Vms: slewUp < 1e14 ? slewUp / 1e3 : null,
    slewLimit_snk_Vms: slewDn < 1e14 ? slewDn / 1e3 : null,
    engine: "spice",
  };
}

// ------ IC Curated Library --------------------------------------------------------------------------
const IC_LIBRARY = [
  { id:"custom", name:"Custom / Manual", desc:"Enter all parameters manually", mfg:"--", supportedTopologies:["buck","2sw_fwd","flyback"] },
  { id:"tps7h4011", name:"TPS7H4011-SP", desc:"Rad-hard 4.5–14V 12A sync buck, peak CM",
    mfg:"TI", link:"https://www.ti.com/product/TPS7H4011-SP",
    ea:"ota", gm_uAV:1650, Rout_MOhm:7.0, Cout_pF:0, Aol_dB:81,
    vref:0.6, senseInternal:true, plantMode:"gmps",
    gmps_table: [
      { ilim_A:3,  gm_ps:7.2,  Rlim_top:"∞", Rlim_bot:"0" },
      { ilim_A:6,  gm_ps:11,   Rlim_top:"100k", Rlim_bot:"49.9k" },
      { ilim_A:9,  gm_ps:16.1, Rlim_top:"49.9k", Rlim_bot:"100k" },
      { ilim_A:12, gm_ps:22.4, Rlim_top:"0", Rlim_bot:"∞" },
    ],
    defaultIlimIdx: 3,
    senseMode:"simple", ri:0.045,
    fsw_max_kHz:2000, Dmax:0.92, tLEB_ns:120, csDelay_ns:0,
    compClampLow:0.4, compClampHigh:2.0,
    eaIsrc_uA:125, eaIsnk_uA:125,
    slopeComp:"external_rsc",
    // Signal conditioning: gm_ps mode — divider absorbed into gm characterization
    compDividerRatio:1, compDiodeDrop_V:0, csOffset_mV:0,
    supportedTopologies:["buck"],
    notes:"Integrated FETs. gm_ps set by ILIM config (7.2–22.4 S). OTA EA: gm=1650uA/V, Aol=81dB, Rout=7MR, EABW=9MHz. Slope comp via RSC resistor." },
  { id:"ucc28c43", name:"UCC28C43", desc:"BiCMOS CM controller, Dmax=100%",
    mfg:"TI", link:"https://www.ti.com/product/UCC28C43",
    ea:"opamp", Aol_dB:90, GBW_MHz:7, PM_ea_deg:60,
    vref:5.0, senseMode:"simple", ri:0.05,
    fsw_max_kHz:1000, Dmax:1.0, tLEB_ns:110, csDelay_ns:80,
    compClampLow:0.9, compClampHigh:5.5,
    eaIsrc_uA:1000, eaIsnk_uA:1000,
    compDividerRatio:1, compDiodeDrop_V:0, csOffset_mV:0,
    supportedTopologies:["buck","2sw_fwd","flyback"],
    notes:"BiCMOS improved UC384x. Direct COMP-to-comparator (no internal divider). 1A gate driver." },
  { id:"ucc28c44", name:"UCC28C44", desc:"BiCMOS CM controller, Dmax=50%",
    mfg:"TI", link:"https://www.ti.com/product/UCC28C44",
    ea:"opamp", Aol_dB:90, GBW_MHz:7, PM_ea_deg:60,
    vref:5.0, senseMode:"simple", ri:0.05,
    fsw_max_kHz:1000, Dmax:0.50, tLEB_ns:110, csDelay_ns:80,
    compClampLow:0.9, compClampHigh:5.5,
    eaIsrc_uA:1000, eaIsnk_uA:1000,
    compDividerRatio:1, compDiodeDrop_V:0, csOffset_mV:0,
    supportedTopologies:["buck","2sw_fwd"],
    notes:"50% Dmax version. Direct COMP-to-comparator. For half-bridge and two-switch forward." },
  { id:"uc3842", name:"UC3842/3", desc:"Industry standard peak CM, Dmax=100%",
    mfg:"TI", link:"https://www.ti.com/product/UC3842",
    ea:"opamp", Aol_dB:90, GBW_MHz:1, PM_ea_deg:45,
    vref:5.0, senseMode:"simple", ri:0.05,
    fsw_max_kHz:500, Dmax:1.0, tLEB_ns:120, csDelay_ns:150,
    compClampLow:1.0, compClampHigh:5.5,
    eaIsrc_uA:800, eaIsnk_uA:1000,
    // Internal: 2 diodes (~1.4V) + 1/3 divider between COMP and PWM comparator
    compDividerRatio:3, compDiodeDrop_V:1.4, csOffset_mV:0,
    supportedTopologies:["buck","2sw_fwd","flyback"],
    notes:"Legacy standard. Internal 2-diode (1.4V) + 1/3 divider: CS threshold = (VCOMP-1.4)/3. Max CS = 1.37V. UVLO 16V/10V (842) or 8.4V/7.6V (843)." },
  { id:"uc3844", name:"UC3844/5", desc:"Industry standard peak CM, Dmax=50%",
    mfg:"TI", link:"https://www.ti.com/product/UC3844",
    ea:"opamp", Aol_dB:90, GBW_MHz:1, PM_ea_deg:45,
    vref:5.0, senseMode:"simple", ri:0.05,
    fsw_max_kHz:500, Dmax:0.50, tLEB_ns:120, csDelay_ns:150,
    compClampLow:1.0, compClampHigh:5.5,
    eaIsrc_uA:800, eaIsnk_uA:1000,
    compDividerRatio:3, compDiodeDrop_V:1.4, csOffset_mV:0,
    supportedTopologies:["buck","2sw_fwd"],
    notes:"50% Dmax version. Internal 2-diode + 1/3 divider. Internal 1V clamp enforces Dmax. For half-bridge and forward." },
  { id:"ucc28780", name:"UCC28780", desc:"Active clamp flyback controller",
    mfg:"TI", link:"https://www.ti.com/product/UCC28780",
    ea:"ota", gm_uAV:150, Rout_MOhm:15, Cout_pF:4, Aol_dB:70,
    vref:4.0, senseMode:"simple", ri:0.05,
    fsw_max_kHz:1000, Dmax:0.68, tLEB_ns:80, csDelay_ns:50,
    compClampLow:0.3, compClampHigh:3.3,
    eaIsrc_uA:100, eaIsnk_uA:100,
    compDividerRatio:1, compDiodeDrop_V:0, csOffset_mV:0,
    supportedTopologies:["flyback"],
    notes:"Integrated active clamp. Adaptive dead time. Multi-mode operation." },
  { id:"isl71043m", name:"ISL71043MBZ", desc:"Rad-tolerant peak CM, Dmax=100%",
    mfg:"Renesas", link:"https://www.renesas.com/en/document/dst/isl71043m-isl71041m-datasheet",
    ea:"opamp", Aol_dB:90, GBW_MHz:1.5, PM_ea_deg:45,
    vref:2.5, senseMode:"simple", ri:0.05,
    fsw_max_kHz:1000, Dmax:1.0, tLEB_ns:0, csDelay_ns:35,
    compClampLow:0.4, compClampHigh:5.0,
    eaIsrc_uA:500, eaIsnk_uA:5000,
    slopeComp:"external_rtct",
    // Internal: 2 diodes (1.15V total) + 1/3 divider + 100mV CS offset
    compDividerRatio:3, compDiodeDrop_V:1.15, csOffset_mV:100,
    supportedTopologies:["buck","2sw_fwd","flyback"],
    notes:"Rad-tolerant (30/50 krad TID). Internal 2-diode (1.15V) + 1/3 divider: CS threshold = (VCOMP-1.15)/3 - 0.1V. CS-to-COMP gain ≈ 3V/V. No internal LEB. -55°C to +125°C." },
  { id:"isl71041m", name:"ISL71041MBZ", desc:"Rad-tolerant peak CM, Dmax=50%",
    mfg:"Renesas", link:"https://www.renesas.com/en/document/dst/isl71043m-isl71041m-datasheet",
    ea:"opamp", Aol_dB:90, GBW_MHz:1.5, PM_ea_deg:45,
    vref:2.5, senseMode:"simple", ri:0.05,
    fsw_max_kHz:1000, Dmax:0.50, tLEB_ns:0, csDelay_ns:35,
    compClampLow:0.4, compClampHigh:5.0,
    eaIsrc_uA:500, eaIsnk_uA:5000,
    slopeComp:"external_rtct",
    compDividerRatio:3, compDiodeDrop_V:1.15, csOffset_mV:100,
    supportedTopologies:["buck","2sw_fwd"],
    notes:"50% Dmax version. Internal 2-diode (1.15V) + 1/3 divider + 1.1V internal clamp. Rad-tolerant (30/50 krad TID). -55°C to +125°C." },
];

// ------ Styles --------------------------------------------------------------------------------------------------
const col = {
  bg: "#0b0f14", panel: "#111820", border: "#1c2736", text: "#b0c4d8",
  dim: "#4e6378", bright: "#e4edf6", accent: "#2f7cf6", plant: "#06d6c2",
  comp: "#a78bfa", loop: "#f5a623", err: "#ef4444", warn: "#eab308",
  info: "#3b82f6", ok: "#22c55e", grid: "#161f2b",
};
const sInput = {
  background: col.bg, border: `1px solid ${col.border}`, color: col.bright,
  borderRadius: 3, padding: "4px 7px", width: "100%", fontSize: 13, boxSizing: "border-box",
  fontFamily: "'JetBrains Mono','Fira Code',monospace", outline: "none",
};
const sLabel = { color: col.dim, fontSize: 10.5, marginBottom: 1, display: "block", fontFamily: "'IBM Plex Sans',sans-serif", letterSpacing: "0.06em" };
const sSection = { color: col.bright, fontSize: 12, fontWeight: 700, marginBottom: 6, marginTop: 4, fontFamily: "'IBM Plex Sans',sans-serif", letterSpacing: "0.05em" };
const sDivider = { margin: "6px 0", borderTop: `1px solid ${col.border}` };

// ------ Main ------------------------------------------------------------------------------------------------------
export default function BuckCMTool() {
  // Topology
  const [topology, setTopology] = useState("buck"); // "buck" | "2sw_fwd" | "flyback"
  // Transformer (2SW forward)
  const [xfmrNp, setXfmrNp] = useState(20);        // primary turns
  const [xfmrNs, setXfmrNs] = useState(5);          // secondary turns
  const [xfmrLm, setXfmrLm] = useState(500);        // magnetizing inductance µH
  const turnsRatio = xfmrNs / Math.max(xfmrNp, 1);  // n = Ns/Np
  const isIsolated = topology === "2sw_fwd" || topology === "flyback";
  // Auxiliary (unregulated) secondary outputs — contribute to primary-side Sn only
  // The main output (xfmrNs, vout, L, capBank) is the regulated output
  const [auxSecondaries, setAuxSecondaries] = useState([]); // [{ns, lout_uH, vout, label}]

  const [vinMin, setVinMin] = useState(9);
  const [vinMax, setVinMax] = useState(15);
  const [useVinNom, setUseVinNom] = useState(false);
  const [vinNomUser, setVinNomUser] = useState(12);
  const [vout, setVout] = useState(3.3);
  const [voutTol, setVoutTol] = useState(2); // ±%
  const [iout, setIout] = useState(5);
  const [fsw, setFsw] = useState(300);
  const [L, setL] = useState(10);
  // Cap bank: array of cap slots
  const [capSlots, setCapSlots] = useState([
    { qty: 1, c_uF: 220, esr_mOhm: 20, esl_nH: 0, type: "electrolytic" },
  ]);
  const updateCapSlot = (idx, field, val) => {
    setCapSlots(prev => prev.map((s, i) => i === idx ? { ...s, [field]: val } : s));
  };
  const addCapSlot = () => {
    if (capSlots.length < 3) setCapSlots(prev => [...prev, { qty: 1, c_uF: 10, esr_mOhm: 5, esl_nH: 1, type: "mlcc_x7r" }]);
  };
  const removeCapSlot = (idx) => {
    if (capSlots.length > 1) setCapSlots(prev => prev.filter((_, i) => i !== idx));
  };
  const [showCapCSV, setShowCapCSV] = useState(false);
  const [capCSVText, setCapCSVText] = useState("");
  const [capCSVResult, setCapCSVResult] = useState(null); // {C_F, ESR_ohm, ESL_H, f_srf, nPoints} or {error}
  // Build capBank array in SI units for physics functions
  const capBank = useMemo(() => capSlots.map(s => ({
    qty: s.qty,
    cap_F: s.c_uF * 1e-6,
    esr_ohm: s.esr_mOhm * 1e-3,
    esl_H: s.esl_nH * 1e-9,
    type: s.type,
  })), [capSlots]);
  // Effective values for display
  const capEff = useMemo(() => getCapBankEffective(capBank), [capBank]);
  // Anti-resonance detection
  const antiRes = useMemo(() => detectAntiResonance(capBank), [capBank]);
  const [ri, setRi] = useState(0.05);
  const [se, setSe] = useState(0);
  const [scAus, setScAus] = useState(1.5);     // Slope comp in A/us (TPS7H4011 datasheet units)
  const [rscKohm, setRscKohm] = useState(196); // RSC resistor in kR
  const [scEnabled, setScEnabled] = useState(false); // SC correction toggle -- OFF by default for gm_ps (SPICE handles SC internally)
  // Sense configuration
  const [senseMode, setSenseMode] = useState("simple"); // "simple" | "shunt" | "ct"
  const [sensePlacement, setSensePlacement] = useState("high_side"); // "high_side" | "inductor"
  // For isolated topologies: which side of the transformer is the current sense on?
  // "primary" = CT/shunt on primary (sees reflected Iout + Im) — typical for UC3844/5
  // "secondary" = CT/shunt on secondary (sees Iout only, no Im) — typical for LTC3726
  const [isoSenseSide, setIsoSenseSide] = useState("primary");
  // Effective Lm correction flag: true when sensing primary current in an isolated topology
  const lmAffectsSn = isIsolated && isoSenseSide === "primary";
  const [rshunt, setRshunt] = useState(50);    // mR
  const [lpar, setLpar] = useState(2);          // nH
  const [gampDC, setGampDC] = useState(1);      // V/V
  const [gampBW, setGampBW] = useState(50);     // MHz
  const [rfilter, setRfilter] = useState(0);    // R
  const [cfilter, setCfilter] = useState(0);    // pF
  const [tLEB, setTLEB] = useState(100);        // ns
  // CT parameters
  const [ctNp, setCtNp] = useState(1);          // primary turns
  const [ctNs, setCtNs] = useState(100);        // secondary turns
  const [ctRb, setCtRb] = useState(10);         // burden R
  const [ctLm, setCtLm] = useState(10);         // magnetizing inductance mH
  const [ctLlk, setCtLlk] = useState(1);        // leakage inductance uH
  const [ctCw, setCtCw] = useState(10);         // winding capacitance pF
  const [ctReset, setCtReset] = useState("self"); // "self" | "forced"
  // Computed sense params (SI units)
  const senseParams = useMemo(() => {
    if (senseMode === "simple") return { mode: "simple", ri };
    if (senseMode === "ct") {
      const turnsRatio = ctNs / Math.max(ctNp, 1);
      return { mode: "ct", turnsRatio, rb: ctRb, lm: ctLm * 1e-3, llk: ctLlk * 1e-6, cw: ctCw * 1e-12, ri: ctRb / turnsRatio, reset: ctReset };
    }
    const rs = rshunt * 1e-3;
    return { mode: "shunt", rshunt: rs, lpar: lpar * 1e-9, gampDC, gampBW: gampBW * 1e6, rfilter, cfilter: cfilter * 1e-12, ri: rs * gampDC };
  }, [senseMode, ri, rshunt, lpar, gampDC, gampBW, rfilter, cfilter, ctNp, ctNs, ctRb, ctLm, ctLlk, ctCw, ctReset]);
  // Effective Ri used in plant model
  // CT: Ri = (Np/Ns) × Rb. Secondary current = I_primary × Np/Ns, sense voltage = I_sec × Rb.
  const ri_eff = senseMode === "shunt" ? rshunt * 1e-3 * gampDC : senseMode === "ct" ? ctRb * ctNp / Math.max(ctNs, 1) : ri;
  const [vref, setVref] = useState(0.8);
  // Opto-isolator or primary-side feedback (isolated topologies)
  const [fbMode, setFbMode] = useState("opto"); // "opto" | "primary"
  const [optoCTR, setOptoCTR] = useState(1.0);      // current transfer ratio (dimensionless)
  const [optoRpullup, setOptoRpullup] = useState(5); // primary pullup kΩ
  const [optoRled, setOptoRled] = useState(1);        // LED series resistor kΩ
  const [optoCopto, setOptoCopto] = useState(2);      // opto collector-emitter parasitic cap nF
  // DC feedback gain:
  //   Opto: H_dc = (Vref/Vout) × CTR × Rpullup / Rled  (gain from opto path)
  //   Primary-side: H_dc = Vref/Vout  (aux winding + divider, turns ratio cancels)
  const optoGain = isIsolated && fbMode === "opto" ? (optoCTR * optoRpullup / Math.max(optoRled, 0.01)) : 1;
  // Opto pole: fp = 1/(2π·Rpullup·Copto) — only for opto mode
  const fp_opto = isIsolated && fbMode === "opto" && optoCopto > 0 ? 1 / (TWO_PI * optoRpullup * 1e3 * optoCopto * 1e-9) : 0;
  const [deltaI, setDeltaI] = useState(2);
  const [tempCorner, setTempCorner] = useState("nominal");
  // Phase 7: Time-domain stimulus config
  const [stimType, setStimType] = useState("load_step");  // "load_step" | "line_step"
  const [stimRiseTime, setStimRiseTime] = useState(1);     // us
  const [rise1090, setRise1090] = useState(false);         // 10-90% mode
  const [stimDeltaVin, setStimDeltaVin] = useState(3);     // V (for line step)

  // App view: "setup" (root page) or "analyze" (analysis page)
  const [view, setView] = useState("setup"); // kept for compat, always "setup" now
  // Card visibility toggles — false = collapsed/hidden but state preserved
  const [cardVis, setCardVis] = useState({
    topo: true, xfmr: true, pstage: true, caps: true,
    sense: true, slope: true, ic: true, opto: true,
    ea: true, comp: true,
  });
  const toggleCard = (key) => setCardVis(prev => ({...prev, [key]: !prev[key]}));
  // ─── Live Activity Log ─────────────────────────────────
  const [logEntries, setLogEntries] = useState([]);
  const [showLog, setShowLog] = useState(false);
  const logRef = useRef(null);
  const addLog = useCallback((category, msg) => {
    const ts = new Date().toLocaleTimeString("en-US", { hour12: false, hour: "2-digit", minute: "2-digit", second: "2-digit" });
    setLogEntries(prev => {
      const entry = { ts, category, msg };
      const next = [...prev, entry];
      return next.length > 200 ? next.slice(-200) : next; // keep last 200
    });
  }, []);
  const [snapText, setSnapText] = useState(""); // snapshot text for manual copy
  const [advisorText, setAdvisorText] = useState(""); // AI advisor output
  const [advisorLoading, setAdvisorLoading] = useState(false);

  // Phase 8.5: WASM NGspice engine state
  const [simEngine, setSimEngine] = useState("analytical"); // "analytical" | "spice"
  const [ngspiceReady, setNgspiceReady] = useState(false);
  const [ngspiceLoading, setNgspiceLoading] = useState(false);
  const [ngspiceError, setNgspiceError] = useState(null);
  const [spiceSim, setSpiceSim] = useState(null);
  const [spiceRunning, setSpiceRunning] = useState(false);
  const [spiceElapsed, setSpiceElapsed] = useState(null);
  const ngspiceRef = useRef(null);

  // Frozen compensation
  const [frozenComp, setFrozenComp] = useState(null);
  const [compMode, setCompMode] = useState("auto"); // "auto" | "manual"
  const [compType, setCompType] = useState("type2"); // "type2" | "type3"
  // Manual state for Type-II
  const [manFzC, setManFzC] = useState(100);
  const [manFpC, setManFpC] = useState(30000);
  const [manFi, setManFi] = useState(1000);
  // Manual state for Type-III
  const [manFz1, setManFz1] = useState(1000);
  const [manFz2, setManFz2] = useState(5000);
  const [manFp1, setManFp1] = useState(30000);
  const [manFp2, setManFp2] = useState(150000);
  const [manFi3, setManFi3] = useState(500);
  const [fcTarget, setFcTarget] = useState(30);

  // Input filter
  const [showInputFilter, setShowInputFilter] = useState(false);
  // Phase 6: Audio susceptibility spec limits
  const [specZoutMax, setSpecZoutMax] = useState(50);     // mR (max Zout_cl at DC)
  const [specGvgMax, setSpecGvgMax] = useState(-40);      // dB (max Gvg_cl, negative = attenuation)
  const [lin, setLin] = useState(1);
  const [cin, setCin] = useState(100);
  const [rd, setRd] = useState(0.5);

  // Error amplifier
  const [eaType, setEaType] = useState("ideal"); // "ideal" | "opamp" | "ota"
  const [eaAol, setEaAol] = useState(90);         // dB
  const [eaGBW, setEaGBW] = useState(7);           // MHz
  const [eaPM, setEaPM] = useState(60);             // degrees
  const [eaGm, setEaGm] = useState(225);            // uA/V
  const [eaRout, setEaRout] = useState(8.7);        // MR
  const [eaCout, setEaCout] = useState(5.4);         // pF
  const [compClampLow, setCompClampLow] = useState(0.9);  // V
  const [compClampHigh, setCompClampHigh] = useState(5.5); // V
  const [csDelay, setCsDelay] = useState(0);         // ns
  const [eaIsrc, setEaIsrc] = useState(125);          // uA -- EA source current
  const [eaIsnk, setEaIsnk] = useState(125);          // uA -- EA sink current

  // IC Library
  const [selectedIC, setSelectedIC] = useState("custom");
  const [plantMode, setPlantMode] = useState("standard"); // "standard" | "gmps"
  const [gmps, setGmps] = useState(20);                   // S (power stage transconductance)
  const [ilimIdx, setIlimIdx] = useState(3);               // index into gmps_table
  const applyIC = useCallback((id) => {
    setSelectedIC(id);
    if (id === "custom") {
      setPlantMode("standard");
      return;
    }
    const ic = IC_LIBRARY.find(x => x.id === id);
    if (!ic) return;
    // EA
    if (ic.ea === "opamp") {
      setEaType("opamp");
      if (ic.Aol_dB !== undefined) setEaAol(ic.Aol_dB);
      if (ic.GBW_MHz !== undefined) setEaGBW(ic.GBW_MHz);
      if (ic.PM_ea_deg !== undefined) setEaPM(ic.PM_ea_deg);
    } else if (ic.ea === "ota") {
      setEaType("ota");
      if (ic.gm_uAV !== undefined) setEaGm(ic.gm_uAV);
      if (ic.Rout_MOhm !== undefined) setEaRout(ic.Rout_MOhm);
      if (ic.Cout_pF !== undefined) setEaCout(ic.Cout_pF);
    }
    // Reference
    if (ic.vref !== undefined) setVref(ic.vref);
    // Sense
    if (ic.senseMode !== undefined) setSenseMode(ic.senseMode);
    if (ic.ri !== undefined) setRi(ic.ri);
    // Clamps & timing
    if (ic.compClampLow !== undefined) setCompClampLow(ic.compClampLow);
    if (ic.compClampHigh !== undefined) setCompClampHigh(ic.compClampHigh);
    if (ic.csDelay_ns !== undefined) setCsDelay(ic.csDelay_ns);
    if (ic.eaIsrc_uA !== undefined) setEaIsrc(ic.eaIsrc_uA);
    if (ic.eaIsnk_uA !== undefined) setEaIsnk(ic.eaIsnk_uA);
    if (ic.tLEB_ns !== undefined) setTLEB(ic.tLEB_ns);
    // Plant mode
    if (ic.plantMode === "gmps") {
      setPlantMode("gmps");
      const idx = ic.defaultIlimIdx !== undefined ? ic.defaultIlimIdx : 0;
      setIlimIdx(idx);
      if (ic.gmps_table && ic.gmps_table[idx]) setGmps(ic.gmps_table[idx].gm_ps);
    } else {
      setPlantMode("standard");
    }
    // Reset comp to recalculate for new plant
    setFrozenComp(null);
  }, []);

  // When ilim changes, update gmps from table
  const applyIlim = useCallback((idx) => {
    setIlimIdx(idx);
    const ic = IC_LIBRARY.find(x => x.id === selectedIC);
    if (ic && ic.gmps_table && ic.gmps_table[idx]) {
      setGmps(ic.gmps_table[idx].gm_ps);
      setFrozenComp(null); // recalc comp for new plant
    }
  }, [selectedIC]);

  // UI
  const [showPlant, setShowPlant] = useState(true);
  const [showComp, setShowComp] = useState(true);
  const [showLoop, setShowLoop] = useState(true);
  const [showSubBlocks, setShowSubBlocks] = useState(false);
  const [activeTab, setActiveTab] = useState("bode");
  const [vinCorner, setVinCorner] = useState("nom"); // "min" | "nom" | "max"

  // ------ Derived operating point ------------------------------------------------------------
  const vinNom = useVinNom ? vinNomUser : (vinMin + vinMax) / 2;
  const vinActive = vinCorner === "min" ? vinMin : vinCorner === "max" ? vinMax : vinNom;
  const vinActiveLabel = vinCorner === "min" ? `${vinMin}V (min)` : vinCorner === "max" ? `${vinMax}V (max)` : `${vinNom.toFixed(1)}V (nom)`;
  const voutMin = vout * (1 - voutTol / 100);
  const voutMax = vout * (1 + voutTol / 100);
  // Effective input voltage seen by output LC filter
  // Buck: Vin_eff = Vin.  2SW Forward: Vin_eff = Vin × Ns/Np.  Flyback: Vin_eff = Vin × Ns/Np (for D calc)
  const n = isIsolated ? turnsRatio : 1;
  const vinEffNom = vinNom * n;
  const vinEffMin = vinMin * n;
  const vinEffMax = vinMax * n;
  const vinEffActive = vinActive * n;
  // Flyback duty: D = Vout / (Vout + Vin×n).  Buck/Forward: D = Vout / (Vin×n)
  const isFlyback = topology === "flyback";
  const calcD = (v_eff) => isFlyback ? vout / Math.max(vout + v_eff, 0.01) : vout / Math.max(v_eff, 0.01);
  const Dnom = calcD(vinEffNom);
  const Dmax = calcD(vinEffMin);   // min Vin → max D
  const Dmin = calcD(vinEffMax);   // max Vin → min D
  const Dactive = calcD(vinEffActive);
  // Hard Dmax constraint: 2SW forward must stay ≤ 50% for magnetizing reset
  const DmaxConstraint = topology === "2sw_fwd" ? 0.50 : topology === "flyback" ? 0.65 : 0.95;
  const DmaxViolation = Dmax > DmaxConstraint;

  // IC signal conditioning: COMP-to-comparator divider (affects modulator gain)
  const selICobj = IC_LIBRARY.find(x => x.id === selectedIC);
  const compDividerRatio = selICobj?.compDividerRatio || 1;
  const compDiodeDrop = selICobj?.compDiodeDrop_V || 0;
  const csOffsetV = (selICobj?.csOffset_mV || 0) * 1e-3;
  // compGain = 1/dividerRatio — small-signal gain from COMP to PWM comparator
  // For gm_ps mode, signal conditioning is absorbed into gm characterization
  const compGain = plantMode === "gmps" ? 1 : 1 / Math.max(compDividerRatio, 0.01);

  // ------ EA params object --------------------------------------------------------------------------
  const eaParams = useMemo(() => ({
    type: eaType,
    Aol_dB: eaAol, GBW_MHz: eaGBW, PM_ea_deg: eaPM,
    gm_uAV: eaGm, Rout_MOhm: eaRout, Cout_pF: eaCout,
  }), [eaType, eaAol, eaGBW, eaPM, eaGm, eaRout, eaCout]);
  const eaInfo = useMemo(() => getEAInfo(eaParams), [eaParams]);

  // Calc & freeze comp (uses vinNom)
  const calcComp = useCallback(() => {
    const fsw_hz = fsw * 1e3;
    const eff = getCapBankEffective(capBank);
    const pp = { vin: vinEffNom, vout, iout, fsw_hz, L: L*1e-6, cout: eff.Ceff, esr: eff.ESReff, ri: ri_eff, se: se*1e-3/1e-6, vref, capBank, placement: sensePlacement, senseParams, plantMode, gm_ps: gmps, sc_aus: scEnabled ? scAus : 0, sc_aus_he: scAus, topology, n, optoGain, fp_opto, compGain, lmAffectsSn, Lm_H: xfmrLm * 1e-6, Np: xfmrNp, Ns: xfmrNs, auxSecondaries };
    const pinfo = getPlantInfo(pp);
    if (compType === "type3") {
      const c = autoPlaceType3(pinfo, fcTarget * 1e3, fsw_hz, pp);
      setFrozenComp(c);
      setManFz1(parseFloat(c.fz1.toFixed(4)));
      setManFz2(parseFloat(c.fz2.toFixed(4)));
      setManFp1(parseFloat(c.fp1.toFixed(4)));
      setManFp2(parseFloat(c.fp2.toFixed(4)));
      setManFi3(parseFloat(c.fi.toFixed(4)));
    } else {
      const c = autoPlace(pinfo, fcTarget * 1e3, fsw_hz, pp);
      setFrozenComp(c);
      setManFzC(parseFloat(c.fz_c.toFixed(4)));
      setManFpC(parseFloat(c.fp_c.toFixed(4)));
      setManFi(parseFloat(c.fi.toFixed(4)));
    }
  }, [vinNom, vout, iout, fsw, L, capBank, ri_eff, se, vref, fcTarget, compType, sensePlacement, senseParams, plantMode, gmps, scAus, scEnabled, topology, n, optoGain, fp_opto, compGain, lmAffectsSn, xfmrLm, xfmrNp, xfmrNs, auxSecondaries]);

  useEffect(() => { if (!frozenComp) calcComp(); }, [frozenComp, calcComp]);
  // Re-calculate when comp type changes
  useEffect(() => { calcComp(); }, [compType]); // eslint-disable-line

  const handleRecalc = () => { calcComp(); setCompMode("auto"); };
  const handleManual = () => {
    setCompMode("manual");
    if (frozenComp && frozenComp.type === "type2") {
      setManFzC(frozenComp.fz_c); setManFpC(frozenComp.fp_c); setManFi(frozenComp.fi);
    } else if (frozenComp && frozenComp.type === "type3") {
      setManFz1(frozenComp.fz1); setManFz2(frozenComp.fz2);
      setManFp1(frozenComp.fp1); setManFp2(frozenComp.fp2); setManFi3(frozenComp.fi);
    }
  };
  const handleApplyManual = () => {
    if (compType === "type3") {
      setFrozenComp({ type: "type3", fz1: manFz1, fz2: manFz2, fp1: manFp1, fp2: manFp2, fi: manFi3 });
    } else {
      setFrozenComp({ type: "type2", fz_c: manFzC, fp_c: manFpC, fi: manFi });
    }
  };

  // ------ Phase 8.5: WASM NGspice engine loader -------------------------------------------------
  useEffect(() => {
    // Polyfill: artifact sandbox blocks fetch() on data: URLs.
    // eecircuit-engine embeds WASM as data:application/wasm;base64,...
    const originalFetch = window.fetch.bind(window);
    if (!window._dataUrlPolyfilled) {
      window._dataUrlPolyfilled = true;
      window.fetch = function(url, options) {
        if (typeof url === "string" && url.startsWith("data:")) {
          try {
            const commaIdx = url.indexOf(",");
            if (commaIdx === -1) return Promise.reject(new Error("Malformed data URL"));
            const header = url.substring(0, commaIdx);
            const body = url.substring(commaIdx + 1);
            const isBase64 = header.includes(";base64");
            const mime = (header.match(/^data:([^;,]+)/) || [])[1] || "application/octet-stream";
            let bytes;
            if (isBase64) {
              const binary = atob(body);
              bytes = new Uint8Array(binary.length);
              for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            } else {
              bytes = new TextEncoder().encode(decodeURIComponent(body));
            }
            return Promise.resolve(new Response(bytes.buffer, {
              status: 200, statusText: "OK", headers: { "Content-Type": mime },
            }));
          } catch (e) { return Promise.reject(e); }
        }
        return originalFetch(url, options);
      };
    }
    // Load engine script from CDN
    setNgspiceLoading(true);
    const script = document.createElement("script");
    script.src = "https://cdn.jsdelivr.net/npm/eecircuit-engine@1.6.0/dist/eecircuit-engine.umd.js";
    script.onload = async () => {
      try {
        const engine = window["EEcircuit-engine"];
        if (!engine || !engine.Simulation) { setNgspiceError("Engine class not found"); setNgspiceLoading(false); return; }
        const sim = new engine.Simulation();
        await sim.start();
        ngspiceRef.current = sim;
        setNgspiceReady(true);
        setNgspiceLoading(false);
      } catch (e) { setNgspiceError("WASM init: " + e.message); setNgspiceLoading(false); }
    };
    script.onerror = () => { setNgspiceError("CDN load failed"); setNgspiceLoading(false); };
    document.body.appendChild(script);
  }, []);

  const activeComp = useMemo(() => {
    if (compMode === "manual") {
      if (compType === "type3") return { type: "type3", fz1: manFz1, fz2: manFz2, fp1: manFp1, fp2: manFp2, fi: manFi3 };
      return { type: "type2", fz_c: manFzC, fp_c: manFpC, fi: manFi };
    }
    if (frozenComp) return frozenComp;
    return { type: "type2", fz_c: 100, fp_c: 30000, fi: 1000 };
  }, [compMode, compType, frozenComp, manFzC, manFpC, manFi, manFz1, manFz2, manFp1, manFp2, manFi3]);

  // ------ Main analysis --------------------------------------------------------------------------------
  const results = useMemo(() => {
    const tf = TEMP_FACTORS[tempCorner];
    const fsw_hz = fsw * 1e3;
    const L_h = L * 1e-6 * tf.ind;
    const se_vs = se * 1e-3 / 1e-6;
    // Apply per-type temperature derating to cap bank
    const capBankDerated = capBank.map(b => {
      const cd = getCapDerate(b.type, tempCorner);
      return { ...b, cap_F: b.cap_F * cd.cap, esr_ohm: b.esr_ohm * cd.esr };
    });
    const eff = getCapBankEffective(capBankDerated);
    const pp = { vin: vinEffActive, vout, iout, fsw_hz, L: L_h, cout: eff.Ceff, esr: eff.ESReff, ri: ri_eff, se: se_vs, vref, capBank: capBankDerated, placement: sensePlacement, senseParams, plantMode, gm_ps: gmps, sc_aus: scEnabled ? scAus : 0, sc_aus_he: scAus, topology, n, optoGain, fp_opto, compGain, lmAffectsSn, Lm_H: xfmrLm * 1e-6, Np: xfmrNp, Ns: xfmrNs, auxSecondaries };
    const pinfo = getPlantInfo(pp);
    const H_dc = evalFeedback(vref, vout) * optoGain;
    const freqs = logspace(1, 2e6, 500);
    const bodeData = [];
    let crossoverFreq = 0, phaseAtCrossover = null, gainAt180 = null, prevG = null;
    let prevLoopPhUnwrap = null, foundCrossover = false;
    // Sub-block scalar values
    const Fm_val = getFm(pp);
    const Fm_dB = dB(Fm_val);
    // Sense chain info
    const sInfo = getSenseInfo(senseParams, sensePlacement, iout, vinEffActive, vout, L_h, fsw_hz);
    for (let i = 0; i < freqs.length; i++) {
      const f = freqs[i];
      const Gp = evalPlant(f, pp);
      const Gc_ideal = evalComp(f, activeComp);
      const Gc = evalCompWithEA(f, activeComp, eaParams);
      const Gd = evalDelay(f, csDelay);
      const Gea = evalEA(f, eaParams);
      // Frequency-dependent feedback: H(f) = H_dc / (1 + jf/fp_opto)
      const Hf = evalOptoH(f, H_dc, fp_opto);
      // Note: Kcs(s) is inside Gp via the inner loop closure Ti = Fm·Gid·Kcs
      // compGain scales the plant by 1/dividerRatio for ICs with internal signal conditioning
      const T = cmul(cmul(cmul(Gc, cscale(Gp, compGain)), Gd), Hf);
      const loopMag = dB(cmag(T));
      let loopPhase = cphase(T);
      // Sub-blocks (only meaningful in CCM)
      const isCCM = iout > getIoCritical(pp.vin, pp.vout, pp.L, pp.fsw_hz);
      const gid = isCCM ? evalGid(f, pp) : C(0,0);
      const gvi = isCCM ? evalGvi(f, pp) : C(0,0);
      const he = isCCM ? evalHe(f, pp) : C(1,0);
      const ti = isCCM ? evalTi(f, pp) : C(0,0);
      const gvc_ridley = isCCM ? evalGvcRidley(f, pp) : C(0,0);
      // Pure voltage-mode plant (Fm·Gvd, no current feedback at all)
      const gvd = evalGvd(f, pp);
      const gvc_vm = cscale(gvd, Fm_val);

      // Unwrap loop phase for crossover/GM detection
      let loopPhUnwrap = loopPhase;
      if (prevLoopPhUnwrap !== null) {
        while (loopPhUnwrap - prevLoopPhUnwrap > 180) loopPhUnwrap -= 360;
        while (loopPhUnwrap - prevLoopPhUnwrap < -180) loopPhUnwrap += 360;
      }

      bodeData.push({
        f,
        plantMag: dB(cmag(Gp)), plantPhase: cphase(Gp),
        compMag: dB(cmag(Gc)), compPhase: cphase(Gc),
        compIdealMag: eaParams.type!=="ideal" ? dB(cmag(Gc_ideal)) : undefined,
        compIdealPhase: eaParams.type!=="ideal" ? cphase(Gc_ideal) : undefined,
        eaMag: eaParams.type!=="ideal" ? dB(cmag(Gea)) : undefined,
        eaPhase: eaParams.type!=="ideal" ? cphase(Gea) : undefined,
        loopMag, loopPhase,
        // Sub-block magnitudes
        fmMag: Fm_dB,
        gidMag: dB(cmag(gid)), gidPhase: cphase(gid),
        gviMag: dB(cmag(gvi)), gviPhase: cphase(gvi),
        heMag: dB(cmag(he)), hePhase: cphase(he),
        tiMag: dB(cmag(ti)), tiPhase: cphase(ti),
        gvcClMag: isCCM ? dB(cmag(gvc_ridley)) : undefined,
        gvcClPhase: isCCM ? cphase(gvc_ridley) : undefined,
        vmMag: dB(cmag(gvc_vm)),
        vmPhase: cphase(gvc_vm),
        // Sense chain (sub-block visualization -- absolute Kcs in dB)
        kcsMag: senseParams.mode !== "simple" ? dB(cmag(evalSenseChain(f, senseParams))) : undefined,
        kcsPhase: senseParams.mode !== "simple" ? cphase(evalSenseChain(f, senseParams)) : undefined,
      });

      // First downward 0dB crossing only
      if (!foundCrossover && prevG !== null && prevG > 0 && loopMag <= 0) {
        foundCrossover = true;
        const frac = prevG / (prevG - loopMag);
        crossoverFreq = freqs[i-1] * (freqs[i] / freqs[i-1]) ** frac;
        // Interpolate unwrapped phase at crossover
        phaseAtCrossover = prevLoopPhUnwrap + frac * (loopPhUnwrap - prevLoopPhUnwrap);
      }
      // Gain at -180deg crossing (using unwrapped phase)
      if (prevLoopPhUnwrap !== null) {
        if (prevLoopPhUnwrap > -180 && loopPhUnwrap <= -180) gainAt180 = loopMag;
      }
      prevG = loopMag;
      prevLoopPhUnwrap = loopPhUnwrap;
    }
    const pm = phaseAtCrossover !== null ? 180 + phaseAtCrossover : null;
    const gm = gainAt180 !== null ? -gainAt180 : null;
    // EA phase loss at crossover = actual phase degradation from EA loading
    let eaPhaseLoss = 0;
    let compUnityGain = null;
    if (eaParams.type !== "ideal" && crossoverFreq > 0) {
      // Actual phase loss = phase(Gc_ideal) - phase(Gc_real) at fc
      const Gc_ideal_fc = evalComp(crossoverFreq, activeComp);
      const Gc_real_fc = evalCompWithEA(crossoverFreq, activeComp, eaParams);
      const phIdeal = cphase(Gc_ideal_fc);
      const phReal = cphase(Gc_real_fc);
      eaPhaseLoss = phIdeal - phReal; // positive = phase lost due to EA
      // Add delay phase loss
      if (csDelay > 0) {
        eaPhaseLoss += 360 * crossoverFreq * csDelay * 1e-9;
      }
      // Find compensator unity-gain frequency (where |Gc_ideal| crosses 0 dB)
      for (let j = 1; j < freqs.length; j++) {
        const g_prev = dB(cmag(evalComp(freqs[j-1], activeComp)));
        const g_curr = dB(cmag(evalComp(freqs[j], activeComp)));
        if (g_prev > 0 && g_curr <= 0) {
          compUnityGain = freqs[j-1] * Math.pow(freqs[j]/freqs[j-1], g_prev/(g_prev - g_curr));
          break;
        }
      }
    }
    const val = validate(crossoverFreq, pm || 0, gm || 999, pinfo, fsw_hz, eaParams, eaPhaseLoss, compUnityGain, csDelay, sInfo, tLEB);
    const tmax = pm && crossoverFreq ? Math.min(10 / (TWO_PI * crossoverFreq), 0.01) : 0.001;
    let inputFilterData = null;
    if (showInputFilter) {
      const zin_mag = converterZin(vinActive, vout, iout);
      inputFilterData = freqs.map(f => ({ f, zout_dB: dB(cmag(evalInputFilterZout(f, lin*1e-6, cin*1e-6, rd))), zin_dB: dB(zin_mag) }));
    }
    // Component calculations
    // For OTA EA (TPS7H4011 etc): COMP pin drives Zcomp = (RCOMP + 1/sCCOMP) || 1/sCHF
    // For Op-amp EA: standard Type-II/III feedback network with R1, R2, C1, C2
    let compComponents;
    const isOTA = eaParams.type === "ota";
    const gmEA_SI = isOTA ? (eaParams.gm_uAV || 1650) * 1e-6 : 0; // A/V
    if (activeComp.type === "type3") {
      // Type-III: always op-amp style (OTA doesn't use Type-III)
      const R1 = 10e3;
      const C2 = 1 / (TWO_PI * activeComp.fi * R1);
      const R2 = 1 / (TWO_PI * activeComp.fz1 * C2);
      const C1 = 1 / (TWO_PI * activeComp.fz2 * R1);
      const C3 = 1 / (TWO_PI * activeComp.fp1 * R2);
      const R3 = 1 / (TWO_PI * activeComp.fp2 * C1);
      compComponents = { type: "type3", topology: "opamp", R1, R2, R3, C1, C2, C3 };
    } else if (isOTA) {
      // OTA Type II (§10.2.2.10, Figure 10-2): RCOMP + CCOMP in series, CHF in parallel
      // fi = gmEA / (2π·CCOMP) → CCOMP = gmEA / (2π·fi)
      // fz = 1 / (2π·RCOMP·CCOMP) → RCOMP = 1 / (2π·fz·CCOMP)
      // fp = 1 / (2π·RCOMP·CHF) → CHF = 1 / (2π·fp·RCOMP)
      const CCOMP = gmEA_SI / (TWO_PI * activeComp.fi);
      const RCOMP = 1 / (TWO_PI * activeComp.fz_c * CCOMP);
      const CHF = 1 / (TWO_PI * activeComp.fp_c * RCOMP);
      compComponents = { type: "type2", topology: "ota", RCOMP, CCOMP, CHF };
    } else {
      // Op-amp Type II: R1/R2/C1/C2 feedback network
      const R1 = 10e3;
      const C2 = 1 / (TWO_PI * activeComp.fi * R1);
      const R2 = 1 / (TWO_PI * activeComp.fz_c * C2);
      const C1 = 1 / (TWO_PI * activeComp.fp_c * R2);
      compComponents = { type: "type2", topology: "opamp", R1, R2, C1, C2 };
    }
    // Phase unwrap
    let pPl=0,pCp=0,pLp=0,pGi=0,pGv=0,pH=0,pTi=0,pCl=0,pVm=0,pEa=0,pCi=0;
    const phaseData = bodeData.map((d,i)=>{
      let pp2=d.plantPhase,cp=d.compPhase,lp=d.loopPhase;
      let gip=d.gidPhase,gvp=d.gviPhase,hp=d.hePhase,tip=d.tiPhase,clp=d.gvcClPhase,vmp=d.vmPhase;
      let eap=d.eaPhase,cip=d.compIdealPhase;
      if(i>0){
        while(pp2-pPl>180)pp2-=360;while(pp2-pPl<-180)pp2+=360;
        while(cp-pCp>180)cp-=360;while(cp-pCp<-180)cp+=360;
        while(lp-pLp>180)lp-=360;while(lp-pLp<-180)lp+=360;
        while(gip-pGi>180)gip-=360;while(gip-pGi<-180)gip+=360;
        while(gvp-pGv>180)gvp-=360;while(gvp-pGv<-180)gvp+=360;
        while(hp-pH>180)hp-=360;while(hp-pH<-180)hp+=360;
        while(tip-pTi>180)tip-=360;while(tip-pTi<-180)tip+=360;
        if(clp!==undefined){while(clp-pCl>180)clp-=360;while(clp-pCl<-180)clp+=360;}
        while(vmp-pVm>180)vmp-=360;while(vmp-pVm<-180)vmp+=360;
        if(eap!==undefined){while(eap-pEa>180)eap-=360;while(eap-pEa<-180)eap+=360;}
        if(cip!==undefined){while(cip-pCi>180)cip-=360;while(cip-pCi<-180)cip+=360;}
      }
      pPl=pp2;pCp=cp;pLp=lp;pGi=gip;pGv=gvp;pH=hp;pTi=tip;if(clp!==undefined)pCl=clp;pVm=vmp;
      if(eap!==undefined)pEa=eap;if(cip!==undefined)pCi=cip;
      return{...d,plantPhase:pp2,compPhase:cp,loopPhase:lp,gidPhase:gip,gviPhase:gvp,hePhase:hp,tiPhase:tip,gvcClPhase:clp,vmPhase:vmp,eaPhase:eap,compIdealPhase:cip};
    });
    // ------ Phase 6: Audio susceptibility data ------------------------------------
    const audioFreqs = logspace(1, 2e6, 400);
    const audioData = audioFreqs.map(f => {
      const zo = evalZout_open(f, pp);
      const zc = evalZout_closed(f, pp, activeComp, eaParams, csDelay);
      const gvg_o = evalGvg_open(f, pp);
      const gvg_c = evalGvg_closed(f, pp, activeComp, eaParams, csDelay);
      const gvg_c_mag = cmag(gvg_c);
      const psrr = gvg_c_mag > 0 ? -dB(gvg_c_mag) : 200;
      return {
        f,
        zo_open_dB: dB(cmag(zo)),
        zo_closed_dB: dB(cmag(zc)),
        gvg_open_dB: dB(cmag(gvg_o)),
        gvg_closed_dB: dB(cmag(gvg_c)),
        psrr_dB: psrr,
      };
    });
    // Zout at DC and at crossover
    const zout_dc = cmag(evalZout_closed(1, pp, activeComp, eaParams, csDelay));
    const zout_fc = crossoverFreq > 0 ? cmag(evalZout_closed(crossoverFreq, pp, activeComp, eaParams, csDelay)) : null;
    const gvg_dc = cmag(evalGvg_closed(1, pp, activeComp, eaParams, csDelay));
    const psrr_dc = gvg_dc > 0 ? -dB(gvg_dc) : 200;

    return { bodeData, phaseData, crossoverFreq, pm, gm, pinfo, val, inputFilterData, compComponents, fsw_hz, tf, Fm_val, Fm_dB, eaPhaseLoss, compUnityGain, sInfo, audioData, zout_dc, zout_fc, psrr_dc };
  }, [vinActive, vout, iout, fsw, L, capBank, ri_eff, se, vref, activeComp, eaParams, csDelay, tempCorner, showInputFilter, lin, cin, rd, sensePlacement, senseParams, plantMode, gmps, scAus, scEnabled, topology, n, optoGain, fp_opto, compGain, lmAffectsSn, xfmrLm, xfmrNp, xfmrNs, auxSecondaries]);

  // ------ Sweep ------------------------------------------------------------------------------------------------
  // ------ Phase 7: Time-domain simulation --------------------------------------
  // Common sim config builder (used by both analytical and SPICE paths)
  const tdCfg = useMemo(() => {
    if (!activeComp || !results.crossoverFreq) return null;
    const tf = TEMP_FACTORS[tempCorner];
    const fsw_hz = fsw * 1e3;
    const L_h = L * 1e-6 * tf.ind;
    const se_vs = se * 1e-3 / 1e-6;
    const capBankDerated = capBank.map(b => {
      const cd = getCapDerate(b.type, tempCorner);
      return { ...b, cap_F: b.cap_F * cd.cap, esr_ohm: b.esr_ohm * cd.esr };
    });
    const eff = getCapBankEffective(capBankDerated);
    const H = evalFeedback(vref, vout) * optoGain;
    let slewSrc = 0, slewSnk = 0;
    const I_src = eaIsrc * 1e-6;
    const I_snk = eaIsnk * 1e-6;
    if (eaParams.type === "ota") {
      const gm = (eaParams.gm_uAV || 1650) * 1e-6;
      const CCOMP = gm / (TWO_PI * Math.max(activeComp.fi || 1000, 1));
      if (CCOMP > 0) { slewSrc = I_src / CCOMP; slewSnk = I_snk / CCOMP; }
    } else if (eaParams.type === "opamp") {
      const R1 = 10e3;
      const C2 = 1 / (TWO_PI * Math.max(activeComp.fi || 1000, 1) * R1);
      if (C2 > 0) { slewSrc = I_src / C2; slewSnk = I_snk / C2; }
    }
    const _pm = results.pm;
    const _fc = results.crossoverFreq;
    const pmR = _pm ? (_pm * Math.PI / 180) : 0.78;
    const z = Math.min(pmR / (Math.PI / 2) * 0.8, 0.99);
    const tSettle_fc = _fc > 0 ? 4 / (z * TWO_PI * _fc) : 200e-6;
    // Also account for integrator wind-up time and plant output pole
    const fi_comp = activeComp ? (activeComp.fi || 1000) : 1000;
    const fp1_plant = results.pinfo?.fp1 || 1000;
    const tSettle_int = 5 / (TWO_PI * Math.min(fi_comp, fp1_plant));
    const tSettle_ss = Math.max(tSettle_fc, tSettle_int);
    // Cap at 10ms to keep sim responsive; clamp minimum at 400µs
    const tTotal_us = Math.min(Math.max(tSettle_ss * 6 * 1e6, 400), 10000);
    const tStart_us = Math.min(tTotal_us * 0.03, 30);
    return {
      vin: vinEffActive, vout_nom: vout, iout, L: L_h, Ceff: eff.Ceff, ESR: eff.ESReff,
      fsw_hz, ri: ri_eff, se_vs, vref, H,
      comp: activeComp, ea: eaParams,
      clampLow: compClampLow, clampHigh: compClampHigh,
      slewSource_Aus: slewSrc, slewSink_Aus: slewSnk,
      plantMode, gm_ps: gmps, sc_aus_he: scAus,
      Dmax: topology === "2sw_fwd" ? 0.50 : topology === "flyback" ? 0.65 : (plantMode === "gmps" ? 0.92 : 0.95),
      stimulus: {
        type: stimType,
        // Line step: user enters ΔVin at primary; secondary sees ΔVin × n
        amplitude: stimType === "load_step" ? deltaI : stimDeltaVin * n,
        riseTime_us: rise1090 ? stimRiseTime / 0.8 : stimRiseTime,
        tStart_us,
      },
      tTotal_us, nPts: 600, topology, n, Lm_H: xfmrLm * 1e-6,
    };
  }, [vinActive, vout, iout, fsw, L, capBank, ri_eff, se, vref, activeComp, eaParams, compClampLow, compClampHigh, tempCorner, plantMode, gmps, scAus, deltaI, stimType, stimDeltaVin, stimRiseTime, rise1090, eaIsrc, eaIsnk, results, topology, n, xfmrLm, optoGain]);

  // Analytical engine (synchronous, runs in useMemo — unchanged behavior)
  const analyticalSim = useMemo(() => {
    if (!tdCfg) return null;
    try { return simTimeDomain(tdCfg); }
    catch (e) { return null; }
  }, [tdCfg]);

  // SPICE engine (async, runs when simEngine==="spice" and params change)
  const spiceCfgRef = useRef(null);
  useEffect(() => {
    if (simEngine !== "spice" || !ngspiceReady || !tdCfg || plantMode !== "gmps") {
      return;
    }
    // Serialize config for comparison to avoid re-running with same params
    const cfgKey = JSON.stringify([
      tdCfg.vin, tdCfg.vout_nom, tdCfg.iout, tdCfg.Ceff, tdCfg.ESR,
      tdCfg.fsw_hz, tdCfg.gm_ps, tdCfg.clampLow, tdCfg.clampHigh,
      tdCfg.comp, tdCfg.stimulus, tdCfg.tTotal_us,
    ]);
    if (spiceCfgRef.current === cfgKey) return;
    spiceCfgRef.current = cfgKey;

    let cancelled = false;
    (async () => {
      setSpiceRunning(true);
      try {
        const sim = ngspiceRef.current;
        // Create fresh engine instance to avoid cached results
        const engine = window["EEcircuit-engine"];
        if (engine && engine.Simulation) {
          const freshSim = new engine.Simulation();
          await freshSim.start();
          ngspiceRef.current = freshSim;
        }
        const { netlist } = generateNGspiceNetlist(tdCfg);
        ngspiceRef.current.setNetList(netlist);
        const t0 = performance.now();
        const res = await ngspiceRef.current.runSim();
        const ms = (performance.now() - t0).toFixed(0);
        if (cancelled) return;
        const parsed = parseNGspiceResults(res, tdCfg);
        if (parsed) {
          setSpiceSim(parsed);
          setSpiceElapsed(ms);
        }
      } catch (e) {
        console.warn("SPICE sim error:", e);
      }
      if (!cancelled) setSpiceRunning(false);
    })();
    return () => { cancelled = true; };
  }, [simEngine, ngspiceReady, tdCfg, plantMode]);

  // Select active engine result
  const tdSim = (simEngine === "spice" && spiceSim && plantMode === "gmps") ? spiceSim : analyticalSim;

  const sweepData = useMemo(() => {
    // Skip heavy sweep computation on setup page
    // Sweep data always computed (single-page layout)
    const tf = TEMP_FACTORS[tempCorner];
    const fsw_hz = fsw*1e3;
    const se_vs = se*1e-3/1e-6;
    const capBankDerated = capBank.map(b => { const cd = getCapDerate(b.type, tempCorner); return { ...b, cap_F: b.cap_F*cd.cap, esr_ohm: b.esr_ohm*cd.esr }; });
    // Line sweep uses actual Vin operating range
    const lineData = [];
    let vinCrit = undefined;
    let hasUnstableRegion = false;
    const nPts = 50;
    for (let i=0;i<=nPts;i++) {
      const v = vinMin+(vinMax-vinMin)*i/nPts;
      const vEff = v * n; // effective Vin (secondary-referred)
      const r = analyzeLoop(vEff,vout,iout,fsw_hz,L*1e-6*tf.ind,capBankDerated,ri_eff,se_vs,vref,activeComp,eaParams,csDelay,sensePlacement,senseParams,plantMode,gmps,scEnabled?scAus:0,scAus,optoGain,fp_opto,{topology,n,Lm_H:xfmrLm*1e-6,Np:xfmrNp,Ns:xfmrNs,lmAffectsSn,auxSecondaries,compGain});
      const D = vout / vEff;
      if (!r.subharmStable) hasUnstableRegion = true;
      if (r.subharmStable && vinCrit === undefined) vinCrit = v;
      lineData.push({
        vin:+v.toFixed(2),
        fc_kHz: r.subharmStable ? r.fc/1e3 : undefined,
        pm: (r.subharmStable && r.pm != null) ? r.pm : undefined,
        gm: (r.subharmStable && r.gm != null) ? r.gm : undefined,
        D: D*100,
        factor: r.factor,
        stable: r.subharmStable,
      });
    }
    // Load sweep uses vinActive (selected corner)
    const iMin=0.1, iMax=Math.max(iout*2,1);
    const loadSweepData = [];
    for (let i=0;i<=nPts;i++) {
      const io = iMin+(iMax-iMin)*i/nPts;
      const r = analyzeLoop(vinEffActive,vout,io,fsw_hz,L*1e-6*tf.ind,capBankDerated,ri_eff,se_vs,vref,activeComp,eaParams,csDelay,sensePlacement,senseParams,plantMode,gmps,scEnabled?scAus:0,scAus,optoGain,fp_opto,{topology,n,Lm_H:xfmrLm*1e-6,Np:xfmrNp,Ns:xfmrNs,lmAffectsSn,auxSecondaries,compGain});
      loadSweepData.push({
        iout:+io.toFixed(2),
        fc_kHz: (r.subharmStable && r.fc) ? r.fc/1e3 : undefined,
        pm: (r.subharmStable && r.pm != null) ? r.pm : undefined,
        gm: (r.subharmStable && r.gm != null) ? r.gm : undefined,
        stable: r.subharmStable,
        factor: r.factor,
      });
    }
    return { lineData, loadSweepData, vinCrit, hasUnstableRegion, vinMinPlot: lineData[0]?.vin };
  }, [vinMin,vinMax,vinActive,vout,iout,fsw,L,capBank,ri_eff,se,vref,activeComp,eaParams,csDelay,tempCorner,sensePlacement,senseParams,plantMode,gmps,scAus,topology,n,optoGain,fp_opto,lmAffectsSn,xfmrLm,xfmrNp,xfmrNs,auxSecondaries]);

  // ------ Cap bank impedance data ------------------------------------------------------------
  const zcapData = useMemo(() => {
    // Zcap always computed
    const freqs = logspace(100, 5e7, 300);
    const rload = vout / Math.max(iout, 0.001);
    return freqs.map(f => {
      const pt = { f, rload_dB: dB(rload) };
      pt.bank_dB = dB(cmag(evalZcapBank(f, capBank)));
      capBank.forEach((b, i) => {
        if (b.qty > 0 && b.cap_F > 0) {
          const z = evalZcapSingle(f, b.cap_F * b.qty, b.esr_ohm / b.qty, b.esl_H / b.qty);
          pt[`cap${i}_dB`] = dB(cmag(z));
        }
      });
      return pt;
    });
  }, [capBank, vout, iout, view]);

  const { bodeData, phaseData, crossoverFreq, pm, gm, pinfo, val, inputFilterData, compComponents, Fm_val, Fm_dB, eaPhaseLoss, compUnityGain, sInfo, audioData, zout_dc, zout_fc, psrr_dc } = results;
  const pmS = pm===null?"err":pm<30?"err":pm<45?"warn":"ok";
  const gmS = gm===null?"ok":gm<6?"err":gm<10?"warn":"ok"; // null GM = phase never hits -180deg = infinite GM = good
  const fcRatio = crossoverFreq/(fsw*1e3);
  const fcTargetMiss = crossoverFreq > 0 && fcTarget > 0 ? Math.abs(crossoverFreq - fcTarget*1e3) / (fcTarget*1e3) : 0;
  const fcS = crossoverFreq <= 0 ? "err" : fcRatio>0.201?"err":fcRatio>0.101?"warn":fcTargetMiss>0.5?"warn":"ok";

  // ─── Live Logging Effects ─────────────────────────────────
  // Log input parameter changes
  useEffect(() => {
    addLog("INPUT", `Topology=${topology} Vin=${vinMin}-${vinMax}V Vout=${vout}V Iout=${iout}A fsw=${fsw}kHz${isFlyback?"":` L=${L}µH`}`);
    if (isIsolated) addLog("XFMR", `Np=${xfmrNp} Ns=${xfmrNs} n=${sf(turnsRatio,4)} Lm=${xfmrLm}µH Vin_eff=${sf(vinEffMin,1)}-${sf(vinEffMax,1)}V${isFlyback?" [flyback]":""}`);
  }, [topology, vinMin, vinMax, vout, iout, fsw, L, xfmrNp, xfmrNs, xfmrLm]);
  // Log sense config changes
  useEffect(() => {
    const scInfo = plantMode === "gmps" ? `SC=${scAus}A/µs${scEnabled?" [applied]":" [He only]"}` : `Se=${se}mV/µs`;
    addLog("SENSE", `Mode=${senseMode} Ri=${sf(ri_eff,4)}V/A${isIsolated?` side=${isoSenseSide}`:""} ${scInfo} plant=${plantMode}${lmAffectsSn?" [Lm→Sn]":""}`);
  }, [senseMode, ri_eff, isoSenseSide, se, lmAffectsSn, plantMode, scAus, scEnabled]);
  // Log computed plant info
  useEffect(() => {
    if (!pinfo) return;
    const parts = [
      `${plantMode==="gmps"?"gm_ps":"std"} D=${sf(pinfo.D*100,1)}% D'=${sf(pinfo.Dprime*100,1)}% ${pinfo.mode}`,
      `mc=${sf(pinfo.mc,3)} Qp=${sf(pinfo.Qp,2)} factor=${sf(pinfo.factor,3)}`,
      `Gvc0=${sf(pinfo.Gvc0_dB,1)}dB fp1=${fmtFreq(pinfo.fp1)} fz_ESR=${fmtFreq(pinfo.fz_esr)}`,
    ];
    if (pinfo.fz_rhp) parts.push(`RHPZ=${fmtFreq(pinfo.fz_rhp)} fc_limit=${fmtFreq(pinfo.fz_rhp/5)}`);
    if (pinfo.sn_mag > 0) parts.push(`Sn(Lm)=${sf(pinfo.sn_mag,0)}A/s (${sf(pinfo.sn_mag/Math.max(pinfo.sn_inductor,1)*100,0)}% equiv SC)`);
    addLog("PLANT", parts.join(" | "));
  }, [pinfo?.D, pinfo?.mc, pinfo?.Qp, pinfo?.fz_rhp, pinfo?.mode, pinfo?.Gvc0_dB, plantMode]);
  // Log loop results
  useEffect(() => {
    if (!crossoverFreq && !pm) return;
    const parts = [];
    if (crossoverFreq > 0) parts.push(`fc=${fmtFreq(crossoverFreq)} (${sf(fcRatio*100,1)}% of fsw)`);
    if (pm !== null) parts.push(`PM=${sf(pm,1)}°`);
    if (gm !== null) parts.push(`GM=${sf(gm,1)}dB`);
    if (zout_dc !== undefined) parts.push(`Zout(DC)=${pm!==null&&pm<0?"N/A(unstable)":fmtSI(zout_dc,"R")}`);
    if (psrr_dc !== undefined) parts.push(`PSRR=${sf(psrr_dc,1)}dB`);
    if (parts.length > 0) addLog("LOOP", parts.join(" | "));
  }, [crossoverFreq, pm, gm, zout_dc, psrr_dc]);
  // Log comp changes
  useEffect(() => {
    if (!activeComp) return;
    if (activeComp.type === "type2") addLog("COMP", `Type-II: fz=${fmtFreq(activeComp.fz_c)} fp=${fmtFreq(activeComp.fp_c)} fi=${fmtFreq(activeComp.fi)} target_fc=${fcTarget}kHz`);
    else if (activeComp.type === "type3") addLog("COMP", `Type-III: fz1=${fmtFreq(activeComp.fz1)} fz2=${fmtFreq(activeComp.fz2)} fp1=${fmtFreq(activeComp.fp1)} fp2=${fmtFreq(activeComp.fp2)} fi=${fmtFreq(activeComp.fi)}`);
  }, [activeComp?.fi, activeComp?.fz_c, activeComp?.fp_c, activeComp?.fz1, activeComp?.type]);
  // Log opto changes
  useEffect(() => {
    if (!isIsolated) return;
    addLog("OPTO", fbMode==="primary" ? `Primary-side FB: H_dc=Vref/Vout=${sf(vref/vout,4)} (no opto pole)` : `G₀=${sf(optoGain,2)} (CTR=${optoCTR} Rpu=${optoRpullup}kΩ Rled=${optoRled}kΩ) fp_opto=${fp_opto>0?fmtFreq(fp_opto):"∞"} H_dc=${sf(vref/vout*optoGain,4)}`);
  }, [optoCTR, optoRpullup, optoRled, optoCopto, optoGain, fp_opto, isIsolated, fbMode]);
  // Log IC selection
  useEffect(() => {
    const ic = IC_LIBRARY.find(x=>x.id===selectedIC);
    if (ic && ic.id !== "custom") addLog("IC", `${ic.name} (${ic.mfg}) Vref=${ic.vref}V Dmax=${((ic.Dmax||1)*100).toFixed(0)}% ${ic.ea==="ota"?"OTA":"OpAmp"}`);
  }, [selectedIC]);
  // Auto-scroll log
  useEffect(() => { if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight; }, [logEntries]);

  const MB = ({label,value,sub,status}) => (
    <div style={{background:col.panel,border:`1px solid ${status==="err"?col.err:status==="warn"?col.warn:col.border}`,borderRadius:5,padding:"8px 11px",minWidth:115,textAlign:"center"}}>
      <div style={{fontSize:10,color:col.dim,marginBottom:2,textTransform:"uppercase",letterSpacing:"0.06em"}}>{label}</div>
      <div style={{fontSize:19,fontWeight:700,color:status==="err"?col.err:status==="warn"?col.warn:col.ok,fontFamily:"monospace"}}>{value}</div>
      <div style={{fontSize:9.5,color:col.dim}}>{sub}</div>
    </div>
  );

  const TT=({active,payload})=>{
    if(!active||!payload?.length)return null;
    const d=payload[0]?.payload;if(!d)return null;
    return(<div style={{background:"#151e2bee",border:`1px solid ${col.border}`,borderRadius:4,padding:"5px 9px",fontSize:11,color:col.text,fontFamily:"monospace"}}>
      <div style={{marginBottom:2,color:col.bright}}>{d.f?`f = ${fmtFreq(d.f)}`:""}</div>
      {d.plantMag!==undefined&&showPlant&&<div style={{color:col.plant}}>Plant: {d.plantMag?.toFixed(1)} dB</div>}
      {d.compMag!==undefined&&showComp&&<div style={{color:col.comp}}>Comp: {d.compMag?.toFixed(1)} dB</div>}
      {d.loopMag!==undefined&&showLoop&&<div style={{color:col.loop}}>Loop: {d.loopMag?.toFixed(1)} dB</div>}
      {showSubBlocks&&plantMode!=="gmps"&&d.tiMag!==undefined&&<>
        <div style={{borderTop:"1px solid #1c2736",marginTop:3,paddingTop:3,color:"#ec4899"}}>Ti: {d.tiMag?.toFixed(1)} dB</div>
        <div style={{color:"#38bdf8"}}>Gid: {d.gidMag?.toFixed(1)} dB</div>
        <div style={{color:"#fb923c"}}>Gvi: {d.gviMag?.toFixed(1)} dB</div>
        <div style={{color:"#94a3b8"}}>He: {d.heMag?.toFixed(1)} dB</div>
        {d.kcsMag!==undefined&&<div style={{color:"#facc15"}}>Kcs: {d.kcsMag?.toFixed(1)} dB</div>}
        <div style={{color:"#ef4444"}}>Ridley: {d.gvcClMag?.toFixed(1)} dB</div>
        <div style={{color:"#4ade80"}}>Fm·Gvd: {d.vmMag?.toFixed(1)} dB</div>
      </>}
      {d.eaMag!==undefined&&<>
        <div style={{borderTop:"1px solid #1c2736",marginTop:3,paddingTop:3,color:"#e879f9"}}>EA(OL): {d.eaMag?.toFixed(1)} dB</div>
        {d.compIdealMag!==undefined&&<div style={{color:col.comp,opacity:0.5}}>Gc(ideal): {d.compIdealMag?.toFixed(1)} dB</div>}
      </>}
    </div>);
  };
  const TT_ph=({active,payload})=>{
    if(!active||!payload?.length)return null;
    const d=payload[0]?.payload;if(!d)return null;
    return(<div style={{background:"#151e2bee",border:`1px solid ${col.border}`,borderRadius:4,padding:"5px 9px",fontSize:11,color:col.text,fontFamily:"monospace"}}>
      <div style={{marginBottom:2,color:col.bright}}>{d.f?`f = ${fmtFreq(d.f)}`:""}</div>
      {d.plantPhase!==undefined&&showPlant&&<div style={{color:col.plant}}>Plant: {d.plantPhase?.toFixed(1)}°</div>}
      {d.compPhase!==undefined&&showComp&&<div style={{color:col.comp}}>Comp: {d.compPhase?.toFixed(1)}°</div>}
      {d.loopPhase!==undefined&&showLoop&&<div style={{color:col.loop}}>Loop: {d.loopPhase?.toFixed(1)}°</div>}
      {showSubBlocks&&plantMode!=="gmps"&&d.tiPhase!==undefined&&<>
        <div style={{borderTop:"1px solid #1c2736",marginTop:3,paddingTop:3,color:"#ec4899"}}>Ti: {d.tiPhase?.toFixed(1)}°</div>
        <div style={{color:"#38bdf8"}}>Gid: {d.gidPhase?.toFixed(1)}°</div>
        <div style={{color:"#fb923c"}}>Gvi: {d.gviPhase?.toFixed(1)}°</div>
        <div style={{color:"#94a3b8"}}>He: {d.hePhase?.toFixed(1)}°</div>
      </>}
      {d.eaPhase!==undefined&&<>
        <div style={{borderTop:"1px solid #1c2736",marginTop:3,paddingTop:3,color:"#e879f9"}}>EA(OL): {d.eaPhase?.toFixed(1)}°</div>
        {d.compIdealPhase!==undefined&&<div style={{color:col.comp,opacity:0.5}}>Gc(ideal): {d.compIdealPhase?.toFixed(1)}°</div>}
      </>}
    </div>);
  };

  const tabs = [
    {id:"bode",label:"BODE"},{id:"step",label:"TRANSIENT"},{id:"sweep",label:"SWEEP"},
    {id:"zcap",label:"Zcap"},{id:"audio",label:"AUDIO"},
    ...(showInputFilter?[{id:"filter",label:"INPUT FILTER"}]:[]),
    {id:"diag",label:"DIAGNOSTICS"},{id:"eqns",label:"EQUATIONS"},
  ];

  const SmBtn = ({label,active,onClick}) => (
    <button onClick={onClick} style={{
      background:active?col.accent:"transparent",color:active?"#fff":col.dim,
      border:`1px solid ${active?col.accent:col.border}`,borderRadius:3,
      padding:"2px 8px",fontSize:10,cursor:"pointer",fontFamily:"inherit",fontWeight:600,
    }}>{label}</button>
  );

  return (
    <div style={{background:col.bg,color:col.text,minHeight:"100vh",fontFamily:"'IBM Plex Sans',sans-serif",display:"flex",flexDirection:"column"}}>
      {/* Header */}
      <div style={{background:col.panel,borderBottom:`1px solid ${col.border}`,padding:"8px 16px",display:"flex",alignItems:"center",gap:12,flexShrink:0,flexWrap:"wrap"}}>
        <div style={{width:8,height:8,borderRadius:"50%",background:val.errors.length>0?col.err:val.warnings.length>0?col.warn:col.ok}} />
        <span style={{fontSize:14,fontWeight:700,color:col.bright,letterSpacing:"0.06em"}}>{topology==="2sw_fwd"?"2SW FORWARD":topology==="flyback"?"FLYBACK":"BUCK"} PEAK CURRENT-MODE</span>
        <span style={{fontSize:10,color:col.dim}}>CONTROL LOOP ANALYZER</span>
        <div style={{marginLeft:"auto",display:"flex",gap:12,alignItems:"center"}}>
          <div style={{display:"flex",alignItems:"center",gap:4}}>
            <span style={{fontSize:10,color:col.dim,fontWeight:600}}>Vin:</span>
            {[{k:"min",l:`${vinMin}V`},{k:"nom",l:`${vinNom.toFixed(0)}V`},{k:"max",l:`${vinMax}V`}].map(v=>
              <SmBtn key={v.k} label={v.l} active={vinCorner===v.k} onClick={()=>setVinCorner(v.k)} />
            )}
          </div>
          <div style={{display:"flex",alignItems:"center",gap:4}}>
            <span style={{fontSize:10,color:col.dim,fontWeight:600}}>Temp:</span>
            {["nominal","cold","hot"].map(t=><SmBtn key={t} label={TEMP_FACTORS[t].label} active={tempCorner===t} onClick={()=>setTempCorner(t)} />)}
          </div>
        </div>
      </div>

      {/* ═══════════ SINGLE-PAGE LAYOUT ═══════════ */}
      <div style={{display:"flex",flex:1,overflow:"hidden"}}>
        {/* ─── LEFT PANEL: Cards ─── */}
        <div style={{width:300,background:col.panel,borderRight:`1px solid ${col.border}`,overflowY:"auto",flexShrink:0,display:"flex",flexDirection:"column"}}>
          {/* Toggle bar */}
          <div style={{padding:"6px 8px",borderBottom:`1px solid ${col.border}`,display:"flex",flexWrap:"wrap",gap:2}}>
            {[
              {k:"topo",l:"TOPO"},{k:"ic",l:"IC"},{k:"xfmr",l:"XFMR",show:isIsolated},{k:"pstage",l:"PWR"},
              {k:"caps",l:"CAPS"},{k:"sense",l:"SENSE"},{k:"slope",l:"SLOPE"},
              {k:"opto",l:"FB",show:isIsolated},{k:"ea",l:"EA"},{k:"comp",l:"COMP"},
            ].filter(x=>x.show!==false).map(x=>(
              <button key={x.k} onClick={()=>toggleCard(x.k)} style={{
                background:cardVis[x.k]?col.accent+"33":"transparent",
                color:cardVis[x.k]?col.accent:col.dim,
                border:`1px solid ${cardVis[x.k]?col.accent:col.border}`,borderRadius:3,
                padding:"2px 6px",fontSize:9,cursor:"pointer",fontWeight:700,fontFamily:"monospace",letterSpacing:"0.04em",
              }}>{x.l}</button>
            ))}
          </div>
          {/* Warnings */}
          <div style={{padding:"6px 10px 0"}}>
            {val.errors.length > 0 && <div style={{background:"#1c0f0f",border:`1px solid ${col.err}`,borderRadius:4,padding:"5px 8px",marginBottom:6}}>
              {val.errors.map((e,i) => <div key={i} style={{fontSize:10,color:"#fca5a5",marginBottom:1}}>❌ {e}</div>)}
            </div>}
            {val.warnings.length > 0 && <div style={{background:"#1c1a0f",border:`1px solid ${col.warn}`,borderRadius:4,padding:"5px 8px",marginBottom:6}}>
              {val.warnings.map((w,i) => <div key={i} style={{fontSize:10,color:"#fde68a",marginBottom:1}}>⚠ {w}</div>)}
            </div>}
          </div>
          {/* Cards */}
          <div style={{flex:1,overflowY:"auto",padding:"6px 10px 10px"}}>
          {(()=>{
            const card = {background:col.bg,border:`1px solid ${col.border}`,borderRadius:5,padding:"10px 12px",marginBottom:8};
            const cardTitle = {...sSection,marginTop:0};
            const selIC = selectedIC !== "custom" ? IC_LIBRARY.find(x=>x.id===selectedIC) : null;
            return (<>

                {/* Topology */}
                {cardVis.topo && <div style={card}>
                  <div style={cardTitle}>TOPOLOGY</div>
                  <div style={{display:"flex",gap:3,marginBottom:6}}>
                    <SmBtn label="BUCK" active={topology==="buck"} onClick={()=>setTopology("buck")} />
                    <SmBtn label="2SW FWD" active={topology==="2sw_fwd"} onClick={()=>setTopology("2sw_fwd")} />
                    <SmBtn label="FLYBACK" active={topology==="flyback"} onClick={()=>setTopology("flyback")} />
                    <SmBtn label="BOOST" active={false} onClick={()=>{}} />
                  </div>
                  <div style={{fontSize:10,color:col.dim,lineHeight:1.5}}>
                    {topology==="buck" && "Non-isolated synchronous buck. Peak current-mode control."}
                    {topology==="2sw_fwd" && "Two-switch forward converter. Transformer-isolated buck-derived topology. D ≤ 50%. No reset winding — magnetizing current resets via body diodes."}
                  </div>
                  {DmaxViolation && <div style={{fontSize:10,color:col.err,marginTop:4,fontWeight:600}}>
                    ⚠ D(max) = {sf(Dmax*100,1)}% exceeds 50% limit. Increase turns ratio (Ns/Np) or reduce Vout.
                  </div>}
                </div>}

                {/* Controller IC */}
                {cardVis.ic && <div style={card}>
                  <div style={cardTitle}>CONTROLLER IC</div>
                  <select value={selectedIC} onChange={e=>applyIC(e.target.value)}
                    style={{width:"100%",background:col.bg,color:col.bright,border:`1px solid ${col.border}`,borderRadius:3,padding:"5px 6px",fontSize:11,marginBottom:4,fontFamily:"'JetBrains Mono',monospace"}}>
                    {IC_LIBRARY.filter(ic => {
                      if (ic.id === "custom" || ic.id === selectedIC) return true;
                      return !ic.supportedTopologies || ic.supportedTopologies.includes(topology);
                    }).map(ic=>(
                      <option key={ic.id} value={ic.id}>{ic.name} -- {ic.desc}</option>
                    ))}
                  </select>
                  {selIC && <>
                    <div style={{fontSize:10,color:col.dim,fontFamily:"monospace",lineHeight:1.5,marginBottom:4}}>
                      {selIC.mfg} | Vref={selIC.vref}V | Dmax={((selIC.Dmax||1)*100).toFixed(0)}%
                      {selIC.fsw_max_kHz ? ` | fsw≤${selIC.fsw_max_kHz}kHz` : ""}
                      {selIC.ea==="ota"?` | OTA gm=${selIC.gm_uAV}µA/V`:` | Op-amp Aol=${selIC.Aol_dB}dB`}
                    </div>
                    {selIC.notes && <div style={{fontSize:9.5,color:col.dim,marginBottom:4,lineHeight:1.4}}>{selIC.notes}</div>}
                    {(selIC.compDividerRatio > 1 || selIC.compDiodeDrop_V > 0 || selIC.csOffset_mV > 0) && (
                      <div style={{fontSize:9.5,color:"#c084fc",background:"#1a0f2e",border:"1px solid #7c3aed44",borderRadius:3,padding:"4px 6px",marginBottom:4,lineHeight:1.5,fontFamily:"monospace"}}>
                        <span style={{fontWeight:700}}>Signal Conditioning:</span><br/>
                        {selIC.compDiodeDrop_V > 0 && <>Diode drop: {selIC.compDiodeDrop_V}V<br/></>}
                        {selIC.compDividerRatio > 1 && <>Internal divider: 1/{selIC.compDividerRatio}<br/></>}
                        {selIC.csOffset_mV > 0 && <>CS offset: +{selIC.csOffset_mV}mV<br/></>}
                        CS threshold = {selIC.compDiodeDrop_V > 0 ? `(VCOMP−${selIC.compDiodeDrop_V}V)` : "VCOMP"}{selIC.compDividerRatio > 1 ? `/${selIC.compDividerRatio}` : ""}{selIC.csOffset_mV > 0 ? ` − ${selIC.csOffset_mV}mV` : ""}<br/>
                        Small-signal gain: Gc→PWM = {compGain < 1 ? `1/${compDividerRatio} = ${sf(compGain,3)}` : "1 (direct)"}
                        {compGain < 1 && <> — loop gain reduced by {sf(dB(compGain),1)}dB</>}
                      </div>
                    )}
                    {selIC.link && <a href={selIC.link} target="_blank" rel="noopener noreferrer" style={{fontSize:9.5,color:col.accent,marginBottom:4,display:"block"}}>Datasheet →</a>}
                    {(()=>{ const icVal = validateIC(selIC, fsw*1e3, pinfo); return <>
                      {icVal.errors.map((e,i)=><div key={"ie"+i} style={{fontSize:10,color:col.err,marginBottom:2}}>⚠ {e}</div>)}
                      {icVal.warnings.map((w,i)=><div key={"iw"+i} style={{fontSize:10,color:col.warn,marginBottom:2}}>⚠ {w}</div>)}
                    </>; })()}
                  </>}
                  {selectedIC==="custom" && <div style={{fontSize:9.5,color:col.dim}}>All parameters entered manually.</div>}
                  <div style={sDivider} />
                  <div style={{fontSize:10.5,fontWeight:600,color:col.bright,marginBottom:4}}>REFERENCE</div>
                  <NumInput label="Vref" unit="V" val={vref} onVal={setVref} />
                </div>}

                {/* Operating Point */}
                <div style={card}>
                  <div style={cardTitle}>OPERATING POINT</div>
                  <div style={{display:"flex",gap:4}}>
                    <div style={{flex:1}}><NumInput label="Vin min" unit="V" val={vinMin} onVal={setVinMin} /></div>
                    <div style={{flex:1}}><NumInput label="Vin max" unit="V" val={vinMax} onVal={setVinMax} /></div>
                  </div>
                  <div style={{display:"flex",alignItems:"center",gap:5,marginBottom:4}}>
                    <input type="checkbox" checked={useVinNom} onChange={e=>setUseVinNom(e.target.checked)} id="vnomchk2" />
                    <label htmlFor="vnomchk2" style={{...sLabel,marginBottom:0,cursor:"pointer"}}>CUSTOM Vin NOM</label>
                  </div>
                  {useVinNom && <NumInput label="Vin nom" unit="V" val={vinNomUser} onVal={setVinNomUser} />}
                  <div style={{display:"flex",gap:4}}>
                    <div style={{flex:1}}><NumInput label="Vout" unit="V" val={vout} onVal={setVout} /></div>
                    <div style={{flex:1}}><NumInput label="Vout tol" unit="±%" val={voutTol} onVal={setVoutTol} /></div>
                  </div>
                  <div style={{display:"flex",gap:4}}>
                    <div style={{flex:1}}><NumInput label="Iout" unit="A" val={iout} onVal={setIout} /></div>
                    <div style={{flex:1}}><NumInput label="fsw" unit="kHz" val={fsw} onVal={setFsw} /></div>
                  </div>
                  <div style={{fontSize:10,color:col.dim,fontFamily:"monospace",marginTop:4}}>
                    D={sf(Dactive*100,1)}% @ {vinActive}V | Dmax={sf(Dmax*100,1)}% @ {vinMin}V
                  </div>
                </div>

                {/* Transformer (2SW Forward only) */}
                {isIsolated && cardVis.xfmr && <div style={card}>
                  <div style={cardTitle}>TRANSFORMER</div>
                  <div style={{display:"flex",gap:4}}>
                    <div style={{flex:1}}><NumInput label="Np (primary)" unit="turns" val={xfmrNp} onVal={v=>setXfmrNp(Math.max(1,Math.round(v)))} /></div>
                    <div style={{flex:1}}><NumInput label="Ns (secondary)" unit="turns" val={xfmrNs} onVal={v=>setXfmrNs(Math.max(1,Math.round(v)))} /></div>
                  </div>
                  <NumInput label="Lm (magnetizing)" unit="µH" val={xfmrLm} onVal={setXfmrLm} />
                  <div style={{fontSize:10,color:col.dim,fontFamily:"monospace",marginTop:6,lineHeight:1.7}}>
                    n = Ns/Np = {sf(turnsRatio,4)} ({xfmrNs}:{xfmrNp})<br/>
                    Vin(eff) = Vin × n = {sf(vinMin*turnsRatio,2)}–{sf(vinMax*turnsRatio,2)} V<br/>
                    {isFlyback
                      ? <>D(nom) = Vout/(Vout+Vin·n) = {sf(Dnom*100,1)}% @ {vinNom.toFixed(1)}V<br/>
                         D(max) = {sf(Dmax*100,1)}% @ {vinMin}V {Dmax>DmaxConstraint?<span style={{color:col.err}}> ⚠ {">"} {sf(DmaxConstraint*100,0)}%</span>:<span style={{color:col.ok}}> ✓ ≤ {sf(DmaxConstraint*100,0)}%</span>}</>
                      : <>D(nom) = Vout/(Vin·n) = {sf(Dnom*100,1)}% @ {vinNom.toFixed(1)}V<br/>
                         D(max) = {sf(Dmax*100,1)}% @ {vinMin}V {Dmax>0.50?<span style={{color:col.err}}> ⚠ {">"} 50%</span>:<span style={{color:col.ok}}> ✓ ≤ 50%</span>}</>}
                  </div>
                  <div style={{fontSize:9.5,color:col.dim,marginTop:4,lineHeight:1.4}}>
                    {isFlyback
                      ? "Lm is the energy storage element. The plant has a Right-Half-Plane Zero (RHPZ) that limits achievable bandwidth. Crossover must stay well below the RHPZ."
                      : "Output inductor L and capacitor bank are on the secondary side. The small-signal plant model is equivalent to a buck with Vin(eff) = Vin × Ns/Np."}
                  </div>
                  {/* Auxiliary (unregulated) secondary outputs */}
                  <div style={{marginTop:8,borderTop:`1px solid ${col.border}`,paddingTop:6}}>
                    <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:4}}>
                      <span style={{fontSize:10,color:col.dim,fontWeight:600}}>SECONDARY WINDINGS ({auxSecondaries.length+1} total)</span>
                      {auxSecondaries.length < 3 && <button onClick={()=>setAuxSecondaries(prev=>[...prev,{
                        ns:xfmrNs, lout_uH:22, vout:3.3, label:`Winding ${prev.length+2}`,
                        cap_qty:1, cap_uF:100, cap_esr_mOhm:20,
                      }])}
                        style={{fontSize:9,color:col.accent,background:"transparent",border:`1px solid ${col.accent}`,borderRadius:3,padding:"2px 8px",cursor:"pointer"}}>+ Add Winding</button>}
                    </div>
                    {/* Main regulated output (winding 1) */}
                    <div style={{fontSize:9.5,color:col.dim,marginBottom:4,lineHeight:1.4}}>
                      <span style={{color:col.ok,fontWeight:600}}>Winding 1 (regulated):</span> Ns={xfmrNs}, Vout={vout}V, Iout={iout}A — caps defined in OUTPUT CAP BANK card
                    </div>
                    {auxSecondaries.length === 0 && <div style={{fontSize:9.5,color:col.dim,fontStyle:"italic"}}>
                      {isFlyback
                        ? "Single-output flyback. Add windings for cross-regulated auxiliary outputs."
                        : "Single-output forward. Add windings with output inductors for auxiliary outputs (affects primary-side Sn)."}
                    </div>}
                    {auxSecondaries.map((aux, idx) => (
                      <div key={idx} style={{background:"#0c1520",border:`1px solid ${col.border}`,borderRadius:4,padding:"6px 8px",marginBottom:4}}>
                        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:4}}>
                          <span style={{fontSize:10,color:col.bright,fontWeight:600}}>{aux.label || `Winding ${idx+2}`}</span>
                          <button onClick={()=>setAuxSecondaries(prev=>prev.filter((_,i)=>i!==idx))}
                            style={{fontSize:9,color:col.err,background:"transparent",border:"none",cursor:"pointer"}}>✕ Remove</button>
                        </div>
                        <div style={{display:"flex",gap:4}}>
                          <div style={{flex:1}}><NumInput label="Ns" unit="turns" val={aux.ns}
                            onVal={v=>setAuxSecondaries(prev=>prev.map((a,i)=>i===idx?{...a,ns:Math.max(1,Math.round(v))}:a))} /></div>
                          {!isFlyback && <div style={{flex:1}}><NumInput label="Lout" unit="µH" val={aux.lout_uH}
                            onVal={v=>setAuxSecondaries(prev=>prev.map((a,i)=>i===idx?{...a,lout_uH:v}:a))} /></div>}
                          <div style={{flex:1}}><NumInput label="Vout" unit="V" val={aux.vout}
                            onVal={v=>setAuxSecondaries(prev=>prev.map((a,i)=>i===idx?{...a,vout:v}:a))} /></div>
                        </div>
                        {/* Per-winding output caps */}
                        <div style={{display:"flex",gap:4,marginTop:4}}>
                          <div style={{width:40}}><NumInput label="Qty" unit="" val={aux.cap_qty||1}
                            onVal={v=>setAuxSecondaries(prev=>prev.map((a,i)=>i===idx?{...a,cap_qty:Math.max(1,Math.round(v))}:a))} /></div>
                          <div style={{flex:1}}><NumInput label="C" unit="µF" val={aux.cap_uF||100}
                            onVal={v=>setAuxSecondaries(prev=>prev.map((a,i)=>i===idx?{...a,cap_uF:v}:a))} /></div>
                          <div style={{flex:1}}><NumInput label="ESR" unit="mΩ" val={aux.cap_esr_mOhm||20}
                            onVal={v=>setAuxSecondaries(prev=>prev.map((a,i)=>i===idx?{...a,cap_esr_mOhm:v}:a))} /></div>
                        </div>
                        <div style={{fontSize:9,color:col.dim,fontFamily:"monospace",marginTop:3}}>
                          n={sf(aux.ns/Math.max(xfmrNp,1),3)} | Vin_eff={sf(vinNom*(aux.ns/Math.max(xfmrNp,1)),1)}V
                          {isFlyback
                            ? ` | D=${sf(aux.vout/Math.max(aux.vout+vinNom*(aux.ns/Math.max(xfmrNp,1)),0.01)*100,1)}%`
                            : ` | D=${sf(aux.vout/Math.max(vinNom*(aux.ns/Math.max(xfmrNp,1)),0.01)*100,1)}%`}
                          {` | Cout=${aux.cap_qty||1}×${aux.cap_uF||100}µF`}
                        </div>
                      </div>
                    ))}
                    {!isFlyback && auxSecondaries.length > 0 && lmAffectsSn && <div style={{fontSize:9.5,color:"#93c5fd",marginTop:2}}>
                      Aux inductors contribute additional slope at primary-side CT → increases mc.
                    </div>}
                    {isFlyback && auxSecondaries.length > 0 && <div style={{fontSize:9.5,color:col.dim,marginTop:2}}>
                      Flyback aux windings are cross-regulated (unregulated). They do not affect the control loop.
                    </div>}
                  </div>
                </div>}

                {/* Power Stage */}
                {cardVis.pstage && <div style={card}>
                  <div style={cardTitle}>POWER STAGE</div>
                  {isFlyback
                    ? <div style={{fontSize:10,color:col.dim,lineHeight:1.5,marginBottom:6}}>
                        Flyback uses Lm ({xfmrLm} µH) as the energy storage element. No separate output inductor. Configure Lm on the Transformer card above.
                      </div>
                    : <NumInput label="L (inductor)" unit="µH" val={L} onVal={setL} />}
                  <div style={{display:"flex",gap:3,marginBottom:6,marginTop:6}}>
                    <SmBtn label="STANDARD" active={plantMode==="standard"} onClick={()=>{setPlantMode("standard");setFrozenComp(null);}} />
                    <SmBtn label="gm_ps" active={plantMode==="gmps"} onClick={()=>{setPlantMode("gmps");setFrozenComp(null);}} />
                  </div>
                  {plantMode==="gmps" && <NumInput label="gm_ps" unit="S" val={gmps} onVal={setGmps} />}
                  <div style={{fontSize:10,color:col.dim,lineHeight:1.5,marginTop:4}}>
                    {plantMode==="gmps"
                      ? "Ridley gm_ps: inner loop absorbed into transconductance."
                      : "Standard: explicit inductor, PWM comparator, current sense."}
                  </div>
                </div>}

                {/* Output Cap Bank */}
                {cardVis.caps && <div style={card}>
                  <div style={cardTitle}>OUTPUT CAP BANK</div>
                  {capSlots.map((s,i)=>(
                    <div key={i} style={{marginBottom:6,paddingBottom:6,borderBottom:i<capSlots.length-1?`1px solid ${col.border}`:"none"}}>
                      <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:3}}>
                        <span style={{fontSize:10,color:col.dim,fontWeight:600}}>Group {i+1}</span>
                        {capSlots.length>1 && <button onClick={()=>setCapSlots(c=>[...c.slice(0,i),...c.slice(i+1)])} style={{background:"transparent",color:col.err,border:"none",cursor:"pointer",fontSize:11,padding:0}}>✕</button>}
                      </div>
                      <div style={{display:"flex",gap:4}}>
                        <div style={{width:40}}><NumInput label="Qty" unit="" val={s.qty} onVal={v=>updateCapSlot(i,"qty",Math.max(1,Math.round(v)))} /></div>
                        <div style={{flex:1}}><NumInput label="C" unit="µF" val={s.c_uF} onVal={v=>updateCapSlot(i,"c_uF",v)} /></div>
                        <div style={{flex:1}}><NumInput label="ESR" unit="mΩ" val={s.esr_mOhm} onVal={v=>updateCapSlot(i,"esr_mOhm",v)} /></div>
                      </div>
                      <div style={{display:"flex",gap:4}}>
                        <div style={{flex:1}}><NumInput label="ESL" unit="nH" val={s.esl_nH} onVal={v=>updateCapSlot(i,"esl_nH",v)} /></div>
                        <div style={{flex:1}}>
                          <select value={s.type} onChange={e=>updateCapSlot(i,"type",e.target.value)} style={{width:"100%",background:col.bg,color:col.bright,border:`1px solid ${col.border}`,borderRadius:3,padding:"4px 4px",fontSize:10,marginBottom:2}}>
                            <option value="ceramic">Ceramic</option><option value="electrolytic">Electrolytic</option>
                            <option value="polymer">Polymer</option><option value="tantalum">Tantalum</option><option value="film">Film</option>
                          </select>
                        </div>
                      </div>
                    </div>
                  ))}
                  {capSlots.length < 3 && <button onClick={()=>setCapSlots(c=>[...c,{qty:1,c_uF:100,esr_mOhm:10,esl_nH:0,type:"ceramic"}])} style={{width:"100%",background:"transparent",color:col.accent,border:`1px dashed ${col.border}`,borderRadius:4,padding:"4px 0",fontSize:10,cursor:"pointer"}}>+ Add Cap Group</button>}
                  {/* Impedance CSV import */}
                  <button onClick={()=>setShowCapCSV(!showCapCSV)} style={{width:"100%",background:"transparent",color:"#93c5fd",border:`1px dashed ${col.border}`,borderRadius:4,padding:"4px 0",fontSize:10,cursor:"pointer",marginTop:4}}>
                    {showCapCSV ? "▾ Close CSV Import" : "▸ Import Impedance CSV"}
                  </button>
                  {showCapCSV && <div style={{marginTop:6,background:"#0c1520",border:`1px solid ${col.border}`,borderRadius:4,padding:8}}>
                    <div style={{fontSize:9.5,color:col.dim,marginBottom:4,lineHeight:1.4}}>
                      Paste impedance data from vendor tools (Murata SimSurfing, TDK SEAT, Kemet K-SIM).<br/>
                      Format: frequency, |Z|, phase (phase optional). Tab/comma/semicolon separated.
                    </div>
                    <textarea value={capCSVText} onChange={e=>setCapCSVText(e.target.value)}
                      placeholder={"freq(Hz)  |Z|(Ω)  phase(°)\n1000      15.9     -89.5\n10000     1.59     -85.2\n100000    0.020    -2.1\n1000000   0.125    87.3"}
                      style={{width:"100%",height:80,background:col.bg,color:col.bright,border:`1px solid ${col.border}`,borderRadius:3,padding:6,fontSize:10,fontFamily:"monospace",resize:"vertical",boxSizing:"border-box"}} />
                    <div style={{display:"flex",gap:4,marginTop:4}}>
                      <button onClick={()=>{
                        const parsed = parseImpedanceCSV(capCSVText);
                        if (parsed.error) { setCapCSVResult({error:parsed.error}); return; }
                        const fit = fitCapFromImpedance(parsed.data);
                        if (!fit) { setCapCSVResult({error:"Could not fit C/ESR/ESL from data"}); return; }
                        setCapCSVResult({...fit, data: parsed.data});
                      }} style={{flex:1,background:col.accent,color:"#fff",border:"none",borderRadius:3,padding:"5px 0",fontSize:10,cursor:"pointer",fontWeight:700}}>Fit C/ESR/ESL</button>
                      {capCSVResult && capCSVResult.C_F && <button onClick={()=>{
                        setCapSlots(prev => {
                          const newSlot = {
                            qty: 1,
                            c_uF: +(capCSVResult.C_F * 1e6).toPrecision(3),
                            esr_mOhm: +(capCSVResult.ESR_ohm * 1e3).toPrecision(3),
                            esl_nH: +(capCSVResult.ESL_H * 1e9).toPrecision(3),
                            type: "ceramic",
                          };
                          return prev.length < 3 ? [...prev, newSlot] : [...prev.slice(0,-1), newSlot];
                        });
                        setShowCapCSV(false);
                        setCapCSVResult(null);
                      }} style={{flex:1,background:"#166534",color:"#86efac",border:"none",borderRadius:3,padding:"5px 0",fontSize:10,cursor:"pointer",fontWeight:700}}>Apply to Cap Group</button>}
                    </div>
                    {capCSVResult && capCSVResult.error && <div style={{fontSize:10,color:col.err,marginTop:4}}>{capCSVResult.error}</div>}
                    {capCSVResult && capCSVResult.C_F && <div style={{fontSize:10,color:col.bright,fontFamily:"monospace",marginTop:4,lineHeight:1.6}}>
                      Fitted from {capCSVResult.nPoints} points (SRF ≈ {fmtFreq(capCSVResult.f_srf)}):<br/>
                      C = {(capCSVResult.C_F*1e6).toPrecision(3)} µF | ESR = {(capCSVResult.ESR_ohm*1e3).toPrecision(3)} mΩ | ESL = {(capCSVResult.ESL_H*1e9).toPrecision(3)} nH
                    </div>}
                  </div>}
                  <div style={{fontSize:10,color:col.dim,fontFamily:"monospace",marginTop:4}}>
                    Ceff={fmtSI(capEff.Ceff,"F")} | ESReff={fmtSI(capEff.ESReff,"R")} | fz_ESR={pinfo.fz_esr?fmtFreq(pinfo.fz_esr):"--"}
                  </div>
                  {antiRes && <div style={{fontSize:10,color:col.warn,marginTop:2}}>⚠ Anti-resonance at {fmtFreq(antiRes.freq)}</div>}
                </div>}

                {/* Current Sense */}
                {cardVis.sense && <div style={card}>
                  <div style={cardTitle}>CURRENT SENSE</div>
                  {/* Isolated topology: primary vs secondary side selector */}
                  {isIsolated && <div style={{marginBottom:8}}>
                    <div style={{fontSize:10,color:col.dim,marginBottom:4}}>Sense location (transformer side):</div>
                    <div style={{display:"flex",gap:3,marginBottom:4}}>
                      <SmBtn label="PRIMARY" active={isoSenseSide==="primary"} onClick={()=>setIsoSenseSide("primary")} />
                      <SmBtn label="SECONDARY" active={isoSenseSide==="secondary"} onClick={()=>setIsoSenseSide("secondary")} />
                    </div>
                    <div style={{fontSize:9.5,color:col.dim,lineHeight:1.4}}>
                      {isoSenseSide==="primary"
                        ? "CT/shunt between FETs or in low-side return. Senses reflected load current + magnetizing ramp. Typical for UC3844/5 primary-side control."
                        : "CT/shunt on secondary (before output inductor). Senses output inductor current only — no magnetizing component. Typical for secondary-side controllers (LTC3726)."}
                    </div>
                    {lmAffectsSn && <div style={{fontSize:9.5,color:"#93c5fd",marginTop:3}}>
                      Lm correction active: magnetizing ramp (Vin/Lm) adds to natural slope Sn.
                    </div>}
                  </div>}
                  {/* IC with internal sense shows gm_ps table */}
                  {selIC && selIC.senseInternal ? (
                    <div style={{background:"#0c1520",border:`1px solid ${col.border}`,borderRadius:4,padding:"8px 10px",marginBottom:6}}>
                      <div style={{fontSize:10.5,color:col.accent,fontWeight:600,marginBottom:4}}>INTERNAL TO {selIC.name}</div>
                      {selIC.gmps_table && <>
                        <div style={{fontSize:10,color:col.dim,marginBottom:4}}>Current limit / gm_ps setting:</div>
                        <div style={{display:"flex",gap:3,marginBottom:4,flexWrap:"wrap"}}>
                          {selIC.gmps_table.map((row,i) => (
                            <SmBtn key={i} label={`${row.ilim_A}A`} active={ilimIdx===i}
                              onClick={()=>applyIlim(i)} />
                          ))}
                        </div>
                        <div style={{fontSize:10.5,color:col.bright,fontFamily:"monospace",lineHeight:1.6,marginBottom:4}}>
                          gm_ps(table) = {selIC.gmps_table[ilimIdx]?.gm_ps} S @ I_lim = {selIC.gmps_table[ilimIdx]?.ilim_A}A<br/>
                          R_ILIM: top={selIC.gmps_table[ilimIdx]?.Rlim_top}Ω, bot={selIC.gmps_table[ilimIdx]?.Rlim_bot}Ω
                        </div>
                      </>}
                      <div style={{fontSize:10,color:col.dim,fontFamily:"monospace",lineHeight:1.5}}>
                        High-side sense — integrated in power stage<br/>
                        LEB = {selIC.tLEB_ns} ns | CS delay = {selIC.csDelay_ns} ns
                        {selIC.slopeComp === "external_rsc" && <><br/>Slope comp: configurable via RSC resistor</>}
                      </div>
                    </div>
                  ) : (
                    <>
                      <div style={{display:"flex",gap:3,marginBottom:6}}>
                        <SmBtn label="SIMPLE" active={senseMode==="simple"} onClick={()=>setSenseMode("simple")} />
                        <SmBtn label="SHUNT" active={senseMode==="shunt"} onClick={()=>setSenseMode("shunt")} />
                        <SmBtn label="CT" active={senseMode==="ct"} onClick={()=>setSenseMode("ct")} />
                      </div>
                      {senseMode==="simple" && <NumInput label="Ri (sense gain)" unit="V/A" val={ri} onVal={setRi} />}
                      {(senseMode==="shunt"||senseMode==="ct") && <>
                        <div style={{display:"flex",gap:3,marginBottom:4}}>
                          <SmBtn label="HIGH-SIDE" active={sensePlacement==="high_side"} onClick={()=>setSensePlacement("high_side")} />
                          <SmBtn label="INDUCTOR" active={sensePlacement==="inductor"} onClick={()=>setSensePlacement("inductor")} />
                        </div>
                        {sensePlacement==="inductor" && senseMode==="ct" && <div style={{fontSize:9.5,color:col.err,marginBottom:4}}>⚠ CT cannot self-reset with continuous inductor current in CCM.</div>}
                        {sensePlacement==="inductor" && senseMode==="shunt" && <div style={{fontSize:9.5,color:col.dim,marginBottom:4}}>Continuous current — highest Irms loss. No LEB needed.</div>}
                      </>}
                      {senseMode==="shunt" && <>
                        <NumInput label="Rshunt" unit="mΩ" val={rshunt} onVal={setRshunt} />
                        <div style={{display:"flex",gap:4}}>
                          <div style={{flex:1}}><NumInput label="Lpar" unit="nH" val={lpar} onVal={setLpar} /></div>
                          <div style={{flex:1}}><NumInput label="Gamp" unit="V/V" val={gampDC} onVal={setGampDC} /></div>
                        </div>
                        <NumInput label="Amp BW" unit="MHz" val={gampBW} onVal={setGampBW} />
                        <div style={{display:"flex",gap:4}}>
                          <div style={{flex:1}}><NumInput label="Rfilt" unit="Ω" val={rfilter} onVal={setRfilter} /></div>
                          <div style={{flex:1}}><NumInput label="Cfilt" unit="pF" val={cfilter} onVal={setCfilter} /></div>
                        </div>
                        <NumInput label="LEB" unit="ns" val={tLEB} onVal={setTLEB} />
                        <div style={{fontSize:10,color:col.dim,fontFamily:"monospace",marginTop:2}}>
                          Ri_eff = {sf(ri_eff*1e3,1)} mΩ = {sf(ri_eff,4)} V/A
                        </div>
                      </>}
                      {senseMode==="ct" && <>
                        <div style={{display:"flex",gap:4}}>
                          <div style={{flex:1}}><NumInput label="Np" unit="turns" val={ctNp} onVal={v=>setCtNp(Math.max(1,Math.round(v)))} /></div>
                          <div style={{flex:1}}><NumInput label="Ns" unit="turns" val={ctNs} onVal={v=>setCtNs(Math.max(1,Math.round(v)))} /></div>
                        </div>
                        <NumInput label="Rb (burden)" unit="Ω" val={ctRb} onVal={setCtRb} />
                        <NumInput label="Lm (magnetizing)" unit="mH" val={ctLm} onVal={setCtLm} />
                        <div style={{display:"flex",gap:4}}>
                          <div style={{flex:1}}><NumInput label="Llk" unit="µH" val={ctLlk} onVal={setCtLlk} /></div>
                          <div style={{flex:1}}><NumInput label="Cw" unit="pF" val={ctCw} onVal={setCtCw} /></div>
                        </div>
                        <div style={{display:"flex",gap:3,marginBottom:4}}>
                          <SmBtn label="SELF-RESET" active={ctReset==="self"} onClick={()=>setCtReset("self")} />
                          <SmBtn label="FORCED" active={ctReset==="forced"} onClick={()=>setCtReset("forced")} />
                        </div>
                        <NumInput label="LEB" unit="ns" val={tLEB} onVal={setTLEB} />
                        <div style={{fontSize:10,color:col.dim,fontFamily:"monospace",marginTop:2}}>
                          Ri_eff = {ctNp}:{ctNs} × {ctRb}Ω = {sf(ri_eff,4)} V/A
                        </div>
                      </>}
                    </>
                  )}
                </div>}

                {/* Slope Compensation */}
                {cardVis.slope && <div style={card}>
                  <div style={cardTitle}>SLOPE COMPENSATION</div>
                  {plantMode === "gmps" && selIC && selIC.slopeComp === "external_rsc" ? (()=>{
                    const fsw_kHz = fsw;
                    const computeRSC = (sc) => sc > 0 ? 0.208 * gmps * Math.pow(sc, -1.5) * fsw_kHz : 9999;
                    const computeSC = (rsc) => rsc > 0 ? Math.pow(0.208 * gmps * fsw_kHz / rsc, 1/1.5) : 0;
                    const scSuggested = L > 0 ? vout / L : 0;
                    const handleScChange = (v) => { setScAus(v); if (v > 0) setRscKohm(parseFloat(computeRSC(v).toFixed(1))); };
                    const handleRscChange = (v) => { setRscKohm(v); if (v > 0) setScAus(parseFloat(computeSC(v).toFixed(3))); };
                    return <>
                      <div style={{fontSize:10,color:col.accent,fontWeight:600,marginBottom:4}}>RSC Calculator ({selIC.name})</div>
                      <div style={{display:"flex",gap:4}}>
                        <div style={{flex:1}}><NumInput label="SC" unit="A/µs" val={scAus} onVal={handleScChange} /></div>
                        <div style={{flex:1}}><NumInput label="RSC" unit="kΩ" val={rscKohm} onVal={handleRscChange} /></div>
                      </div>
                      <div style={{fontSize:9.5,color:col.dim,fontFamily:"monospace",lineHeight:1.6,marginBottom:4}}>
                        R<sub>SC</sub> = 0.208 × g<sub>mps</sub> × SC⁻¹·⁵ × f<sub>SW</sub><br/>
                        Suggested SC ≈ V<sub>OUT</sub>/L = {sf(scSuggested,2)} A/µs → RSC ≈ {sf(computeRSC(scSuggested),0)} kΩ
                      </div>
                      <label style={{display:"flex",alignItems:"center",gap:6,cursor:"pointer",fontSize:10.5,color:scEnabled?col.warn:col.dim,marginBottom:4}}>
                        <input type="checkbox" checked={scEnabled} onChange={e=>setScEnabled(e.target.checked)} />
                        Apply SC→gm_ps correction to Bode
                      </label>
                      <div style={{fontSize:9.5,color:"#93c5fd",fontFamily:"monospace",lineHeight:1.5,background:"#0c1520",border:`1px solid ${col.border}`,borderRadius:3,padding:"4px 6px"}}>
                        {scEnabled ? <>
                          SC ON: gm_ps(eff) = {sf(pinfo.gm_ps,2)} S<br/>
                          mc = {sf(pinfo.mc,2)}, factor = {sf(pinfo.factor,3)}, Qp = {sf(pinfo.Qp,2)}
                        </> : <>
                          SC OFF (default). gm_ps = {sf(gmps,1)} S direct.<br/>
                          He: factor = {sf(pinfo.factor,3)}, Qp = {sf(pinfo.Qp,2)}
                        </>}
                      </div>
                      {lmAffectsSn && pinfo.sn_mag > 0 && <div style={{fontSize:9.5,color:"#93c5fd",fontFamily:"monospace",marginTop:3,lineHeight:1.6}}>
                        Se(Lm) = {sf(pinfo.sn_mag,2)} A/µs equiv. ext. slope → mc includes {sf(pinfo.sn_mag / Math.max(pinfo.sn_inductor, 1e-6) * 100, 0)}% from Lm
                      </div>}
                    </>;
                  })() : plantMode === "gmps" ? <>
                    {/* gm_ps mode without RSC calculator: show SC input */}
                    <NumInput label="SC (slope comp)" unit="A/µs" val={scAus} onVal={setScAus} />
                    <label style={{display:"flex",alignItems:"center",gap:6,cursor:"pointer",fontSize:10.5,color:scEnabled?col.warn:col.dim,marginTop:4}}>
                      <input type="checkbox" checked={scEnabled} onChange={e=>setScEnabled(e.target.checked)} />
                      Apply SC→gm_ps correction to Bode
                    </label>
                    <div style={{fontSize:9.5,color:"#93c5fd",fontFamily:"monospace",lineHeight:1.5,background:"#0c1520",border:`1px solid ${col.border}`,borderRadius:3,padding:"4px 6px",marginTop:4}}>
                      {scEnabled ? <>
                        SC ON: gm_ps(eff) = {sf(pinfo.gm_ps,2)} S<br/>
                        mc = {sf(pinfo.mc,2)}, factor = {sf(pinfo.factor,3)}, Qp = {sf(pinfo.Qp,2)}
                      </> : <>
                        SC OFF (default). gm_ps = {sf(gmps,1)} S direct.<br/>
                        He: factor = {sf(pinfo.factor,3)}, Qp = {sf(pinfo.Qp,2)}
                      </>}
                    </div>
                    {lmAffectsSn && pinfo.sn_mag > 0 && <div style={{fontSize:9.5,color:"#93c5fd",fontFamily:"monospace",marginTop:3,lineHeight:1.6}}>
                      Se(Lm) = {sf(pinfo.sn_mag,2)} A/µs equiv. ext. slope → mc includes {sf(pinfo.sn_mag / Math.max(pinfo.sn_inductor, 1e-6) * 100, 0)}% from Lm
                    </div>}
                  </> : <>
                    {/* Standard mode: show Se (external ramp voltage at comparator) */}
                    <NumInput label="Se (ext ramp)" unit="mV/µs" val={se} onVal={setSe} />
                    <div style={{fontSize:10,color:pinfo.factor<=0?col.err:pinfo.factor<0.15?col.warn:col.dim,fontFamily:"monospace",marginTop:4}}>
                      mc={sf(pinfo.mc,2)} | mc·D'-0.5={sf(pinfo.factor,3)}{pinfo.factor<=0?" ⚠ UNSTABLE":""}
                    </div>
                    {lmAffectsSn && pinfo.sn_mag > 0 && <div style={{fontSize:9.5,color:"#93c5fd",fontFamily:"monospace",marginTop:3,lineHeight:1.6}}>
                      Sn(L) = {sf(pinfo.sn_inductor * ri_eff,2)} V/s (natural inductor slope)<br/>
                      Se(Lm) = {sf(pinfo.sn_mag * ri_eff,2)} V/s (equiv. ext. slope from magnetizing ramp)<br/>
                      {auxSecondaries.length > 0 && <>Se(aux) = {auxSecondaries.length} aux output{auxSecondaries.length>1?"s":""} contribute additional slope<br/></>}
                      mc = 1 + (Se + Se_Lm{auxSecondaries.length>0?" + Se_aux":""})/Sn = {sf(pinfo.mc,3)} — Lm{auxSecondaries.length>0?" + aux outputs":""} provide{auxSecondaries.length>0?"":"s"} {sf((pinfo.mc - 1) * 100, 0)}% total equiv. slope comp
                    </div>}
                  </>}
                </div>}

                {/* Error Amplifier */}
                {cardVis.ea && <div style={card}>
                  <div style={cardTitle}>ERROR AMPLIFIER</div>
                  <div style={{display:"flex",gap:3,marginBottom:6}}>
                    <SmBtn label="IDEAL" active={eaType==="ideal"} onClick={()=>setEaType("ideal")} />
                    <SmBtn label="OP-AMP" active={eaType==="opamp"} onClick={()=>setEaType("opamp")} />
                    <SmBtn label="OTA" active={eaType==="ota"} onClick={()=>setEaType("ota")} />
                  </div>
                  {eaType==="opamp" && <>
                    <NumInput label="Aol (DC gain)" unit="dB" val={eaAol} onVal={setEaAol} />
                    <NumInput label="GBW" unit="MHz" val={eaGBW} onVal={setEaGBW} />
                    <NumInput label="EA phase margin" unit="deg" val={eaPM} onVal={setEaPM} />
                    <div style={{fontSize:10.5,color:col.dim,fontFamily:"monospace",marginBottom:4}}>
                      fp1(EA) = {fmtFreq(eaInfo.fp1_ea)} | Aol = {sf(eaInfo.Aol_dB,0)} dB
                    </div>
                  </>}
                  {eaType==="ota" && <>
                    <NumInput label="gm" unit="µA/V" val={eaGm} onVal={setEaGm} />
                    <NumInput label="Rout" unit="MΩ" val={eaRout} onVal={setEaRout} />
                    <NumInput label="Cout(EA)" unit="pF" val={eaCout} onVal={setEaCout} />
                    <div style={{fontSize:10.5,color:col.dim,fontFamily:"monospace",marginBottom:4}}>
                      Aol = {sf(eaInfo.Aol_dB,0)} dB{eaInfo.noCout
                        ? <> | No internal pole<br/><span style={{color:col.ok}}>All shaping via ext RCOMP/CCOMP/CHF</span></>
                        : <> | GBW = {fmtFreq(eaInfo.GBW_Hz)} | fp1 = {fmtFreq(eaInfo.fp1_ea)}</>}
                    </div>
                  </>}
                  {eaType!=="ideal" && <>
                    <div style={{display:"flex",gap:4}}>
                      <div style={{flex:1}}><NumInput label="COMP low" unit="V" val={compClampLow} onVal={setCompClampLow} /></div>
                      <div style={{flex:1}}><NumInput label="COMP high" unit="V" val={compClampHigh} onVal={setCompClampHigh} /></div>
                    </div>
                    <NumInput label="CS-to-out delay" unit="ns" val={csDelay} onVal={setCsDelay} />
                    <div style={{display:"flex",gap:4}}>
                      <div style={{flex:1}}><NumInput label="EA I src" unit="µA" val={eaIsrc} onVal={setEaIsrc} /></div>
                      <div style={{flex:1}}><NumInput label="EA I snk" unit="µA" val={eaIsnk} onVal={setEaIsnk} /></div>
                    </div>
                  </>}
                  {eaType==="ideal" && <div style={{fontSize:10.5,color:col.dim}}>Infinite gain, infinite bandwidth.</div>}
                </div>}

                {/* Opto-Isolator Feedback (isolated topologies only) */}
                {isIsolated && cardVis.opto && <div style={card}>
                  <div style={cardTitle}>ISOLATED FEEDBACK</div>
                  <div style={{display:"flex",gap:3,marginBottom:6}}>
                    <SmBtn label="OPTOCOUPLER" active={fbMode==="opto"} onClick={()=>setFbMode("opto")} />
                    <SmBtn label="PRIMARY-SIDE" active={fbMode==="primary"} onClick={()=>setFbMode("primary")} />
                  </div>
                  {fbMode === "opto" ? <>
                    <div style={{fontSize:9.5,color:col.dim,lineHeight:1.4,marginBottom:4}}>
                      TL431 + opto across isolation. R<sub>pullup</sub> × C<sub>opto</sub> forms bandwidth-limiting pole.
                    </div>
                    <NumInput label="CTR" unit="" val={optoCTR} onVal={setOptoCTR} />
                    <div style={{display:"flex",gap:4}}>
                      <div style={{flex:1}}><NumInput label="R pullup" unit="kΩ" val={optoRpullup} onVal={setOptoRpullup} /></div>
                      <div style={{flex:1}}><NumInput label="R LED" unit="kΩ" val={optoRled} onVal={setOptoRled} /></div>
                    </div>
                    <NumInput label="C opto" unit="nF" val={optoCopto} onVal={setOptoCopto} />
                    <div style={{fontSize:9.5,color:col.dim,fontFamily:"monospace",marginTop:4,lineHeight:1.6}}>
                      G<sub>0</sub> = CTR×R<sub>pu</sub>/R<sub>led</sub> = {sf(optoGain,3)} ({sf(dB(optoGain),1)}dB)<br/>
                      f<sub>p</sub> = 1/(2π·R<sub>pu</sub>·C<sub>opto</sub>) = {fp_opto>0?fmtFreq(fp_opto):"∞"}<br/>
                      H<sub>dc</sub> = (V<sub>ref</sub>/V<sub>out</sub>)×G<sub>0</sub> = {sf(vref/vout*optoGain,4)}
                    </div>
                    {fp_opto > 0 && fp_opto < fcTarget * 1e3 * 2 && <div style={{fontSize:9.5,color:col.warn,marginTop:4}}>
                      ⚠ Opto pole at {fmtFreq(fp_opto)} is near fc target. Adds phase lag.
                    </div>}
                  </> : <>
                    <div style={{fontSize:9.5,color:col.dim,lineHeight:1.5,marginBottom:4}}>
                      Primary-side regulation via aux winding. Resistor divider from aux output to FB pin; COMP network from COMP pin to same node (ISL71041M/ISL71043M topology).
                    </div>
                    <div style={{fontSize:9.5,color:col.dim,fontFamily:"monospace",lineHeight:1.6}}>
                      H<sub>dc</sub> = V<sub>ref</sub>/V<sub>out</sub> = {sf(vref/vout,4)}<br/>
                      No opto pole — flat feedback to &gt;1 MHz<br/>
                      Loop gain = Gvc(s) × Gc(s) × H<sub>dc</sub>
                    </div>
                    <div style={{fontSize:9.5,color:"#93c5fd",marginTop:4,lineHeight:1.4}}>
                      Aux winding turns ratio sets V<sub>aux</sub> = V<sub>out</sub> × N<sub>aux</sub>/N<sub>s</sub>. The divider is sized for V<sub>ref</sub> at V<sub>aux</sub>. The small-signal gain (N<sub>aux</sub>/N<sub>s</sub>) × R<sub>div</sub> = V<sub>ref</sub>/V<sub>out</sub> — turns ratio cancels.
                    </div>
                    <div style={{fontSize:9.5,color:col.warn,marginTop:4,lineHeight:1.4}}>
                      ⚠ Cross-regulation: aux outputs track V<sub>out</sub> only at DC. Load-dependent voltage drops in the transformer will cause output regulation error under varying load.
                    </div>
                  </>}
                </div>}

                {/* Compensator */}
                {cardVis.comp && <div style={card}>
                  <div style={cardTitle}>COMPENSATOR</div>
                  <div style={{display:"flex",gap:3,marginBottom:4}}>
                    <SmBtn label="TYPE-II" active={compType==="type2"} onClick={()=>{setCompType("type2");setFrozenComp(null);}} />
                    <SmBtn label="TYPE-III" active={compType==="type3"} onClick={()=>{setCompType("type3");setFrozenComp(null);}} />
                  </div>
                  <div style={{display:"flex",gap:3,marginBottom:4}}>
                    <SmBtn label="AUTO" active={compMode==="auto"} onClick={()=>{setCompMode("auto");calcComp();}} />
                    <SmBtn label="MANUAL" active={compMode==="manual"} onClick={handleManual} />
                  </div>
                  {compType==="type2" && pinfo.mode==="CCM" && plantMode!=="gmps" && topology!=="flyback" && pinfo.Ti0 < 3 && (
                    <div style={{fontSize:9,color:col.err,background:"#1c0f0f",border:`1px solid ${col.err}`,borderRadius:3,padding:"3px 5px",marginBottom:4}}>
                      Ti(0)={sf(pinfo.Ti0,2)} — VM-like. Use Type-III.
                    </div>
                  )}
                  {compMode==="auto" && <>
                    <NumInput label="fc target" unit="kHz" val={fcTarget} onVal={setFcTarget} />
                    <button onClick={handleRecalc} style={{width:"100%",background:col.accent,color:"#fff",border:"none",borderRadius:3,padding:"5px 0",fontSize:10,cursor:"pointer",fontWeight:700,marginBottom:4}}>RECALCULATE</button>
                    {frozenComp && <div style={{fontSize:9.5,color:col.dim,fontFamily:"monospace",lineHeight:1.5}}>
                      {frozenComp.type==="type2" ? <>fz={fmtFreq(frozenComp.fz_c)} fp={fmtFreq(frozenComp.fp_c)}<br/>fi={fmtFreq(frozenComp.fi)}</>
                       : <>fz1={fmtFreq(frozenComp.fz1)} fz2={fmtFreq(frozenComp.fz2)}<br/>fp1={fmtFreq(frozenComp.fp1)} fp2={fmtFreq(frozenComp.fp2)}<br/>fi={fmtFreq(frozenComp.fi)}</>}
                    </div>}
                  </>}
                  {compMode==="manual" && compType==="type2" && <>
                    <NumInput label="fz" unit="Hz" val={manFzC} onVal={setManFzC} />
                    <NumInput label="fp" unit="Hz" val={manFpC} onVal={setManFpC} />
                    <NumInput label="fi" unit="Hz" val={manFi} onVal={setManFi} />
                    <button onClick={handleApplyManual} style={{width:"100%",background:"#7c3aed",color:"#fff",border:"none",borderRadius:3,padding:"5px 0",fontSize:10,cursor:"pointer",fontWeight:700,marginBottom:4}}>APPLY</button>
                  </>}
                  {compMode==="manual" && compType==="type3" && <>
                    <NumInput label="fz1" unit="Hz" val={manFz1} onVal={setManFz1} />
                    <NumInput label="fz2" unit="Hz" val={manFz2} onVal={setManFz2} />
                    <NumInput label="fp1" unit="Hz" val={manFp1} onVal={setManFp1} />
                    <NumInput label="fp2" unit="Hz" val={manFp2} onVal={setManFp2} />
                    <NumInput label="fi" unit="Hz" val={manFi3} onVal={setManFi3} />
                    <button onClick={handleApplyManual} style={{width:"100%",background:"#7c3aed",color:"#fff",border:"none",borderRadius:3,padding:"5px 0",fontSize:10,cursor:"pointer",fontWeight:700,marginBottom:4}}>APPLY</button>
                  </>}
                  <div style={{fontSize:9,color:col.dim,fontFamily:"monospace",lineHeight:1.4,marginTop:4,borderTop:`1px solid ${col.border}`,paddingTop:4}}>
                    {compComponents.topology === "ota" ? <>R<sub>C</sub>={fmtSI(compComponents.RCOMP,"R")} C<sub>C</sub>={fmtSI(compComponents.CCOMP,"F")} C<sub>HF</sub>={fmtSI(compComponents.CHF,"F")}</>
                    : compComponents.type==="type3" ? <>R1={fmtSI(compComponents.R1,"R")} R2={fmtSI(compComponents.R2,"R")} R3={fmtSI(compComponents.R3,"R")}<br/>C1={fmtSI(compComponents.C1,"F")} C2={fmtSI(compComponents.C2,"F")} C3={fmtSI(compComponents.C3,"F")}</>
                    : <>R1={fmtSI(compComponents.R1,"R")} R2={fmtSI(compComponents.R2,"R")}<br/>C1={fmtSI(compComponents.C1,"F")} C2={fmtSI(compComponents.C2,"F")}</>}
                  </div>
                </div>}

                {/* Load Transient & Input Filter */}
                <div style={{...card,padding:"8px 12px"}}>
                  <div style={{...cardTitle,fontSize:10}}>LOAD TRANSIENT</div>
                  <NumInput label="ΔI step" unit="A" val={deltaI} onVal={setDeltaI} />
                  <label style={{display:"flex",alignItems:"center",gap:5,cursor:"pointer",fontSize:10,color:col.dim,marginTop:4}}>
                    <input type="checkbox" checked={showInputFilter} onChange={e=>setShowInputFilter(e.target.checked)} />INPUT FILTER
                  </label>
                  {showInputFilter && <>
                    <NumInput label="Lin" unit="uH" val={lin} onVal={setLin} />
                    <NumInput label="Cin" unit="uF" val={cin} onVal={setCin} />
                    <NumInput label="Rd" unit="R" val={rd} onVal={setRd} />
                  </>}
                </div>

            </>);
          })()}
          </div>
        </div>

        {/* ─── RIGHT PANEL: Plots ─── */}
        <div style={{flex:1,display:"flex",flexDirection:"column",overflow:"hidden"}}>
          {/* Metrics bar */}
          <div style={{display:"flex",gap:6,padding:"6px 10px",flexWrap:"wrap",background:col.panel,borderBottom:`1px solid ${col.border}`}}>
            <MB label="fc" value={crossoverFreq>0?fmtFreq(crossoverFreq):"--"} sub={crossoverFreq>0?`${sf(fcRatio*100,1)}% fsw${fcTargetMiss>0.3?" ⚠MISS":""}`:"—"} status={fcS} />
            <MB label="PM" value={pm!==null?sf(pm,1)+"°":"--"} sub="≥45°" status={pmS} />
            <MB label="GM" value={gm!==null?sf(gm,1)+"dB":"∞"} sub={gm===null?"—":"≥10dB"} status={gmS} />
            <MB label="D" value={sf(Dactive*100,1)+"%"} sub={`${pinfo.mode} mc=${sf(pinfo.mc,2)}`} status={pinfo.factor<=0?"err":pinfo.factor<0.15?"warn":"ok"} />
            {pinfo.mode==="CCM" && <MB label="Qp" value={pinfo.Qp>50?"∞":sf(pinfo.Qp,2)} sub={`factor=${sf(pinfo.factor,2)}`} status={pinfo.Qp>5?"warn":"ok"} />}
            {topology==="flyback" && pinfo.fz_rhp && <MB label="RHPZ" value={fmtFreq(pinfo.fz_rhp)} sub={`fc<${fmtFreq(pinfo.fz_rhp/5)}`} status={crossoverFreq>pinfo.fz_rhp/5?"err":"ok"} />}
            <MB label="Zout" value={pm!==null&&pm<0?"N/A":fmtSI(zout_dc,"R")} sub={pm!==null&&pm<0?"loop unstable":`PSRR=${sf(psrr_dc,1)}dB`} status={pm!==null&&pm<0?"err":zout_dc*1e3>specZoutMax?"warn":"ok"} />
            {eaType!=="ideal" && <MB label="EA φ" value={sf(eaPhaseLoss,1)+"°"} sub={eaInfo.noCout?`Aol=${sf(eaInfo.Aol_dB,0)}dB`:`GBW=${fmtFreq(eaInfo.GBW_Hz)}`} status={eaPhaseLoss>15?"err":eaPhaseLoss>8?"warn":"ok"} />}
          </div>

          {/* Tabs */}
          <div style={{display:"flex",gap:0,borderBottom:`1px solid ${col.border}`,background:col.panel}}>
            {tabs.map(t=>(
              <button key={t.id} onClick={()=>setActiveTab(t.id)} style={{
                background:activeTab===t.id?col.bg:"transparent",color:activeTab===t.id?col.bright:col.dim,
                border:"none",borderBottom:activeTab===t.id?`2px solid ${col.accent}`:"2px solid transparent",
                padding:"7px 14px",fontSize:11,cursor:"pointer",fontFamily:"inherit",fontWeight:600,letterSpacing:"0.04em",
              }}>{t.label}</button>
            ))}
            <div style={{marginLeft:"auto",display:"flex",alignItems:"center",gap:8,paddingRight:14}}>
              {[{k:"plant",c:col.plant,l:"Plant",s:showPlant,f:setShowPlant},{k:"comp",c:col.comp,l:"Comp",s:showComp,f:setShowComp},{k:"loop",c:col.loop,l:"Loop",s:showLoop,f:setShowLoop},{k:"sub",c:"#f472b6",l:"Sub-blocks",s:showSubBlocks,f:setShowSubBlocks}].map(t=>(
                <label key={t.k} style={{display:"flex",alignItems:"center",gap:3,cursor:"pointer",fontSize:10.5,color:t.s?t.c:col.dim}}>
                  <input type="checkbox" checked={t.s} onChange={e=>t.f(e.target.checked)} />{t.l}
                </label>
              ))}
            </div>
          </div>

          {/* Content */}
          <div style={{flex:1,overflowY:"auto",padding:"10px 14px"}}>

            {activeTab==="bode"&&(<div style={{display:"flex",flexDirection:"column",gap:6}}>
              <PanelBox title={`MAGNITUDE (dB) -- ${topology==="2sw_fwd"?"2SW FWD ":""}${pinfo.mode} @ Vin = ${vinActiveLabel}${isIsolated?` (Veff=${sf(vinEffActive,1)}V)`:""}, D = ${sf(Dactive*100,1)}%`}>
                <ResponsiveContainer width="100%" height={250}>
                  <LineChart data={bodeData} margin={{left:8,right:16,top:4,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="f" scale="log" domain={[10,2e6]} type="number" ticks={logTicks} tickFormatter={logTickFmt} stroke={col.dim} tick={{fontSize:10}} />
                    <YAxis domain={[-60,80]} stroke={col.dim} tick={{fontSize:10}} ticks={[-60,-40,-20,0,20,40,60,80]} />
                    <ReferenceLine y={0} stroke={col.dim} strokeDasharray="6 3" strokeWidth={1.5} />
                    {crossoverFreq>0&&<ReferenceLine x={crossoverFreq} stroke={col.loop} strokeDasharray="4 4" strokeOpacity={0.4} />}
                    <Tooltip content={<TT />} />
                    {showPlant&&<Line dataKey="plantMag" stroke={col.plant} dot={false} strokeWidth={1.5} isAnimationActive={false} />}
                    {showComp&&<Line dataKey="compMag" stroke={col.comp} dot={false} strokeWidth={1.5} isAnimationActive={false} />}
                    {showLoop&&<Line dataKey="loopMag" stroke={col.loop} dot={false} strokeWidth={2} isAnimationActive={false} />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="fmMag" stroke="#f472b6" dot={false} strokeWidth={1} strokeDasharray="4 3" isAnimationActive={false} name="Fm" />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="gidMag" stroke="#38bdf8" dot={false} strokeWidth={1.2} strokeDasharray="6 3" isAnimationActive={false} name="Gid" />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="gviMag" stroke="#fb923c" dot={false} strokeWidth={1.2} strokeDasharray="6 3" isAnimationActive={false} name="Gvi" />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="tiMag" stroke="#ec4899" dot={false} strokeWidth={2} isAnimationActive={false} name="Ti (inner)" />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="heMag" stroke="#94a3b8" dot={false} strokeWidth={1.2} strokeDasharray="3 2" isAnimationActive={false} name="He" />}
                    {showSubBlocks&&senseMode!=="simple"&&<Line dataKey="kcsMag" stroke="#facc15" dot={false} strokeWidth={1.5} strokeDasharray="5 3" isAnimationActive={false} name="Kcs(s)" />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="gvcClMag" stroke="#ef4444" dot={false} strokeWidth={1.2} strokeDasharray="2 2" isAnimationActive={false} name="Gvc(Ridley)" />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="vmMag" stroke="#4ade80" dot={false} strokeWidth={2} isAnimationActive={false} name="Fm·Gvd (VM)" />}
                    {eaType!=="ideal"&&<Line dataKey="eaMag" stroke="#e879f9" dot={false} strokeWidth={1.2} strokeDasharray="8 3" isAnimationActive={false} name="Gea(OL)" />}
                    {eaType!=="ideal"&&<Line dataKey="compIdealMag" stroke={col.comp} dot={false} strokeWidth={0.8} strokeDasharray="2 3" strokeOpacity={0.5} isAnimationActive={false} name="Gc(ideal)" />}
                  </LineChart>
                </ResponsiveContainer>
              </PanelBox>
              <PanelBox title="PHASE (deg)">
                <ResponsiveContainer width="100%" height={210}>
                  <LineChart data={phaseData} margin={{left:8,right:16,top:4,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="f" scale="log" domain={[10,2e6]} type="number" ticks={logTicks} tickFormatter={logTickFmt} stroke={col.dim} tick={{fontSize:10}} />
                    <YAxis domain={[-360,90]} stroke={col.dim} tick={{fontSize:10}} ticks={[-360,-270,-180,-90,0,90]} />
                    <ReferenceLine y={-180} stroke={col.err} strokeDasharray="6 3" strokeWidth={1.5} strokeOpacity={0.6} />
                    {crossoverFreq>0&&<ReferenceLine x={crossoverFreq} stroke={col.loop} strokeDasharray="4 4" strokeOpacity={0.4} />}
                    <Tooltip content={<TT_ph />} />
                    {showPlant&&<Line dataKey="plantPhase" stroke={col.plant} dot={false} strokeWidth={1.5} isAnimationActive={false} />}
                    {showComp&&<Line dataKey="compPhase" stroke={col.comp} dot={false} strokeWidth={1.5} isAnimationActive={false} />}
                    {showLoop&&<Line dataKey="loopPhase" stroke={col.loop} dot={false} strokeWidth={2} isAnimationActive={false} />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="gidPhase" stroke="#38bdf8" dot={false} strokeWidth={1.2} strokeDasharray="6 3" isAnimationActive={false} />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="gviPhase" stroke="#fb923c" dot={false} strokeWidth={1.2} strokeDasharray="6 3" isAnimationActive={false} />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="tiPhase" stroke="#ec4899" dot={false} strokeWidth={2} isAnimationActive={false} />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="hePhase" stroke="#94a3b8" dot={false} strokeWidth={1.2} strokeDasharray="3 2" isAnimationActive={false} />}
                    {showSubBlocks&&senseMode!=="simple"&&<Line dataKey="kcsPhase" stroke="#facc15" dot={false} strokeWidth={1.5} strokeDasharray="5 3" isAnimationActive={false} />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="gvcClPhase" stroke="#ef4444" dot={false} strokeWidth={1.2} strokeDasharray="2 2" isAnimationActive={false} />}
                    {showSubBlocks&&plantMode!=="gmps"&&<Line dataKey="vmPhase" stroke="#4ade80" dot={false} strokeWidth={2} isAnimationActive={false} />}
                    {eaType!=="ideal"&&<Line dataKey="eaPhase" stroke="#e879f9" dot={false} strokeWidth={1.2} strokeDasharray="8 3" isAnimationActive={false} />}
                    {eaType!=="ideal"&&<Line dataKey="compIdealPhase" stroke={col.comp} dot={false} strokeWidth={0.8} strokeDasharray="2 3" strokeOpacity={0.5} isAnimationActive={false} />}
                  </LineChart>
                </ResponsiveContainer>
              </PanelBox>
              {/* Sub-block legend */}
              {showSubBlocks&&pinfo.mode==="CCM"&&plantMode!=="gmps"&&(
                <div style={{background:col.panel,border:`1px solid ${col.border}`,borderRadius:5,padding:10}}>
                  <div style={{fontSize:10,color:col.dim,fontWeight:700,letterSpacing:"0.06em",marginBottom:6}}>
                    INNER LOOP SUB-BLOCKS -- Plant (teal) = closure model, Red dashed = Ridley closed-form
                  </div>
                  <div style={{display:"flex",gap:14,flexWrap:"wrap",fontSize:11,fontFamily:"monospace"}}>
                    <span><span style={{color:col.plant}}>━━</span> <span style={{color:col.plant}}>Plant</span><span style={{color:col.dim}}> = Fm·Gvd/(1+Ti) -- closure model (primary)</span></span>
                    <span><span style={{color:"#4ade80"}}>╌╌</span> <span style={{color:"#4ade80"}}>Fm·Gvd</span><span style={{color:col.dim}}> = pure VM plant (no current FB)</span></span>
                    <span><span style={{color:"#ef4444"}}>··</span> <span style={{color:"#ef4444"}}>Ridley</span><span style={{color:col.dim}}> = closed-form CM reference</span></span>
                    <span><span style={{color:"#ec4899"}}>━━</span> <span style={{color:"#ec4899"}}>Ti(s)</span><span style={{color:col.dim}}> inner loop gain = Fm·Gid·{senseMode!=="simple"?"Kcs":"Ri"} (physical, no He)</span></span>
                    <span><span style={{color:"#f472b6",opacity:0.7}}>╌╌</span> <span style={{color:"#f472b6"}}>Fm</span><span style={{color:col.dim}}> = {sf(Fm_val,3)} ({sf(Fm_dB,1)} dB)</span></span>
                    <span><span style={{color:"#38bdf8"}}>╌╌</span> <span style={{color:"#38bdf8"}}>Gid(s)</span><span style={{color:col.dim}}> duty→iL</span></span>
                    <span><span style={{color:"#fb923c"}}>╌╌</span> <span style={{color:"#fb923c"}}>Gvi(s)</span><span style={{color:col.dim}}> iL→vo</span></span>
                    <span><span style={{color:"#94a3b8"}}>╌╌</span> <span style={{color:"#94a3b8"}}>He(s)</span><span style={{color:col.dim}}> sampling</span></span>
                    {senseMode!=="simple"&&<span><span style={{color:"#facc15"}}>╌╌</span> <span style={{color:"#facc15"}}>Kcs(s)</span><span style={{color:col.dim}}> {senseMode==="ct"?"CT high-pass":"shunt"} ({sf(ri_eff,4)} V/A midband)</span></span>}
                  </div>
                  <div style={{marginTop:8,fontSize:11,color:col.text,background:col.bg,border:`1px solid ${col.border}`,borderRadius:4,padding:"6px 10px"}}>
                    {topology==="flyback" ? <>
                      Flyback uses the Basso/Richtek closed-form plant model: single output pole + RHPZ + He(s). The Ti(0) metric and VM/CM sub-block traces are from the buck decomposition and are <span style={{color:"#f59e0b",fontWeight:700}}>not applicable</span> to flyback.
                    </> : <>
                    <span style={{color:"#4ade80",fontWeight:700}}>Fm·Gvd (green dashed)</span> shows the LC double-pole resonance with zero current feedback -- this is what the plant would look like in pure voltage mode.
                    The <span style={{color:col.plant,fontWeight:700}}>teal Plant trace</span> is the closure model which damps this resonance via current feedback.
                    As Se increases, the Plant trace should approach the green VM trace.
                    Ti(0) = <span style={{color:pinfo.Ti0<3?"#f59e0b":"#22c55e",fontWeight:700}}>{sf(pinfo.Ti0,1)}</span>
                    {pinfo.Ti0 < 1 && <span style={{color:"#ef4444"}}> -- plant is near voltage-mode. Use Type-III compensator.</span>}
                    {pinfo.Ti0 >= 1 && pinfo.Ti0 < 3 && <span style={{color:"#f59e0b"}}> -- transitional. LC resonance partially visible in plant.</span>}
                    {pinfo.Ti0 >= 3 && <span style={{color:"#22c55e"}}> -- current-mode. Plant and Ridley agree, VM trace diverges.</span>}
                    </>}
                  </div>
                </div>
              )}
              {showSubBlocks&&pinfo.mode==="DCM"&&plantMode!=="gmps"&&(
                <div style={{background:col.panel,border:`1px solid ${col.border}`,borderRadius:5,padding:10}}>
                  <div style={{fontSize:11,color:col.warn}}>
                    Sub-block decomposition not available in DCM -- inner current loop is not applicable.
                    DCM plant is a single-pole model (inductor resets each cycle).
                  </div>
                </div>
              )}
              <div style={{background:col.panel,border:`1px solid ${col.border}`,borderRadius:5,padding:10,display:"flex",gap:14,flexWrap:"wrap",fontSize:11,fontFamily:"monospace"}}>
                <span><span style={{color:col.bright,fontWeight:700}}>{pinfo.mode}</span></span>
                {pinfo.mode==="CCM" && <>
                  <span><span style={{color:col.dim}}>fp1=</span><span style={{color:col.plant}}>{fmtFreq(pinfo.fp1)}</span></span>
                  <span><span style={{color:col.dim}}>f0(LC)=</span><span style={{color:"#fb923c"}}>{fmtFreq(pinfo.f0_LC)}</span></span>
                  <span><span style={{color:col.dim}}>Ti(0)=</span><span style={{color:topology==="flyback"?col.dim:pinfo.Ti0<3?"#f59e0b":"#22c55e"}}>{topology==="flyback"?"N/A":sf(pinfo.Ti0,1)}{topology!=="flyback"&&pinfo.Ti0<3?" (VM-like)":""}</span></span>
                </>}
                {pinfo.mode==="DCM" && <>
                  <span><span style={{color:col.dim}}>fp(DCM)=</span><span style={{color:col.plant}}>{fmtFreq(pinfo.fp_dcm)}</span></span>
                  <span><span style={{color:col.dim}}>Io_crit=</span><span style={{color:col.warn}}>{fmtSI(pinfo.Io_crit,"A")}</span></span>
                </>}
                <span><span style={{color:col.dim}}>fz(ESR)=</span><span style={{color:col.plant}}>{fmtFreq(pinfo.fz_esr)}</span></span>
                {activeComp.type==="type2" && <>
                  <span><span style={{color:col.dim}}>fz(comp)=</span><span style={{color:col.comp}}>{fmtFreq(activeComp.fz_c)}</span></span>
                  <span><span style={{color:col.dim}}>fp(comp)=</span><span style={{color:col.comp}}>{fmtFreq(activeComp.fp_c)}</span></span>
                  <span><span style={{color:col.dim}}>fi=</span><span style={{color:col.comp}}>{fmtFreq(activeComp.fi)}</span></span>
                </>}
                {activeComp.type==="type3" && <>
                  <span><span style={{color:col.dim}}>fz1=</span><span style={{color:col.comp}}>{fmtFreq(activeComp.fz1)}</span></span>
                  <span><span style={{color:col.dim}}>fz2=</span><span style={{color:col.comp}}>{fmtFreq(activeComp.fz2)}</span></span>
                  <span><span style={{color:col.dim}}>fp1=</span><span style={{color:col.comp}}>{fmtFreq(activeComp.fp1)}</span></span>
                  <span><span style={{color:col.dim}}>fp2=</span><span style={{color:col.comp}}>{fmtFreq(activeComp.fp2)}</span></span>
                  <span><span style={{color:col.dim}}>fi=</span><span style={{color:col.comp}}>{fmtFreq(activeComp.fi)}</span></span>
                </>}
                <span><span style={{color:col.dim}}>Gvc(0)=</span><span style={{color:col.plant}}>{sf(pinfo.Gvc0_dB,1)} dB</span></span>
                {pinfo.mode==="CCM" && <span><span style={{color:col.dim}}>Fm=</span><span style={{color:"#f472b6"}}>{sf(Fm_val,3)} ({sf(Fm_dB,1)} dB)</span></span>}
                {eaType!=="ideal" && <>
                  <span><span style={{color:col.dim}}>EA:</span><span style={{color:"#e879f9"}}>{eaType==="ota"?"OTA":"OpAmp"} Aol={sf(eaInfo.Aol_dB,0)}dB GBW={fmtFreq(eaInfo.GBW_Hz)}</span></span>
                  <span><span style={{color:col.dim}}>PM erosion(EA+td)=</span><span style={{color:eaPhaseLoss>15?col.err:eaPhaseLoss>8?col.warn:"#e879f9"}}>{sf(eaPhaseLoss,1)}deg</span></span>
                  {csDelay>0 && <span><span style={{color:col.dim}}>td=</span><span style={{color:"#e879f9"}}>{csDelay}ns</span></span>}
                </>}
              </div>

              {/* ─── SPICE EXPORT ─── */}
              <div style={{display:"flex",gap:6,marginTop:8}}>
                {["ac","tran"].map(mode => (
                  <button key={mode} onClick={()=>{
                    try {
                      const ic = IC_LIBRARY.find(x=>x.id===selectedIC);
                      const eff = getCapBankEffective(capBank);
                      const netlist = generateSpiceNetlist({
                        vin: vinEffActive, vinMin: vinMin*n, vinMax: vinMax*n, vout, iout, fsw_hz: fsw*1e3, L: L*1e-6, vref,
                        ri: ri_eff, se: se*1e-3/1e-6, capBank, esr_eff: eff.ESReff, cout_eff: eff.Ceff,
                        comp: activeComp, compComponents, eaParams,
                        plantMode, gm_ps: gmps, sc_aus: scEnabled?scAus:0, sc_aus_he: scAus,
                        csDelay_ns: csDelay, compClampLow, compClampHigh,
                        fc: crossoverFreq, pm, gm_margin: gm,
                        ic, deltaI, stimRiseTime, rise1090, stimType, stimDeltaVin: stimDeltaVin*n,
                        simMode: mode, topology, n, Dmax: topology==="2sw_fwd"?0.50:topology==="flyback"?0.65:0.95,
                        xfmrNp, xfmrNs, xfmrLm, lmAffectsSn, optoGain, fp_opto, compGain,
                      });
                      const topoPrefix = topology==="2sw_fwd"?"2sw_fwd":topology==="flyback"?"flyback":"buck";
                      const fname = `${topoPrefix}_${vout}V_${iout}A_${fsw}kHz_${mode}.cir`;
                      try {
                        const blob = new Blob([netlist],{type:"text/plain"});
                        const url = URL.createObjectURL(blob);
                        const a = document.createElement("a"); a.href=url; a.download=fname;
                        document.body.appendChild(a); a.click(); document.body.removeChild(a);
                        URL.revokeObjectURL(url);
                      } catch { const w=window.open("","_blank"); if(w) w.document.write("<pre>"+netlist.replace(/</g,"&lt;")+"</pre>"); }
                    } catch(err) { console.error(err); }
                  }} style={{
                    flex:1,background:mode==="ac"?"#1e3a2f":"#1e2a3f",
                    color:mode==="ac"?"#86efac":"#93c5fd",
                    border:`1px solid ${mode==="ac"?"#22c55e":"#3b82f6"}`,
                    borderRadius:4,padding:"7px 0",fontSize:11,cursor:"pointer",fontWeight:700,letterSpacing:"0.04em",
                  }}>
                    ⚡ EXPORT .CIR ({mode==="ac"?"Bode":"Transient"})
                  </button>
                ))}
              </div>

              {/* ─── LOOP DESIGN ADVISOR ─── */}
              <div style={{background:col.panel,border:`1px solid ${col.border}`,borderRadius:6,padding:"12px 16px",marginTop:8}}>
                <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:advisorText?8:0}}>
                  <span style={{fontSize:12,fontWeight:700,color:col.bright,letterSpacing:"0.05em"}}>LOOP DESIGN ADVISOR</span>
                  <button onClick={async()=>{
                    const fc = crossoverFreq;
                    if (!fc || fc <= 0) { setAdvisorText("No crossover frequency — loop is not closing. Check compensator and plant gain."); return; }

                    // ── Compute phase budget (shared by both paths) ──
                    const pp_adv = {vin:vinEffActive,vout,iout,fsw_hz:fsw*1e3,L:L*1e-6,cout:getCapBankEffective(capBank).Ceff,esr:getCapBankEffective(capBank).ESReff,ri:ri_eff,se:se*1e-3/1e-6,vref,capBank,placement:sensePlacement,senseParams,plantMode,gm_ps:gmps,sc_aus:scEnabled?scAus:0,sc_aus_he:scAus,optoGain,fp_opto,lmAffectsSn,Lm_H:xfmrLm*1e-6,n:turnsRatio,Np:xfmrNp,Ns:xfmrNs,auxSecondaries,topology};
                    const Gp = evalPlant(fc, pp_adv);
                    const H_dc_v = evalFeedback(vref,vout)*(optoGain||1);
                    const H_fc = evalOptoH(fc, H_dc_v, fp_opto||0);
                    const Gc_id = activeComp ? (activeComp.type==="type2" ? evalCompType2(fc,activeComp.fz_c,activeComp.fp_c,activeComp.fi) : evalCompType3(fc,activeComp.fz1,activeComp.fz2,activeComp.fp1,activeComp.fp2,activeComp.fi)) : C(1,0);
                    const Gc_ea_v = activeComp ? evalCompWithEA(fc, activeComp, eaParams) : C(1,0);
                    const Gd_v = evalDelay(fc, csDelay);
                    const ph_plant = cphase(Gp), ph_comp_ideal = cphase(Gc_id), ph_comp_ea = cphase(Gc_ea_v);
                    const ph_opto = isIsolated ? cphase(H_fc) : 0, ph_delay = cphase(Gd_v);
                    const ph_ea_loss = ph_comp_ideal - ph_comp_ea;
                    const ph_total = ph_plant + ph_comp_ea + ph_opto + ph_delay;
                    const pm_calc = 180 + ph_total;
                    const ph_fp1 = -Math.atan(fc/pinfo.fp1)*180/Math.PI;
                    const ph_esr = pinfo.fz_esr ? Math.atan(fc/pinfo.fz_esr)*180/Math.PI : 0;
                    const ph_rhp = pinfo.fz_rhp ? -Math.atan(fc/pinfo.fz_rhp)*180/Math.PI : 0;
                    const fn_he = fsw*1e3/Math.PI, norm_he = fc/fn_he;
                    const ph_he = pinfo.Qp < 100 ? -Math.atan2(norm_he/pinfo.Qp, 1-norm_he*norm_he)*180/Math.PI : 0;

                    // ── Build local analysis (always available) ──
                    const buildLocal = (prefix) => {
                      const contributors = [
                        {name:"Output pole (fp1="+fmtFreq(pinfo.fp1)+")", phase:ph_fp1},
                        {name:"ESR zero (fz="+fmtFreq(pinfo.fz_esr)+")", phase:ph_esr},
                        ...(pinfo.fz_rhp ? [{name:"RHPZ (fz="+fmtFreq(pinfo.fz_rhp)+")", phase:ph_rhp}] : []),
                        {name:"He sampling (Qp="+sf(pinfo.Qp,2)+", fn="+fmtFreq(fn_he)+")", phase:ph_he},
                        {name:"Compensator ("+compType+(compMode==="auto"?" auto":"")+")", phase:ph_comp_ideal},
                        ...(ph_ea_loss > 0.5 ? [{name:"EA finite BW (GBW="+eaGBW+"MHz)", phase:-ph_ea_loss}] : []),
                        ...(isIsolated && Math.abs(ph_opto) > 0.5 ? [{name:"Opto pole (fp="+fmtFreq(fp_opto)+")", phase:ph_opto}] : []),
                        ...(Math.abs(ph_delay) > 0.1 ? [{name:"CS delay ("+csDelay+"ns)", phase:ph_delay}] : []),
                      ].sort((a,b) => a.phase - b.phase);
                      const lines = [];
                      if (prefix) lines.push(prefix, "");
                      lines.push("PHASE BUDGET AT fc = "+fmtFreq(fc)+" (PM = "+sf(pm_calc,1)+"\u00B0)");
                      lines.push("\u2500".repeat(56));
                      lines.push("Contributor".padEnd(38)+"Phase");
                      lines.push("\u2500".repeat(56));
                      contributors.forEach(c => lines.push(c.name.padEnd(38)+((c.phase>=0?"+":"")+sf(c.phase,1)+"\u00B0").padStart(8)));
                      lines.push("\u2500".repeat(56));
                      lines.push("Total phase at fc".padEnd(38)+(sf(ph_total,1)+"\u00B0").padStart(8));
                      lines.push("Phase Margin (180\u00B0 + total)".padEnd(38)+(sf(pm_calc,1)+"\u00B0").padStart(8));
                      lines.push("");
                      const killers = contributors.filter(c=>c.phase<-3&&!c.name.startsWith("Compensator")).sort((a,b)=>a.phase-b.phase).slice(0,3);
                      if (killers.length>0) { lines.push("TOP PHASE KILLERS:"); killers.forEach((k,i)=>lines.push("  #"+(i+1)+" "+k.name+": "+sf(k.phase,1)+"\u00B0")); lines.push(""); }
                      if (pm_calc>=45) lines.push("STATUS: Loop is stable with adequate margin.");
                      else if (pm_calc>=30) lines.push("STATUS: Marginal. PM="+sf(pm_calc,1)+"\u00B0 \u2014 target \u226545\u00B0. Loop will ring.");
                      else if (pm_calc>=0) lines.push("STATUS: Poor stability. PM="+sf(pm_calc,1)+"\u00B0 \u2014 oscillation likely under variation.");
                      else lines.push("STATUS: UNSTABLE. PM="+sf(pm_calc,1)+"\u00B0 \u2014 loop will oscillate.");
                      lines.push(""); lines.push("DESIGN OPTIONS:");
                      let o=1;
                      if (fc>pinfo.fp1*5) { lines.push("  "+o+". Lower fc from "+fmtFreq(fc)+" to ~"+fmtFreq(Math.max(pinfo.fp1*3,1000))); lines.push("     Reduces phase lag from all sources. Trade-off: slower transient."); o++; }
                      if (isIsolated&&fp_opto>0&&fp_opto<fc*3) { const cs=Math.max(0.1,optoCopto*fp_opto/(fc*5)); const fpn=1/(TWO_PI*optoRpullup*1e3*cs*1e-9); const imp=Math.abs(ph_opto)-Math.abs(-Math.atan(fc/fpn)*180/Math.PI); lines.push("  "+o+". Reduce Copto: "+optoCopto+"nF \u2192 ~"+sf(cs,1)+"nF (moves fp_opto to "+fmtFreq(fpn)+")"); lines.push("     Recovers ~"+sf(imp,0)+"\u00B0. Trade-off: more HF noise."); o++; }
                      if (compType==="type2") { lines.push("  "+o+". Switch to Type-III (+40-60\u00B0 phase boost from extra zero)"); lines.push("     Trade-off: 3R+3C network vs 2R+2C."); o++; }
                      if (ph_ea_loss>8) { lines.push("  "+o+". Higher-GBW EA (current "+eaGBW+"MHz adds "+sf(ph_ea_loss,1)+"\u00B0 loss)"); lines.push("     Trade-off: may need different IC."); o++; }
                      if (pinfo.mc>1.5&&pinfo.Qp<0.5) { lines.push("  "+o+". Reduce Se (mc="+sf(pinfo.mc,2)+" is high)"); lines.push("     Trade-off: subharmonic risk if factor\u21920."); o++; }
                      if (pinfo.fz_rhp&&fc>pinfo.fz_rhp/5) { lines.push("  "+o+". fc exceeds RHPZ/5 limit \u2014 reduce to <"+fmtFreq(pinfo.fz_rhp/5)); o++; }
                      if (isIsolated&&optoGain>2) { lines.push("  "+o+". Reduce opto gain (CTR or Rpullup) \u2014 autoplacer adjusts fi to match"); lines.push("     In MANUAL mode lowers fc directly. Trade-off: higher Zout."); o++; }
                      if (o===1) lines.push("  No specific recommendations \u2014 loop looks good.");
                      return lines.join("\n");
                    };

                    // ── Try API first, fall back to local ──
                    setAdvisorText("Analyzing..."); setAdvisorLoading(true);
                    const stateStr = [
                      `${topology} flyback | ${plantMode} | Vin:${vinMin}-${vinMax}V Vout:${vout}V Iout:${iout}A fsw:${fsw}kHz`,
                      isIsolated?`Np=${xfmrNp} Ns=${xfmrNs} n=${sf(turnsRatio,4)} Lm=${xfmrLm}uH`:`L=${L}uH`,
                      `Ri=${sf(ri_eff,4)} Se=${se}mV/us mc=${sf(pinfo.mc,3)} Qp=${sf(pinfo.Qp,2)}`,
                      `IC:${IC_LIBRARY.find(x=>x.id===selectedIC)?.name||"Custom"} EA:${eaType} Aol=${eaAol}dB GBW=${eaGBW}MHz`,
                      isIsolated?(fbMode==="primary"?`Primary-side FB: H_dc=${sf(vref/vout,4)} (no opto pole)`:`Opto: CTR=${optoCTR} Rpu=${optoRpullup}kR Copto=${optoCopto}nF fp_opto=${fp_opto>0?fmtFreq(fp_opto):"inf"}`):"",
                      `D=${sf(pinfo.D*100,1)}% fp1=${fmtFreq(pinfo.fp1)} fz_esr=${fmtFreq(pinfo.fz_esr)}${pinfo.fz_rhp?" RHPZ="+fmtFreq(pinfo.fz_rhp):""}`,
                      `Comp:${compType} fc_target=${fcTarget}kHz`,
                      `fc=${fmtFreq(fc)} PM=${pm!==null?sf(pm,1):"--"}deg GM=${gm!==null?sf(gm,1):"inf"}dB`,
                      `Phase budget @ fc: plant=${sf(ph_plant,1)} comp+EA=${sf(ph_comp_ea,1)} opto=${sf(ph_opto,1)} delay=${sf(ph_delay,1)} total=${sf(ph_total,1)} PM=${sf(pm_calc,1)}`,
                      `EA phase loss: ${sf(ph_ea_loss,1)}deg | He phase: ${sf(ph_he,1)}deg | RHPZ phase: ${sf(ph_rhp,1)}deg`,
                      ...(val.errors||[]).map(e=>"ERR: "+e), ...(val.warnings||[]).map(w=>"WARN: "+w),
                    ].filter(Boolean).join("\n");

                    // ── Try API first (5s hard timeout via Promise.race) ──
                    let apiSuccess = false;
                    try {
                      const apiPromise = fetch("https://api.anthropic.com/v1/messages", {
                        method:"POST",
                        headers:{"Content-Type":"application/json"},
                        body:JSON.stringify({
                          model:"claude-sonnet-4-20250514", max_tokens:1000,
                          system:"You are a power electronics control loop design advisor for PCMC converters. Given the tool state and phase budget, provide:\n1. A concise diagnosis of what is limiting the phase margin\n2. The top 3 phase contributors and their impact\n3. 2-4 specific design changes with expected PM improvement in degrees and trade-offs\nBe specific with numbers from the data. Keep under 350 words. Plain text only.",
                          messages:[{role:"user",content:stateStr}],
                        }),
                      }).then(async r => {
                        if (!r.ok) return null;
                        const d = await r.json();
                        const txt = d.content?.filter(b=>b.type==="text").map(b=>b.text).join("\n")||"";
                        return txt.length > 20 ? txt : null;
                      });
                      const timeoutPromise = new Promise(r => setTimeout(()=>r(null), 5000));
                      const result = await Promise.race([apiPromise, timeoutPromise]);
                      if (result) {
                        setAdvisorText("[AI Advisor]\n\n"+result);
                        apiSuccess = true;
                      }
                    } catch(e) { /* network/CORS/sandbox error → fall through */ }

                    // ── Local fallback ──
                    if (!apiSuccess) {
                      setAdvisorText(buildLocal("[Local Analysis]"));
                    }
                    setAdvisorLoading(false);
                  }} disabled={advisorLoading} style={{
                    background:advisorLoading?"#1e293b":"#7c3aed",color:advisorLoading?"#64748b":"#fff",
                    border:"none",borderRadius:4,padding:"6px 16px",fontSize:11,cursor:advisorLoading?"wait":"pointer",
                    fontWeight:700,letterSpacing:"0.04em",fontFamily:"inherit",
                  }}>
                    {advisorLoading ? "Analyzing..." : "\uD83D\uDD0D RUN ADVISOR"}
                  </button>
                </div>
                {advisorText && <div style={{
                  background:"#0d1117",border:`1px solid #7c3aed44`,borderRadius:4,padding:"10px 14px",
                  fontSize:11,color:"#c9d1d9",fontFamily:"'JetBrains Mono','Fira Code',monospace",
                  lineHeight:1.7,whiteSpace:"pre-wrap",maxHeight:400,overflowY:"auto",
                }}>{advisorText}</div>}
              </div>

            </div>)}

            {activeTab==="step"&&(<div style={{display:"flex",flexDirection:"column",gap:8}}>
              {/* Stimulus controls */}
              <div style={{display:"flex",gap:10,alignItems:"center",paddingLeft:48,fontSize:11,flexWrap:"wrap"}}>
                <label style={{color:col.dim}}>Stimulus:
                  <select value={stimType} onChange={e=>setStimType(e.target.value)} style={{...sInput,width:100,marginLeft:4}}>
                    <option value="load_step">Load Step</option>
                    <option value="line_step">Line Step</option>
                  </select>
                </label>
                {stimType==="load_step" && <label style={{color:col.dim}}>ΔI <input type="number" value={deltaI} onChange={e=>setDeltaI(+e.target.value)} style={{...sInput,width:50,marginLeft:2}} /> A</label>}
                {stimType==="line_step" && <label style={{color:col.dim}}>ΔVin <input type="number" value={stimDeltaVin} onChange={e=>setStimDeltaVin(+e.target.value)} style={{...sInput,width:50,marginLeft:2}} /> V</label>}
                <label style={{color:col.dim}}>Rise <input type="number" value={stimRiseTime} onChange={e=>setStimRiseTime(+e.target.value)} style={{...sInput,width:70,marginLeft:2}} /> µs</label>
                <label style={{color:rise1090?col.accent:col.dim,cursor:"pointer",fontSize:10}}>
                  <input type="checkbox" checked={rise1090} onChange={e=>setRise1090(e.target.checked)} style={{marginRight:3}} />
                  10–90%
                </label>
                {/* Engine toggle: Analytical vs SPICE (gm_ps only) */}
                {plantMode === "gmps" && (
                  <span style={{display:"inline-flex",gap:0,marginLeft:4,border:`1px solid ${col.border}`,borderRadius:4,overflow:"hidden"}}>
                    <button onClick={()=>setSimEngine("analytical")} style={{
                      padding:"2px 8px",fontSize:9,fontWeight:600,cursor:"pointer",border:"none",
                      background:simEngine==="analytical"?col.accent:"transparent",
                      color:simEngine==="analytical"?"#000":col.dim,
                    }}>Analytical</button>
                    <button onClick={()=>setSimEngine("spice")} disabled={!ngspiceReady&&!ngspiceLoading} style={{
                      padding:"2px 8px",fontSize:9,fontWeight:600,cursor:"pointer",border:"none",borderLeft:`1px solid ${col.border}`,
                      background:simEngine==="spice"?col.accent:"transparent",
                      color:simEngine==="spice"?"#000":ngspiceReady?col.dim:"#555",
                    }}>{ngspiceLoading?"Loading…":spiceRunning?"⏳ Simulating…":"SPICE"}</button>
                  </span>
                )}
                {ngspiceError && <span style={{color:col.err,fontSize:9}}>⚠ {ngspiceError}</span>}
                {tdSim && (tdSim.clamped || tdSim.dcm_entered || tdSim.slewLimited_src || tdSim.slewLimited_snk) && (
                  <span style={{color:col.warn,fontWeight:700,fontSize:10}}>
                    {tdSim.clamped && "⚠ COMP clamped "}
                    {tdSim.dcm_entered && "⚠ DCM entered "}
                    {tdSim.slewLimited_src && "⚡ Src slew limited "}
                    {tdSim.slewLimited_snk && "⚡ Snk slew limited"}
                  </span>
                )}
              </div>

              {tdSim && tdSim.data.length > 0 ? (()=>{
              // ------ Dynamic X-axis for output voltage (full recovery view) ------
              const tMax = tdSim.data[tdSim.data.length - 1].t_us;
              const useMs = tMax > 2000;
              const tDomain = [0, useMs ? Math.ceil(tMax / 1000) * 1000 : tMax];
              // Generate ~6–8 clean ticks
              const nTicks = 7;
              const rawStep = tMax / nTicks;
              const mag = Math.pow(10, Math.floor(Math.log10(rawStep)));
              const norm = rawStep / mag;
              const niceStep = norm < 1.5 ? 1 : norm < 3.5 ? 2 : norm < 7.5 ? 5 : 10;
              const step = niceStep * mag;
              const tTicks = [];
              for (let t = 0; t <= tMax * 1.01; t += step) tTicks.push(parseFloat(t.toFixed(3)));
              const tFmt = (v) => useMs ? (v / 1000).toFixed(v >= 1000 && v % 1000 === 0 ? 0 : 1) : v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(0) : v.toFixed(1);
              const tUnit = useMs ? "ms" : "us";

              // ------ Zoomed X-axis for iL and vcomp/D (fast dynamics) ------
              // Zoom to show transient action: use 5/(2π·fc) × 8 or settling time, whichever is longer
              const tauFC = _fc > 0 ? 1 / (TWO_PI * _fc) * 1e6 : 200; // µs
              let tSettle_iL = tauFC * 8; // default: 8 crossover time constants
              // Refine: scan data for when iL has settled within 5% of final
              const iLfinal = tdSim.data[tdSim.data.length - 1].iL_A;
              const iL0 = tdSim.data[0].iL_A;
              const iLrange = Math.abs(iLfinal - iL0);
              if (iLrange > 0.001) {
                for (let i = tdSim.data.length - 1; i >= 0; i--) {
                  if (Math.abs(tdSim.data[i].iL_A - iLfinal) > iLrange * 0.05) {
                    tSettle_iL = Math.max(tSettle_iL, tdSim.data[Math.min(i + 5, tdSim.data.length - 1)].t_us * 1.5);
                    break;
                  }
                }
              }
              const tZoom = Math.min(Math.max(tSettle_iL, stimRiseTime * 10, 200), tMax * 0.4);
              const useMsZ = tZoom > 2000;
              // Round to nice boundary
              const tDomainZmax = useMsZ ? Math.ceil(tZoom / 500) * 500 : tZoom > 500 ? Math.ceil(tZoom / 100) * 100 : Math.ceil(tZoom / 50) * 50;
              const tDomainZ = [0, tDomainZmax];
              // Generate 5 clean ticks (fewer = readable in small chart)
              const nTicksZ = 5;
              const rawStepZ = tDomainZmax / nTicksZ;
              const magZ = Math.pow(10, Math.floor(Math.log10(Math.max(rawStepZ, 1))));
              const normZ = rawStepZ / magZ;
              const niceStepZ = normZ < 1.5 ? 1 : normZ < 3.5 ? 2 : normZ < 7.5 ? 5 : 10;
              const stepZ = niceStepZ * magZ;
              const tTicksZ = [];
              for (let t = 0; t <= tDomainZmax * 1.01; t += stepZ) tTicksZ.push(parseFloat(t.toFixed(3)));
              const tFmtZ = (v) => useMsZ ? (v / 1000).toFixed(v >= 1000 && v % 1000 === 0 ? 0 : 1) : v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(0) : v.toFixed(1);
              const tUnitZ = useMsZ ? "ms" : "µs";

              return <>
              {/* Vout deviation */}
              <PanelBox title={`OUTPUT VOLTAGE${tdSim.engine==="spice"?" (SPICE)":""} -- ${stimType==="load_step"?`ΔI = ${deltaI} A`:`ΔVin = ${stimDeltaVin} V`} | Rise = ${stimRiseTime} µs${rise1090?" (10-90%)":""} @ Vin = ${vinActiveLabel}`}>
                <ResponsiveContainer width="100%" height={220}>
                  <LineChart data={tdSim.data} margin={{left:8,right:16,top:8,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="t_us" type="number" domain={tDomain} ticks={tTicks} stroke={col.dim} tick={{fontSize:10}} tickFormatter={tFmt}>
                      <Label value={`Time (${tUnit})`} position="bottom" offset={-2} style={{fill:col.dim,fontSize:9}} />
                    </XAxis>
                    <YAxis stroke={col.dim} tick={{fontSize:10}}
                      label={{value:"ΔVout (mV)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                    <ReferenceLine y={0} stroke={col.dim} strokeDasharray="6 3" />
                    <ReferenceLine y={vout*20} stroke={col.ok} strokeDasharray="4 4" strokeOpacity={0.3} label={{value:"+2%",fill:col.ok,fontSize:8}} />
                    <ReferenceLine y={-vout*20} stroke={col.ok} strokeDasharray="4 4" strokeOpacity={0.3} label={{value:"-2%",fill:col.ok,fontSize:8}} />
                    <Tooltip formatter={(v,name)=>[parseFloat(v).toFixed(2)+(name==="vout_mv"?" mV":name==="iout_A"?" A":""),name==="vout_mv"?"ΔVout":"Iout"]}
                      labelFormatter={v=>`${parseFloat(v).toFixed(1)} us`} contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}} />
                    <Line dataKey="vout_mv" stroke={col.err} dot={false} strokeWidth={2} isAnimationActive={false} name="ΔVout" />
                  </LineChart>
                </ResponsiveContainer>
                <div style={{paddingLeft:48,fontSize:10.5,fontFamily:"monospace",color:col.dim}}>
                  Undershoot: <span style={{color:col.err}}>{sf(tdSim.peakUndershoot,1)} mV</span> | Overshoot: <span style={{color:col.warn}}>{sf(tdSim.peakOvershoot,1)} mV</span>
                  {tdSim.settlingTime !== null ? ` | Settling (2%): ${sf(tdSim.settlingTime,1)} us` : " | Settling: < 1 step"}
                  {` | Sim: ${tFmt(tMax)} ${tUnit}`}
                  {tdSim.engine==="spice" && spiceElapsed && <span style={{color:col.accent}}>{` | SPICE ${spiceElapsed}ms`}</span>}
                </div>
              </PanelBox>

              {/* Inductor current + stimulus */}
              <PanelBox title={`INDUCTOR CURRENT & STIMULUS${tdSim.engine==="spice"?" (SPICE)":""}  (0–${tFmtZ(tDomainZ[1])} ${tUnitZ})`}>
                <ResponsiveContainer width="100%" height={180}>
                  <LineChart data={tdSim.data} margin={{left:8,right:16,top:8,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="t_us" type="number" domain={tDomainZ} ticks={tTicksZ} stroke={col.dim} tick={{fontSize:10}} tickFormatter={tFmtZ} />
                    <YAxis yAxisId="l" stroke={col.dim} tick={{fontSize:10}}
                      label={{value:"iL (A)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                    {stimType==="line_step" && <YAxis yAxisId="r" orientation="right" stroke={col.dim} tick={{fontSize:10}}
                      label={{value:"Vin (V)",angle:90,position:"insideRight",style:{fill:col.dim,fontSize:9}}} />}
                    <Tooltip contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}}
                      labelFormatter={v=>`${parseFloat(v).toFixed(1)} us`} />
                    <Line yAxisId="l" dataKey="iL_A" stroke={col.plant} dot={false} strokeWidth={2} isAnimationActive={false} name="iL (A)" />
                    {stimType==="load_step" && <Line yAxisId="l" dataKey="iout_A" stroke={col.dim} dot={false} strokeWidth={1.5} strokeDasharray="6 3" isAnimationActive={false} name="Iout (A)" />}
                    {stimType==="line_step" && <Line yAxisId="r" dataKey="vin_V" stroke={col.warn} dot={false} strokeWidth={1.5} strokeDasharray="6 3" isAnimationActive={false} name="Vin (V)" />}
                    <Legend wrapperStyle={{fontSize:10,color:col.dim}} />
                  </LineChart>
                </ResponsiveContainer>
              </PanelBox>

              {/* COMP voltage & Duty cycle */}
              <PanelBox title={`COMP VOLTAGE & DUTY CYCLE${tdSim.engine==="spice"?" (SPICE)":""}  (0–${tFmtZ(tDomainZ[1])} ${tUnitZ})`}>
                <ResponsiveContainer width="100%" height={180}>
                  <LineChart data={tdSim.data} margin={{left:8,right:16,top:8,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="t_us" type="number" domain={tDomainZ} ticks={tTicksZ} stroke={col.dim} tick={{fontSize:10}} tickFormatter={tFmtZ} />
                    <YAxis yAxisId="l" stroke={col.dim} tick={{fontSize:10}}
                      label={{value:"VCOMP (V)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                    <YAxis yAxisId="r" orientation="right" stroke={col.dim} tick={{fontSize:10}}
                      label={{value:"D (%)",angle:90,position:"insideRight",style:{fill:col.dim,fontSize:9}}} />
                    <Tooltip contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}}
                      labelFormatter={v=>`${parseFloat(v).toFixed(1)} us`}
                      formatter={(v,name,props)=>{
                        if(name==="VCOMP (V)") {
                          const s = props.payload?.slew;
                          const tag = s===1?" ⚡SRC LIM":s===-1?" ⚡SNK LIM":"";
                          return [parseFloat(v).toFixed(4)+" V"+tag, name];
                        }
                        return [parseFloat(v).toFixed(1)+"%", name];
                      }} />
                    <ReferenceLine yAxisId="l" y={compClampHigh} stroke={col.err} strokeDasharray="4 4" strokeOpacity={0.4} label={{value:"clamp↑",fill:col.err,fontSize:8}} />
                    <ReferenceLine yAxisId="l" y={compClampLow} stroke={col.err} strokeDasharray="4 4" strokeOpacity={0.4} label={{value:"clamp↓",fill:col.err,fontSize:8}} />
                    <Line yAxisId="l" dataKey="vcomp_V" stroke={"#e879f9"} dot={false} strokeWidth={2} isAnimationActive={false} name="VCOMP (V)" />
                    <Line yAxisId="r" dataKey="D_pct" stroke={col.comp} dot={false} strokeWidth={1.5} strokeDasharray="6 3" isAnimationActive={false} name="D (%)" />
                    <Legend wrapperStyle={{fontSize:10,color:col.dim}} />
                  </LineChart>
                </ResponsiveContainer>
                <div style={{paddingLeft:48,fontSize:10.5,fontFamily:"monospace",color:col.dim}}>
                  {tdSim.slewLimit_src_Vms != null ? (<>
                    Slew limit: <span style={{color:"#e879f9"}}>↑{sf(tdSim.slewLimit_src_Vms,1)} V/ms</span> (src)
                    {" / "}<span style={{color:"#e879f9"}}>↓{sf(tdSim.slewLimit_snk_Vms,1)} V/ms</span> (snk)
                    {" | "}Peak: ↑{sf(tdSim.peakSlewUp_Vms,1)} ↓{sf(tdSim.peakSlewDn_Vms,1)} V/ms
                    {tdSim.slewLimited_src && <span style={{color:col.warn,fontWeight:700}}>{" "}⚡ SOURCE LIMITED</span>}
                    {tdSim.slewLimited_snk && <span style={{color:col.warn,fontWeight:700}}>{" "}⚡ SINK LIMITED</span>}
                    {!tdSim.slewLimited_src && !tdSim.slewLimited_snk && <span style={{color:col.ok}}>{" "}✓ not slew limited</span>}
                  </>) : (
                    <span style={{color:col.dim}}>EA slew: unlimited (ideal or not configured)</span>
                  )}
                  {(tdSim.slewLimited_src || tdSim.slewLimited_snk) && <div style={{fontSize:9.5,color:col.dim,marginTop:2,lineHeight:1.4}}>
                    How to see it: VCOMP shows a straight-line ramp (constant dV/dt = {tdSim.slewLimited_src ? sf(tdSim.slewLimit_src_Vms,0) : sf(tdSim.slewLimit_snk_Vms,0)} V/ms) instead of an exponential curve during the initial transient. This limits how fast the duty cycle can respond → slower recovery, deeper droop.
                  </div>}
                </div>
              </PanelBox>
              </>})() : (
                <div style={{padding:20,textAlign:"center",color:col.dim,fontSize:12}}>
                  {simEngine==="spice" && spiceRunning ? (
                    <span style={{color:col.accent}}>⏳ Running SPICE simulation...</span>
                  ) : simEngine==="spice" && ngspiceLoading ? (
                    <span style={{color:col.warn}}>Loading NGspice WASM engine (~20MB)...</span>
                  ) : simEngine==="spice" && !ngspiceReady ? (
                    <span style={{color:col.warn}}>NGspice engine not available{ngspiceError ? `: ${ngspiceError}` : ""}</span>
                  ) : (
                    <>Simulation requires valid loop (crossover {">"} 0). Check plant/comp settings.</>
                  )}
                </div>
              )}
            </div>)}

            {activeTab==="sweep"&&(<div style={{display:"flex",flexDirection:"column",gap:10}}>
              {sweepData.hasUnstableRegion && (
                <div style={{background:"#1c0f0f",border:`1px solid ${col.err}`,borderRadius:5,padding:"8px 12px",fontSize:11,color:"#fca5a5"}}>
                  <span style={{fontWeight:700,color:col.err}}>SUBHARMONIC INSTABILITY REGION </span>
                  at low Vin where D {">"} 50% with Se = {se} mV/us. Factor = mc·D'-0.5 goes ≤ 0.
                  {se === 0 && <span style={{color:"#fde68a"}}> Add slope compensation (Se {">"} 0) to stabilize.</span>}
                </div>
              )}
              <div style={{background:"#0c1520",border:`1px solid ${col.border}`,borderRadius:5,padding:"8px 12px",fontSize:11,color:col.text,lineHeight:1.6}}>
                <span style={{fontWeight:700,color:col.bright}}>HOW TO READ: </span>
                <span style={{color:col.loop}}>PM (deg)</span> = phase margin at first 0 dB crossover.
                {" "}<span style={{color:col.comp}}>GM (dB)</span> = gain margin at -180deg phase crossing.
                {" "}<span style={{fontWeight:600,color:col.err}}>Negative GM</span> means the loop gain re-crosses 0 dB above -180deg phase -- this is <span style={{color:col.err}}>conditional instability</span> from He(s) peaking near fsw/2.
                Even if PM looks fine at the intended crossover, negative GM means the system oscillates at a higher frequency.
              </div>
              <PanelBox title={`LINE REGULATION -- Vin ${vinMin}–${vinMax} V @ Iout = ${iout} A (comp frozen)`}>
                <ResponsiveContainer width="100%" height={260}>
                  <LineChart data={sweepData.lineData} margin={{left:8,right:16,top:8,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="vin" stroke={col.dim} tick={{fontSize:10}}><Label value="Vin (V)" position="bottom" offset={-2} style={{fill:col.dim,fontSize:10}} /></XAxis>
                    <YAxis yAxisId="l" domain={[0,120]} stroke={col.dim} tick={{fontSize:10}} ticks={[0,15,30,45,60,75,90]}
                      label={{value:"PM (deg) / fc (kHz)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                    <YAxis yAxisId="r" orientation="right" domain={[-30,50]} stroke={col.dim} tick={{fontSize:10}} ticks={[-20,-10,0,10,20,30,40,50]}
                      label={{value:"GM (dB)",angle:90,position:"insideRight",style:{fill:col.dim,fontSize:9}}} />
                    {sweepData.hasUnstableRegion && sweepData.vinCrit && sweepData.vinMinPlot && <ReferenceArea yAxisId="l" x1={sweepData.vinMinPlot} x2={sweepData.vinCrit} fill={col.err} fillOpacity={0.08} />}
                    <ReferenceLine yAxisId="l" y={45} stroke={col.ok} strokeDasharray="4 4" strokeOpacity={0.4} />
                    <ReferenceLine yAxisId="r" y={0} stroke={col.err} strokeDasharray="4 4" strokeOpacity={0.5} />
                    {sweepData.vinCrit && sweepData.hasUnstableRegion && <ReferenceLine yAxisId="l" x={sweepData.vinCrit} stroke={col.err} strokeDasharray="3 3" strokeOpacity={0.6} />}
                    <ReferenceLine yAxisId="l" x={vinNom} stroke={col.bright} strokeDasharray="8 4" strokeOpacity={0.3} />
                    {vinCorner !== "nom" && <ReferenceLine yAxisId="l" x={vinActive} stroke={col.accent} strokeDasharray="4 2" strokeOpacity={0.6} />}
                    <Tooltip contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}}
                      formatter={(v,name)=>{
                        if(v==null) return ["--",name];
                        const val = typeof v==="number"?v.toFixed(1):v;
                        if(name==="GM (dB)" && typeof v==="number" && v<0) return [val+" ⚠ UNSTABLE",name];
                        return [val,name];
                      }}
                      labelFormatter={v=>{const D=(vout/v*100); return `Vin=${v}V (D=${D.toFixed(1)}%)`;}} />
                    <Line yAxisId="l" dataKey="pm" stroke={col.loop} dot={false} strokeWidth={2} name="PM (deg)" isAnimationActive={false} connectNulls={false} />
                    <Line yAxisId="l" dataKey="fc_kHz" stroke={col.plant} dot={false} strokeWidth={1.5} name="fc (kHz)" isAnimationActive={false} connectNulls={false} />
                    <Line yAxisId="r" dataKey="gm" stroke={col.comp} dot={false} strokeWidth={1.5} name="GM (dB)" isAnimationActive={false} connectNulls={false} />
                    <Legend wrapperStyle={{fontSize:10,color:col.dim}} />
                  </LineChart>
                </ResponsiveContainer>
                <div style={{paddingLeft:48,fontSize:10.5,color:col.dim,fontFamily:"monospace",marginTop:2}}>
                  Vin range: {vinMin}–{vinMax} V, Nom = {vinNom.toFixed(1)} V (dashed white). D: {(Dmin*100).toFixed(0)}%–{(Dmax*100).toFixed(0)}%.
                  {sweepData.hasUnstableRegion && <span style={{color:"#fca5a5"}}> Red zone: mc·D'-0.5 ≤ 0.</span>}
                  {" "}Red dashed = GM 0 dB line. GM below 0 = conditionally unstable.
                </div>
              </PanelBox>
              <PanelBox title={`LOAD REGULATION -- Iout sweep @ Vin = ${vinActiveLabel} (comp frozen)`}>
                <ResponsiveContainer width="100%" height={260}>
                  <LineChart data={sweepData.loadSweepData} margin={{left:8,right:16,top:8,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="iout" stroke={col.dim} tick={{fontSize:10}}><Label value="Iout (A)" position="bottom" offset={-2} style={{fill:col.dim,fontSize:10}} /></XAxis>
                    <YAxis yAxisId="l" domain={[0,120]} stroke={col.dim} tick={{fontSize:10}} ticks={[0,15,30,45,60,75,90]}
                      label={{value:"PM (deg) / fc (kHz)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                    <YAxis yAxisId="r" orientation="right" domain={[-30,50]} stroke={col.dim} tick={{fontSize:10}} ticks={[-20,-10,0,10,20,30,40,50]}
                      label={{value:"GM (dB)",angle:90,position:"insideRight",style:{fill:col.dim,fontSize:9}}} />
                    <ReferenceLine yAxisId="l" y={45} stroke={col.ok} strokeDasharray="4 4" strokeOpacity={0.4} />
                    <ReferenceLine yAxisId="r" y={0} stroke={col.err} strokeDasharray="4 4" strokeOpacity={0.5} />
                    <ReferenceLine yAxisId="l" x={iout} stroke={col.bright} strokeDasharray="8 4" strokeOpacity={0.3} />
                    <Tooltip contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}}
                      formatter={(v,name)=>{
                        if(v==null) return ["--",name];
                        const val = typeof v==="number"?v.toFixed(1):v;
                        if(name==="GM (dB)" && typeof v==="number" && v<0) return [val+" ⚠ UNSTABLE",name];
                        return [val,name];
                      }}
                      labelFormatter={v=>`Iout=${v}A (Rload=${(vout/v).toFixed(2)}R)`} />
                    <Line yAxisId="l" dataKey="pm" stroke={col.loop} dot={false} strokeWidth={2} name="PM (deg)" isAnimationActive={false} connectNulls={false} />
                    <Line yAxisId="l" dataKey="fc_kHz" stroke={col.plant} dot={false} strokeWidth={1.5} name="fc (kHz)" isAnimationActive={false} connectNulls={false} />
                    <Line yAxisId="r" dataKey="gm" stroke={col.comp} dot={false} strokeWidth={1.5} name="GM (dB)" isAnimationActive={false} connectNulls={false} />
                    <Legend wrapperStyle={{fontSize:10,color:col.dim}} />
                  </LineChart>
                </ResponsiveContainer>
                <div style={{paddingLeft:48,fontSize:10.5,color:col.dim,fontFamily:"monospace",marginTop:2}}>
                  Nominal Iout = {iout} A (dashed white). fp1 moves with load -- lighter load → lower fp1, lower fc.
                </div>
              </PanelBox>
            </div>)}

            {activeTab==="zcap"&&(
              <PanelBox title="OUTPUT CAP BANK IMPEDANCE">
                <div style={{fontSize:11,color:col.dim,paddingLeft:48,marginBottom:6}}>
                  |Z| vs frequency for each cap slot and the parallel combination. Rload shown for reference.
                  {antiRes && <span style={{color:col.warn}}> ⚠ Anti-resonance peak at {fmtFreq(antiRes.freq)}: |Z| = {(antiRes.impedance*1e3).toFixed(1)} mR ({antiRes.ratio.toFixed(1)}x minimum)</span>}
                </div>
                <ResponsiveContainer width="100%" height={320}>
                  <LineChart data={zcapData} margin={{left:8,right:16,top:4,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="f" scale="log" domain={[100,5e7]} type="number" ticks={[100,1e3,1e4,1e5,1e6,1e7]} tickFormatter={logTickFmt} stroke={col.dim} tick={{fontSize:10}}>
                      <Label value="Frequency" position="bottom" offset={-2} style={{fill:col.dim,fontSize:10}} />
                    </XAxis>
                    <YAxis domain={[-80,40]} stroke={col.dim} tick={{fontSize:10}}
                      label={{value:"|Z| (dBR)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                    <Tooltip contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}}
                      labelFormatter={v=>`f = ${fmtFreq(v)}`}
                      formatter={(v,name)=>[v?.toFixed(1)+" dBR",name]} />
                    <ReferenceLine y={dB(vout/Math.max(iout,0.001))} stroke={col.warn} strokeDasharray="8 4" strokeOpacity={0.4} label={{value:"Rload",fill:col.warn,fontSize:9}} />
                    <Line dataKey="bank_dB" stroke={col.bright} dot={false} strokeWidth={2.5} isAnimationActive={false} name="Bank total" />
                    {capSlots.map((s,i) => (
                      <Line key={i} dataKey={`cap${i}_dB`} stroke={["#06d6c2","#fb923c","#a78bfa"][i%3]} dot={false} strokeWidth={1.2} strokeDasharray="6 3" isAnimationActive={false} name={`Cap ${i+1} (${s.type.replace("_"," ")})`} />
                    ))}
                    <Legend wrapperStyle={{fontSize:10,color:col.dim}} />
                  </LineChart>
                </ResponsiveContainer>
                <div style={{paddingLeft:48,fontSize:10.5,color:col.dim,fontFamily:"monospace",marginTop:4}}>
                  Ceff = {fmtSI(capEff.Ceff,"F")} | ESReff = {fmtSI(capEff.ESReff,"R")} | fp1 ≈ {fmtFreq(pinfo.fp1)} | fz(ESR) ≈ {fmtFreq(pinfo.fz_esr)}
                  {capBank.some(b=>b.esl_H>0) && ` | SRFs: ${capBank.filter(b=>b.esl_H>0&&b.cap_F>0).map((b,i)=>`Cap${i+1}=${fmtFreq(1/(TWO_PI*Math.sqrt(b.esl_H/b.qty*b.cap_F*b.qty)))}`).join(", ")}`}
                </div>
              </PanelBox>
            )}

            {activeTab==="audio"&&(
              <div style={{display:"flex",flexDirection:"column",gap:8}}>
                {/* Spec limit inputs */}
                <div style={{display:"flex",gap:12,alignItems:"center",paddingLeft:48,fontSize:11}}>
                  <label style={{color:col.dim}}>Max Zout(DC)
                    <input type="number" value={specZoutMax} onChange={e=>setSpecZoutMax(+e.target.value)} style={{...sInput,width:60,marginLeft:4}} /> mR
                  </label>
                  <label style={{color:col.dim}}>Max Gvg(CL)
                    <input type="number" value={specGvgMax} onChange={e=>setSpecGvgMax(+e.target.value)} style={{...sInput,width:60,marginLeft:4}} /> dB
                  </label>
                </div>

                {/* Zout plot */}
                <PanelBox title={`OUTPUT IMPEDANCE Zout(f) -- ${pinfo.mode} @ Vin = ${vinActiveLabel}`}>
                  <div style={{fontSize:11,color:col.dim,paddingLeft:48,marginBottom:4}}>
                    Open-loop Zout = {plantMode==="gmps"?"Rload || Zcap":"Gvi/(1+Ti)"} | Closed-loop = Zout_open / (1+T)
                    <span style={{marginLeft:12,color:col.bright}}>Zout(DC) = {zout_dc<1?sf(zout_dc*1e3,1)+" mR":sf(zout_dc,3)+" R"}</span>
                    {zout_fc!==null && <span style={{marginLeft:8,color:col.bright}}>@ fc = {zout_fc<1?sf(zout_fc*1e3,1)+" mR":sf(zout_fc,3)+" R"}</span>}
                  </div>
                  <ResponsiveContainer width="100%" height={250}>
                    <LineChart data={audioData} margin={{left:8,right:16,top:4,bottom:16}}>
                      <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                      <XAxis dataKey="f" scale="log" domain={[1,2e6]} type="number" ticks={[1,10,100,1e3,1e4,1e5,1e6]} tickFormatter={logTickFmt} stroke={col.dim} tick={{fontSize:10}}>
                        <Label value="Frequency (Hz)" position="bottom" offset={0} style={{fill:col.dim,fontSize:9}} />
                      </XAxis>
                      <YAxis domain={[-80,20]} ticks={[-80,-60,-40,-20,0,20]} stroke={col.dim} tick={{fontSize:10}}
                        label={{value:"|Z| (dBR)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                      <Tooltip contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}}
                        labelFormatter={v=>`f = ${fmtFreq(v)}`}
                        formatter={(v,name)=>[v?.toFixed(1)+" dBR",name]} />
                      {specZoutMax>0 && <ReferenceLine y={dB(specZoutMax*1e-3)} stroke={col.err} strokeDasharray="6 3" strokeOpacity={0.5} label={{value:`spec ≤ ${specZoutMax} mR`,fill:col.err,fontSize:10,position:"right"}} />}
                      {crossoverFreq>0&&<ReferenceLine x={crossoverFreq} stroke={col.loop} strokeDasharray="4 4" strokeOpacity={0.3} label={{value:"fc",fill:col.loop,fontSize:9,position:"top"}} />}
                      <Line dataKey="zo_open_dB" stroke={col.plant} dot={false} strokeWidth={1.5} strokeDasharray="6 3" isAnimationActive={false} name="Zout open-loop" />
                      <Line dataKey="zo_closed_dB" stroke={col.bright} dot={false} strokeWidth={2.5} isAnimationActive={false} name="Zout closed-loop" />
                      <Legend wrapperStyle={{fontSize:10,color:col.dim,paddingTop:6}} />
                    </LineChart>
                  </ResponsiveContainer>
                </PanelBox>

                {/* Gvg plot */}
                <PanelBox title={`AUDIO SUSCEPTIBILITY Gvg(f) -- ${pinfo.mode} @ Vin = ${vinActiveLabel}`}>
                  <div style={{fontSize:11,color:col.dim,paddingLeft:48,marginBottom:4}}>
                    Line-to-output: Gvg = Vout/Vin disturbance transfer. Negative dB = attenuation (good).
                    <span style={{marginLeft:12,color:col.bright}}>Gvg_cl(DC) = {sf(dB(cmag(evalGvg_closed(1, {vin:vinEffActive,vout,iout,fsw_hz:fsw*1e3,L:L*1e-6,cout:getCapBankEffective(capBank).Ceff,esr:getCapBankEffective(capBank).ESReff,ri:ri_eff,se:se*1e-3/1e-6,vref,capBank,placement:sensePlacement,senseParams,plantMode,gm_ps:gmps,sc_aus:scEnabled?scAus:0,sc_aus_he:scAus,optoGain,fp_opto,lmAffectsSn,Lm_H:xfmrLm*1e-6,n:turnsRatio,Np:xfmrNp,Ns:xfmrNs,auxSecondaries}, activeComp, eaParams, csDelay))),1)} dB</span>
                    {lmAffectsSn && xfmrLm > 0 && <><br/><span style={{color:"#93c5fd",fontSize:10}}>Feedforward kf = (1−2D)/(2·fsw·Lm) active — magnetizing slope modifies audio susceptibility (Chen/Huang 2007)</span></>}
                  </div>
                  <ResponsiveContainer width="100%" height={250}>
                    <LineChart data={audioData} margin={{left:8,right:16,top:4,bottom:16}}>
                      <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                      <XAxis dataKey="f" scale="log" domain={[1,2e6]} type="number" ticks={[1,10,100,1e3,1e4,1e5,1e6]} tickFormatter={logTickFmt} stroke={col.dim} tick={{fontSize:10}}>
                        <Label value="Frequency (Hz)" position="bottom" offset={0} style={{fill:col.dim,fontSize:9}} />
                      </XAxis>
                      <YAxis domain={[-100,20]} ticks={[-100,-80,-60,-40,-20,0,20]} stroke={col.dim} tick={{fontSize:10}}
                        label={{value:"Gvg (dB)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                      <Tooltip contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}}
                        labelFormatter={v=>`f = ${fmtFreq(v)}`}
                        formatter={(v,name)=>[v?.toFixed(1)+" dB",name]} />
                      {specGvgMax!==0 && <ReferenceLine y={specGvgMax} stroke={col.err} strokeDasharray="6 3" strokeOpacity={0.5} label={{value:`spec ≤ ${specGvgMax} dB`,fill:col.err,fontSize:10,position:"right"}} />}
                      <ReferenceLine y={0} stroke={col.dim} strokeDasharray="6 3" strokeWidth={1} />
                      {crossoverFreq>0&&<ReferenceLine x={crossoverFreq} stroke={col.loop} strokeDasharray="4 4" strokeOpacity={0.3} label={{value:"fc",fill:col.loop,fontSize:9,position:"top"}} />}
                      <Line dataKey="gvg_open_dB" stroke={"#fb923c"} dot={false} strokeWidth={1.5} strokeDasharray="6 3" isAnimationActive={false} name="Gvg open-loop" />
                      <Line dataKey="gvg_closed_dB" stroke={"#f472b6"} dot={false} strokeWidth={2.5} isAnimationActive={false} name="Gvg closed-loop" />
                      <Legend wrapperStyle={{fontSize:10,color:col.dim,paddingTop:6}} />
                    </LineChart>
                  </ResponsiveContainer>
                </PanelBox>

                {/* PSRR plot */}
                <PanelBox title={`PSRR(f) = -20·log₁₀|Gvg_cl| -- ${pinfo.mode} @ Vin = ${vinActiveLabel}`}>
                  <div style={{fontSize:11,color:col.dim,paddingLeft:48,marginBottom:4}}>
                    Power Supply Rejection Ratio. Higher = better line rejection.
                    <span style={{marginLeft:12,color:col.bright}}>PSRR(DC) = {sf(psrr_dc,1)} dB</span>
                  </div>
                  <ResponsiveContainer width="100%" height={220}>
                    <LineChart data={audioData} margin={{left:8,right:16,top:4,bottom:16}}>
                      <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                      <XAxis dataKey="f" scale="log" domain={[1,2e6]} type="number" ticks={[1,10,100,1e3,1e4,1e5,1e6]} tickFormatter={logTickFmt} stroke={col.dim} tick={{fontSize:10}}>
                        <Label value="Frequency (Hz)" position="bottom" offset={0} style={{fill:col.dim,fontSize:9}} />
                      </XAxis>
                      <YAxis domain={[-20,140]} ticks={[-20,0,20,40,60,80,100,120,140]} stroke={col.dim} tick={{fontSize:10}}
                        label={{value:"PSRR (dB)",angle:-90,position:"insideLeft",style:{fill:col.dim,fontSize:9}}} />
                      <Tooltip contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}}
                        labelFormatter={v=>`f = ${fmtFreq(v)}`}
                        formatter={(v,name)=>[v?.toFixed(1)+" dB",name]} />
                      {crossoverFreq>0&&<ReferenceLine x={crossoverFreq} stroke={col.loop} strokeDasharray="4 4" strokeOpacity={0.3} label={{value:"fc",fill:col.loop,fontSize:9,position:"top"}} />}
                      <Line dataKey="psrr_dB" stroke={"#22c55e"} dot={false} strokeWidth={2.5} isAnimationActive={false} name="PSRR" />
                      <Legend wrapperStyle={{fontSize:10,color:col.dim,paddingTop:6}} />
                    </LineChart>
                  </ResponsiveContainer>
                </PanelBox>

                {/* Summary box */}
                <div style={{background:col.panel,border:`1px solid ${col.border}`,borderRadius:5,padding:12}}>
                  <div style={{fontSize:12,fontWeight:700,color:col.bright,marginBottom:8}}>AUDIO SUSCEPTIBILITY SUMMARY</div>
                  <div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr",gap:8,fontSize:11}}>
                    <div style={{background:col.bg,borderRadius:4,padding:8,border:`1px solid ${col.border}`}}>
                      <div style={{color:col.dim,fontSize:10,marginBottom:2}}>Zout(DC) closed-loop</div>
                      <div style={{color:zout_dc*1e3>specZoutMax?col.warn:col.ok,fontWeight:700,fontFamily:"monospace"}}>{zout_dc<1?sf(zout_dc*1e3,2)+" mR":sf(zout_dc,3)+" R"}</div>
                      <div style={{color:col.dim,fontSize:9,marginTop:2}}>spec ≤ {specZoutMax} mR</div>
                    </div>
                    <div style={{background:col.bg,borderRadius:4,padding:8,border:`1px solid ${col.border}`}}>
                      <div style={{color:col.dim,fontSize:10,marginBottom:2}}>PSRR(DC)</div>
                      <div style={{color:psrr_dc<Math.abs(specGvgMax)?col.warn:col.ok,fontWeight:700,fontFamily:"monospace"}}>{sf(psrr_dc,1)} dB</div>
                      <div style={{color:col.dim,fontSize:9,marginTop:2}}>spec ≥ {Math.abs(specGvgMax)} dB</div>
                    </div>
                    <div style={{background:col.bg,borderRadius:4,padding:8,border:`1px solid ${col.border}`}}>
                      <div style={{color:col.dim,fontSize:10,marginBottom:2}}>Zout @ fc</div>
                      <div style={{color:col.bright,fontWeight:700,fontFamily:"monospace"}}>{zout_fc!==null?(zout_fc<1?sf(zout_fc*1e3,1)+" mR":sf(zout_fc,2)+" R"):"--"}</div>
                      <div style={{color:col.dim,fontSize:9,marginTop:2}}>peaks near crossover</div>
                    </div>
                  </div>
                  <div style={{marginTop:8,fontSize:10.5,color:col.dim,lineHeight:1.6}}>
                    {plantMode==="gmps"
                      ? "gm_ps mode: Zout_open ≈ Rload || Zcap (current source). Gvg_ol = D·Zout/(1+gm_ps·Zout·He). Loop gain T(s) improves rejection below fc."
                      : "Standard mode: Zout_open = Gvi/(1+Ti). Inner current loop provides partial rejection. Outer voltage loop T(s) provides further rejection below fc."
                    }
                    {" "}Above fc the loop gain drops below unity and Zout rises toward the open-loop value.
                    For cascaded converters, verify Zout(downstream) {"<"} Zin(upstream) at all frequencies (Middlebrook criterion).
                  </div>
                </div>
              </div>
            )}

            {activeTab==="filter"&&inputFilterData&&(
              <PanelBox title="INPUT FILTER Zout vs CONVERTER Zin (MIDDLEBROOK)">
                <div style={{fontSize:11,color:col.dim,paddingLeft:48,marginBottom:6}}>
                  |Zout_filter| must stay below |Zin_converter| = {converterZin(vinActive,vout,iout).toFixed(2)} R everywhere
                </div>
                <ResponsiveContainer width="100%" height={280}>
                  <LineChart data={inputFilterData} margin={{left:8,right:16,top:4,bottom:4}}>
                    <CartesianGrid stroke={col.grid} strokeDasharray="3 3" />
                    <XAxis dataKey="f" scale="log" domain={[10,2e6]} type="number" ticks={logTicks} tickFormatter={logTickFmt} stroke={col.dim} tick={{fontSize:10}} />
                    <YAxis domain={[-40,40]} stroke={col.dim} tick={{fontSize:10}} />
                    <Tooltip formatter={v=>[parseFloat(v).toFixed(1)+" dB"]} labelFormatter={v=>`f=${fmtFreq(v)}`} contentStyle={{background:"#151e2bee",border:`1px solid ${col.border}`,fontSize:11}} />
                    <Line dataKey="zout_dB" stroke={col.plant} dot={false} strokeWidth={2} name="|Zout filter|" isAnimationActive={false} />
                    <Line dataKey="zin_dB" stroke={col.err} dot={false} strokeWidth={2} strokeDasharray="6 3" name="|Zin converter|" isAnimationActive={false} />
                    <Legend wrapperStyle={{fontSize:10,color:col.dim}} />
                  </LineChart>
                </ResponsiveContainer>
              </PanelBox>
            )}

            {activeTab==="diag"&&(
              <div style={{display:"flex",flexDirection:"column",gap:8}}>
                {val.errors.length>0&&<DiagBox title="ERRORS" items={val.errors} color={col.err} bg="#1c0f0f" />}
                {val.warnings.length>0&&<DiagBox title="WARNINGS" items={val.warnings} color={col.warn} bg="#1c1708" />}
                {val.info.length>0&&<DiagBox title="DESIGN INFO" items={val.info} color={col.info} bg="#0c1520" />}
                <div style={{background:col.panel,border:`1px solid ${col.border}`,borderRadius:5,padding:12}}>
                  <div style={{fontSize:12,fontWeight:700,color:col.bright,marginBottom:8}}>MODEL ASSUMPTIONS</div>
                  {[
                    `Bode/transient analysis at: Vin=${vinActive}V (${vinCorner})${isIsolated?` → Veff=${sf(vinEffActive,2)}V`:""}, Vout=${vout}V, Iout=${iout}A`,
                    `Vin range: ${vinMin}–${vinMax}V → D: ${(Dmin*100).toFixed(1)}–${(Dmax*100).toFixed(1)}%. Vout ±${voutTol}%: ${voutMin.toFixed(3)}–${voutMax.toFixed(3)}V`,
                    `State-space averaged ${topology==="2sw_fwd"?"two-switch forward (buck-equivalent, n="+sf(turnsRatio,3)+")":topology==="flyback"?"flyback (Basso/Richtek closed-form, n="+sf(turnsRatio,3)+", RHPZ="+fmtFreq(pinfo.fz_rhp||0)+")":"buck"} ${pinfo.mode} with He/Ridley sampled-data double-pole at fsw/π`,
                    `Peak current-mode control · ${sensePlacement.replace("_"," ")} sense${isIsolated?` (${isoSenseSide} side)`:""} · Se = ${se} mV/us${senseMode==="shunt"?` · Rshunt=${rshunt} mR`:senseMode==="ct"?` · CT ${ctNs}:${ctNp} Rb=${ctRb}R`:""}${lmAffectsSn?` · Lm=${xfmrLm}µH (Sn includes mag ramp)`:""}`,
                    selectedIC!=="custom" ? `Controller IC: ${IC_LIBRARY.find(x=>x.id===selectedIC)?.name || selectedIC}` : null,
                    "Constant switching frequency (no jitter/spread-spectrum)",
                    "Output capacitor bank model (ESR + ESL per cap, parallel impedance)",
                    "Ideal switches (Rds(on)/Vf not in small-signal model)",
                    `Temp: ${TEMP_FACTORS[tempCorner].label} -- Lx${TEMP_FACTORS[tempCorner].ind}, cap derating per type (${capSlots.map(s => { const cd = getCapDerate(s.type, tempCorner); return `${s.type.replace("_"," ")}: ESRx${cd.esr} Cx${cd.cap}`; }).join("; ")})`,
                    eaType==="ideal" ? `${compType==="type2"?"Type-II":"Type-III"} comp -- no EA GBW or slew-rate limiting modeled`
                      : `${compType==="type2"?"Type-II":"Type-III"} comp with ${eaType==="ota"?"OTA":"Op-amp"} EA (${eaType==="ota"?`gm=${eaGm}uA/V`:`Aol=${eaAol}dB, GBW=${eaGBW}MHz`})`,
                    "Time-domain: linearized 2nd-order approx from fc and PM",
                    "Sweep uses frozen comp network -- does not re-optimize per point",
                  ].filter(Boolean).map((a,i)=><div key={i} style={{fontSize:11,color:col.text,paddingLeft:8,borderLeft:`2px solid ${col.dim}`,marginBottom:4}}>{a}</div>)}
                </div>
              </div>
            )}

            {activeTab==="eqns"&&(
              <TabErrorBoundary>
              <div style={{display:"flex",flexDirection:"column",gap:10}}>
                <CollapsiblePanel title="CONTROL LOOP BLOCK DIAGRAM" defaultOpen={true}>
                  <LoopBlockDiagram senseMode={senseMode} sensePlacement={sensePlacement} rshunt={rshunt} gampDC={gampDC} ri_eff={ri_eff} ctNs={ctNs} ctNp={ctNp} ctRb={ctRb} />
                </CollapsiblePanel>
                <EqnSection title="LOOP GAIN DECOMPOSITION" content={[
                  {eq:"T(s) = Gc(s) · Gvd(s) · H",desc:"Loop gain = compensator x plant (control-to-output) x feedback divider"},
                  {eq:"H = Vref / Vout",desc:"Resistive divider attenuation"},
                ]} refs={["TI SLVA301 -- Understanding and Applying Current-Mode Control Theory","TI SNVA555 -- Demystifying Type II and Type III Compensators"]} />

                <EqnSection title="RIDLEY CLOSED-FORM (reference model)" content={[
                  {eq:"Gvc(s) = (Rload/Ri) · (1+s/ωz_esr) / [(1+s/ωp1) · He(s)]",desc:"Ridley's control-to-output in CCM. Assumes inner current loop has high gain (Ti(0) ≫ 1). Shown as red dashed trace when Sub-blocks enabled."},
                  {eq:"fp1 = 1/(2π·Cout·Rload)",desc:"Dominant output pole -- moves with load"},
                  {eq:"fz_esr = 1/(2π·Cout·ESR)",desc:"ESR zero -- phase boost from capacitor parasitic resistance"},
                  {eq:"He(s) = 1 + s/(Qp·ωn) + (s/ωn)²",desc:"Sampled-data double-pole from current-loop sampling"},
                  {eq:"ωn = 2π·fsw/π  →  fn = fsw/π",desc:"Natural frequency of the He double-pole"},
                  {eq:"Qp = 1/(π·(mc·D' - 0.5))",desc:"Quality factor -- peaking near fsw/2 when Qp is high. Peak CM only (high-side or inductor sense placement)."},
                ]} refs={[
                  "R.B. Ridley -- A New, Continuous-Time Model for Current-Mode Control (IEEE TPEL, 1991)",
                  "R.B. Ridley -- A More Accurate Current-Mode Control Model (Ridley Engineering)",
                  "TI SNVA555 -- Demystifying Type II and Type III Compensators",
                ]} />

                {/* ====== DERIVATION ====== */}
                <CollapsiblePanel title="HOW THE INNER CURRENT LOOP IS ABSORBED INTO Gvc(s) — AND WHERE Fm LIVES">
                  <div style={{fontSize:11.5,color:"#8899aa",lineHeight:1.7,marginBottom:12}}>
                    The block diagram shows 5 inner-loop blocks (Fm, Gid, Gvi, Ri, He). But the Ridley model computes
                    Gvc(s) as a single closed-form expression. This section shows exactly how each block maps into the code,
                    and why the modulator gain Fm doesn't appear as a multiplicative constant in the DC gain.
                  </div>

                  {/* Step 1: Individual blocks */}
                  <div style={{fontSize:11,color:"#06d6c2",fontWeight:700,marginBottom:6}}>STEP 1: THE INDIVIDUAL SUB-BLOCKS</div>
                  {[
                    {eq:"Fm = fsw / (Sn · mc)  =  fsw / ((Vin-Vout)/L · Ri · mc)",desc:"Modulator gain: duty perturbation per volt of control signal. Units: 1/V → duty/V.  CODE: getFm() function."},
                    {eq:"Gid(s) = Vin / (sL + Zo(s))",desc:"Duty-to-inductor-current. At DC: Gid(0) = Vin/Rload.  CODE: evalGid() function."},
                    {eq:"Gvi(s) = Zo(s) = Rload ‖ (1/sCout + ESR)",desc:"Inductor-current-to-output-voltage (output impedance). At DC: Gvi(0) = Rload.  CODE: evalGvi() function."},
                    {eq:"He(s) = 1 + s/(Qp·ωn) + (s/ωn)²",desc:"Sampled-data correction. He(0) = 1 at DC. Adds double-pole at fsw/π.  CODE: evalHe() function."},
                  ].map((c,i)=>(
                    <div key={i} style={{marginBottom:8}}>
                      <div style={{fontFamily:"'JetBrains Mono',monospace",fontSize:12,color:"#06d6c2",background:"#0b0f14",borderRadius:3,padding:"5px 10px",border:"1px solid #1c2736",marginBottom:2,overflowX:"auto",whiteSpace:"nowrap"}}>{c.eq}</div>
                      <div style={{fontSize:10.5,color:"#8899aa",paddingLeft:4}}>{c.desc}</div>
                    </div>
                  ))}

                  {/* Step 2: Classical closure */}
                  <div style={{fontSize:11,color:"#f472b6",fontWeight:700,marginTop:14,marginBottom:6}}>STEP 2: CLASSICAL INNER LOOP CLOSURE (what Gvc(closure) computes)</div>
                  {[
                    {eq:"Ti(s) = Fm · Gid(s) · Ri",desc:"Physical inner current-loop gain. No He(s) -- He is Ridley's analytical correction, not part of the physical feedback. Pink trace on Bode when Sub-blocks enabled."},
                    {eq:"Gvc_closure(s) = Fm · Gid(s) · Gvi(s) / (1 + Ti(s))",desc:"Naively closing the inner loop with Black's formula.  CODE: evalGvcClosure() function. This is the red dashed trace."},
                    {eq:"At DC:  Gvc_closure(0) = Fm·Gid(0)·Gvi(0) / (1 + Ti(0))  =  Fm·(Vin/Rload)·Rload / (1 + Fm·(Vin/Rload)·Ri)",desc:"The DC gain depends on Fm and Ti(0). If Ti(0) ≫ 1, this → Rload/Ri. But Ti(0) is often NOT ≫ 1!"},
                  ].map((c,i)=>(
                    <div key={i} style={{marginBottom:8}}>
                      <div style={{fontFamily:"'JetBrains Mono',monospace",fontSize:12,color:"#f472b6",background:"#0b0f14",borderRadius:3,padding:"5px 10px",border:"1px solid #1c2736",marginBottom:2,overflowX:"auto",whiteSpace:"nowrap"}}>{c.eq}</div>
                      <div style={{fontSize:10.5,color:"#8899aa",paddingLeft:4}}>{c.desc}</div>
                    </div>
                  ))}

                  {/* Step 3: Why Ridley is different */}
                  <div style={{fontSize:11,color:"#f5a623",fontWeight:700,marginTop:14,marginBottom:6}}>STEP 3: WHY THE RIDLEY MODEL GIVES Gvc(0) = Rload/Ri EXACTLY</div>
                  <div style={{fontSize:11.5,color:"#8899aa",lineHeight:1.8,marginBottom:8}}>
                    The Ridley model does NOT derive Gvc(s) by naively closing a classical feedback loop. Instead, it uses
                    sampled-data analysis of the peak-detection process. The physical reasoning is:
                  </div>
                  {[
                    {eq:"Peak current-mode comparator:  Ri · iL_peak = vc",desc:"Every switching cycle, the comparator forces the peak inductor current to equal vc/Ri. This is a cycle-by-cycle constraint, not a continuous-time feedback loop."},
                    {eq:"Average inductor current:  iL_avg ≈ vc/Ri - ΔiL/2",desc:"The average current is the peak minus half the ripple. The ripple correction is small-signal and frequency-dependent."},
                    {eq:"At DC (f → 0):  iL_avg = vc/Ri  (ripple correction → 0)",desc:"At DC the peak-to-average correction vanishes. The current-mode controller EXACTLY forces iL = vc/Ri regardless of Fm, because the inductor integrates any error away cycle-by-cycle."},
                    {eq:"Therefore:  vo = iL · Rload = (vc/Ri) · Rload  →  Gvc(0) = Rload/Ri",desc:"The DC gain is set by Ohm's law and the sense resistor. Fm doesn't appear because the integrating inductor provides infinite DC loop gain through the sample-and-hold mechanism."},
                  ].map((c,i)=>(
                    <div key={i} style={{marginBottom:8}}>
                      <div style={{fontFamily:"'JetBrains Mono',monospace",fontSize:12,color:"#f5a623",background:"#0b0f14",borderRadius:3,padding:"5px 10px",border:"1px solid #1c2736",marginBottom:2,overflowX:"auto",whiteSpace:"nowrap"}}>{c.eq}</div>
                      <div style={{fontSize:10.5,color:"#8899aa",paddingLeft:4}}>{c.desc}</div>
                    </div>
                  ))}

                  {/* Step 4: Where Fm actually enters */}
                  <div style={{fontSize:11,color:"#a78bfa",fontWeight:700,marginTop:14,marginBottom:6}}>STEP 4: WHERE Fm ENTERS THE CLOSURE MODEL (PRIMARY)</div>
                  <div style={{fontSize:11.5,color:"#8899aa",lineHeight:1.8,marginBottom:8}}>
                    In the closure model, Fm appears directly as a multiplicative gain -- no indirection through He(s):
                  </div>
                  {[
                    {eq:"Fm = fsw / (Sn · mc)",desc:"Modulator gain. Large Se → large mc → small Fm. Directly multiplies the forward path and the inner loop gain Ti."},
                    {eq:"Ti(s) = Fm · Gid(s) · Ri",desc:"Inner loop gain. When Fm is small, Ti is small, and (1+Ti) ≈ 1 → Gvc ≈ Fm·Gvd(s) → voltage-mode LC double-pole appears."},
                    {eq:"When Fm is large (no/little slope comp): Ti ≫ 1",desc:"Current loop dominates → Gvc ≈ Gvd/Gid·(1/Ri) = Gvi/Ri → single-pole CM behavior. The inner loop cancels the inductor pole."},
                    {eq:"mc·D' - 0.5 and Qp: used for subharmonic DETECTION only",desc:"These are still computed for warnings/diagnostics but do NOT appear in the closure Ti. They tell you if the discrete sampling causes period-doubling -- a separate phenomenon from the CM→VM transition."},
                  ].map((c,i)=>(
                    <div key={i} style={{marginBottom:8}}>
                      <div style={{fontFamily:"'JetBrains Mono',monospace",fontSize:12,color:"#a78bfa",background:"#0b0f14",borderRadius:3,padding:"5px 10px",border:"1px solid #1c2736",marginBottom:2,overflowX:"auto",whiteSpace:"nowrap"}}>{c.eq}</div>
                      <div style={{fontSize:10.5,color:"#8899aa",paddingLeft:4}}>{c.desc}</div>
                    </div>
                  ))}

                  {/* Summary box */}
                  <div style={{marginTop:12,background:"#0b0f14",border:"1px solid #1c2736",borderRadius:4,padding:"10px 12px"}}>
                    <div style={{fontSize:11,color:"#e4edf6",fontWeight:700,marginBottom:6}}>SUMMARY: CODE VARIABLE → PHYSICAL BLOCK MAPPING</div>
                    <div style={{display:"grid",gridTemplateColumns:"auto auto auto",gap:"4px 16px",fontSize:11,fontFamily:"monospace"}}>
                      <span style={{color:"#4e6378",fontWeight:700}}>Code variable</span><span style={{color:"#4e6378",fontWeight:700}}>Block diagram</span><span style={{color:"#4e6378",fontWeight:700}}>Effect</span>
                      <span style={{color:"#06d6c2"}}>Rload / Ri</span><span style={{color:"#8899aa"}}>Gvi(0) / Ri</span><span style={{color:"#8899aa"}}>DC gain (line 45)</span>
                      <span style={{color:"#06d6c2"}}>fp1</span><span style={{color:"#8899aa"}}>Gvi(s) output pole</span><span style={{color:"#8899aa"}}>Load-dependent pole (line 43)</span>
                      <span style={{color:"#06d6c2"}}>fz_esr</span><span style={{color:"#8899aa"}}>Gvi(s) ESR zero</span><span style={{color:"#8899aa"}}>Phase boost from ESR (line 44)</span>
                      <span style={{color:"#f472b6"}}>Sn, Se → mc</span><span style={{color:"#8899aa"}}>Fm (modulator)</span><span style={{color:"#8899aa"}}>Fm = fsw/(Sn·mc) -- sets inner loop gain</span>
                      <span style={{color:"#f472b6"}}>factor, Qp</span><span style={{color:"#8899aa"}}>Subharmonic criterion</span><span style={{color:"#8899aa"}}>Detection only -- not in closure Ti</span>
                      <span style={{color:"#94a3b8"}}>ωn = 2πfsw/π</span><span style={{color:"#8899aa"}}>He(s) in Ridley ref only</span><span style={{color:"#8899aa"}}>Not in closure model Ti</span>
                      <span style={{color:"#f5a623"}}>Vref/Vout</span><span style={{color:"#8899aa"}}>H (feedback)</span><span style={{color:"#8899aa"}}>Divider attenuation (line 77)</span>
                    </div>
                  </div>

                  <div style={{marginTop:8,paddingTop:8,borderTop:"1px solid #1c2736"}}>
                    <div style={{fontSize:10,color:"#4e6378",fontWeight:700,marginBottom:4,letterSpacing:"0.06em"}}>REFERENCES</div>
                    {[
                      "R.B. Ridley -- A New, Continuous-Time Model for Current-Mode Control (IEEE TPEL Vol.6 No.2, 1991) -- original derivation",
                      "R.D. Middlebrook -- Topics in Multiple-Loop Regulators and Current-Mode Programming (IEEE PESC, 1985) -- describes the current-programming approximation iL = vc/Ri",
                      "V. Vorperian -- Simplified Analysis of PWM Converters Using Model of PWM Switch (IEEE TAES, 1990) -- alternative unified switch model",
                      "R. Erickson & D. Maksimovic -- Fundamentals of Power Electronics, 3rd ed., Ch.12 -- current-mode control derivation",
                      "C. Basso -- Designing Control Loops for Linear and Switching Power Supplies (Artech, 2012) -- practical He(s) implementation",
                    ].map((r,i)=>(
                      <div key={i} style={{fontSize:10.5,color:"#6b829e",paddingLeft:6,marginBottom:2}}>[{i+1}] {r}</div>
                    ))}
                  </div>
                </CollapsiblePanel>

                <EqnSection title="UNIFIED PLANT MODEL (THIS TOOL)" content={[
                  {eq:"Gvc(s) = Fm · Gid(s) · Gvi(s) / (1 + Fm · Gid(s) · Kcs(s))",desc:"Inner-loop closure -- the PRIMARY model. Ti = Fm·Gid·Kcs is the physical inner loop gain. Kcs(s) is the sense chain transfer function (= scalar Ri in simple mode). Naturally transitions CM ↔ VM."},
                  {eq:"When Ti(0) ≫ 1: Gvc ≈ (Rload/Ri) · (1+s/ωz_esr) / (1+s/ωp1)",desc:"High inner-loop gain → current-mode behavior. Single pole + ESR zero. Matches Ridley."},
                  {eq:"When Ti(0) ≈ 1: LC double-pole begins to emerge",desc:"Transitional -- the inductor pole from Gid starts to appear in the closed-loop response."},
                  {eq:"When Ti(0) ≪ 1: Gvc ≈ Fm · Gvd(s) → LC double-pole visible",desc:"Inner loop has no gain -- plant reverts to VM. Gvd = Vin/(s²LC + sL/Rload + 1) x (1+sCout·ESR). Requires Type-III compensator."},
                  {eq:"Ti(0) = Fm · (Vin/Rload) · Ri",desc:"DC inner-loop gain. Monitor this to assess CM vs VM plant character."},
                  {eq:"He(s) NOT in Ti",desc:"He(s) is Ridley's analytical sampling correction for the closed-form model. It belongs in the Ridley reference trace, not in the physical inner-loop feedback path."},
                ]} refs={[
                  "R.B. Ridley -- A New, Continuous-Time Model for Current-Mode Control (IEEE TPEL, 1991)",
                  "V. Vorperian -- Simplified Analysis of PWM Converters Using Model of PWM Switch (IEEE TAES, 1990)",
                  "R. Erickson & D. Maksimovic -- Fundamentals of Power Electronics, 3rd ed., Ch.12",
                ]} />

                <EqnSection title="DCM PLANT MODEL" content={[
                  {eq:"Io_crit = (Vin - Vout) · D / (2 · L · fsw)",desc:"CCM/DCM boundary current. Below this, inductor current touches zero each cycle."},
                  {eq:"Gvc_dcm(s) = (Reff/Ri) · (1+s/ωz_esr) / (1+s/ωp_dcm)",desc:"DCM plant: single-pole response. No LC resonance, no He(s), no subharmonic instability."},
                  {eq:"Re = 2·L·fsw / D²",desc:"Loss-free resistor from the DCM PWM switch model (Vorpérian)."},
                  {eq:"Reff = Rload ‖ Re",desc:"Effective load seen by the output capacitor in DCM."},
                  {eq:"fp_dcm = 1/(2π · Reff · Cout)",desc:"Single output pole -- typically much lower than the CCM fp1 at the same load."},
                  {eq:"No He(s) in DCM",desc:"Inductor current resets to zero each cycle → no cycle-to-cycle memory → no sampling double-pole."},
                ]} refs={[
                  "V. Vorperian -- Simplified Analysis of PWM Converters Using Model of PWM Switch, Part II: DCM (IEEE TAES, 1990)",
                  "R. Erickson & D. Maksimovic -- Fundamentals of Power Electronics, 3rd ed., Ch.11",
                  "R. Ridley -- Analyzing the Sepic Converter in Discontinuous Mode (Ridley Engineering)",
                ]} />

                <EqnSection title="CURRENT SENSE CHAIN -- SHUNT" content={[
                  {eq:"Kcs(s) = (Rshunt + s·Lpar) · Gamp(s) · Gfilter(s)",desc:"Full shunt sense chain. Rshunt is the sense resistance, Lpar is PCB/package parasitic inductance."},
                  {eq:"Ri_eff = Rshunt x Gamp_DC = Kcs(0)",desc:"Effective sense gain at DC. This is the Ri used in plant model."},
                  {eq:"fz_par = Rshunt/(2π·Lpar)",desc:"Parasitic inductance zero. Adds leading-edge noise above this frequency. Keep > 10xfsw."},
                  {eq:"fp_amp = Gamp_BW",desc:"Current sense amplifier bandwidth pole. Rolls off sense gain at high frequency."},
                  {eq:"Ti(s) = Fm · Gid(s) · Kcs(s)",desc:"Inner loop gain uses the full sense chain. When Kcs rolls off at HF, Ti drops and plant transitions toward voltage-mode."},
                  {eq:"P_shunt = Irms² · Rshunt",desc:"Power dissipation. Irms depends on placement: continuous (inductor), pulsed D (high-side)."},
                ]} refs={[
                  "TI SNVA842 -- Current Sensing in Power Electronic Converters",
                  "TI SLVA504 -- High-Side vs Low-Side Current Sensing",
                ]} />

                <EqnSection title="CURRENT SENSE CHAIN -- CT" content={[
                  {eq:"Kcs_CT(s) = (Ns/Np) · Rb · sLm / (sLm + Rb)",desc:"Current transformer sense chain (simplified). High-pass: gain rolls off below fp_CT. Midband gain = (Ns/Np)·Rb."},
                  {eq:"fp_CT = Rb / (2π·Lm)",desc:"CT high-pass corner. Below this frequency the sensed signal droops. Keep fp_CT << fsw for minimal droop."},
                  {eq:"Droop = Ton / (Lm/Rb) x 100%",desc:"Signal droop during on-time. If >5%, the effective sensed slope changes and mc is affected. Increase Lm to reduce droop."},
                  {eq:"Self-reset: requires Toff ≥ Ton → D ≤ 50%",desc:"The CT core must demagnetize each cycle. For self-reset, the off-time must exceed on-time. At D > 50%, forced reset is required."},
                  {eq:"HF resonance: f_res = 1/(2π·√(Llk·Cw))",desc:"Leakage inductance and winding capacitance create a resonance that limits CT bandwidth. Keep well above fsw."},
                  {eq:"Ri_eff = (Np/Ns) · Rb",desc:"Effective sense gain at midband. I_sec = I_pri × (Np/Ns). V_sense = I_sec × Rb. Turns ratio provides galvanic isolation and current scaling."},
                  {eq:"P_burden = (I_primary/(Ns/Np))² · Rb = Irms² / (Ns/Np)² · Rb",desc:"Burden resistor dissipation. CT secondary current = primary current / turns ratio. Squared through the burden."},
                ]} refs={[
                  "Unitrode SEM-900 -- Current Transformer Design and Application",
                  "TI SLUA887 -- Current Sensing Using Current Transformers",
                  "C. Basso -- Switch-Mode Power Supplies, 2nd ed., Ch. 7 -- Current Sensing",
                ]} />

                <EqnSection title="SENSE PLACEMENT (PEAK CM)" content={[
                  {eq:"High-side: sees pulsed rising ramp during Ton → Peak CM",desc:"Standard peak CM. Requires leading-edge blanking (LEB). High common-mode voltage."},
                  {eq:"Inductor: sees continuous triangular current → Peak CM",desc:"Best SNR, no blanking needed. But CT can't self-reset in CCM and shunt has highest Irms dissipation."},
                  {eq:"Low-side: not implemented -- requires variable-frequency (COT) valley CM model",desc:"Most low-side sensing converters are COT/D-CAP topology, not fixed-frequency. Deferred to future phase."},
                ]} refs={[
                  "R. Ridley -- A New Small-Signal Model for Current-Mode Control (PhD Thesis, 1990)",
                  "TI SLVA504 -- High-Side vs Low-Side Current Sensing",
                ]} />

                <EqnSection title="SLOPE COMPENSATION" content={[
                  {eq:"Sn = [(Vin-Vout)/L] · Ri",desc:"Natural inductor up-slope sensed at CS pin (V/s)"},
                  {eq:"mc = 1 + Se/Sn",desc:"Compensation ratio -- Se is externally added slope"},
                  {eq:"Stability criterion: mc·D' - 0.5 > 0",desc:"If ≤ 0, subharmonic period-doubling oscillation occurs"},
                  {eq:"D > 50% requires Se > 0",desc:"Above 50% duty, slope compensation is mandatory"},
                ]} refs={[
                  "TI SLVA301 -- Understanding and Applying Current-Mode Control Theory",
                  "TI SLUA702 -- Slope Compensation for Current-Mode Control",
                ]} />

                <EqnSection title="TYPE-II COMPENSATOR" content={[
                  {eq:"Gc(s) = (2π·fi/s) · (1+s/ωz) / (1+s/ωp)",desc:"Integrator + one zero + one pole. Provides up to +90deg phase boost. Sufficient for current-mode plants (single-pole)."},
                  {eq:"Op-amp form: Gc(s) = (1+sR₂C₂) / (sR₁C₂·(1+sR₂C₁))",desc:"Physical implementation with R₁, R₂, C₁, C₂"},
                  {eq:"fi = 1/(2πR₁C₂)   fz = 1/(2πR₂C₂)   fp = 1/(2πR₂C₁)",desc:"Component ↔ frequency mapping"},
                  {eq:"LIMITATION: Cannot stabilize voltage-mode (LC double-pole) plants",desc:"When Ti(0) < ~3, the plant has an LC resonance with -180deg phase drop. Type-II can only boost by +90deg -- insufficient."},
                ]} refs={[
                  "TI SNVA555 -- Demystifying Type II and Type III Compensators",
                  "C. Basso -- Designing Control Loops for Linear and Switching Power Supplies (Artech, 2012)",
                ]} />

                <EqnSection title="TYPE-III COMPENSATOR" content={[
                  {eq:"Gc(s) = (fi/s) · (1+s/ωz1)(1+s/ωz2) / ((1+s/ωp1)(1+s/ωp2))",desc:"Integrator + two zeros + two poles. Provides up to +180deg phase boost. Required for voltage-mode plants (LC double-pole)."},
                  {eq:"Op-amp: fi = 1/(2πR₁C₂), fz1 = 1/(2πR₂C₂), fz2 = 1/(2πR₁C₁)",desc:"Zero placement (approx. R3 ≪ R1 for fz2)"},
                  {eq:"fp1 = 1/(2πR₂C₃), fp2 = 1/(2πR₃C₁)",desc:"Pole placement. C₃ in parallel with C₂, R₃ in series with C₁."},
                  {eq:"Two zeros straddle the LC resonance: fz1 = f₀/k, fz2 = f₀·k",desc:"Spread factor k ≈ 2. Centers the phase boost peak at f₀(LC) for maximum margin through the resonance."},
                ]} refs={[
                  "TI SNVA555 -- Demystifying Type II and Type III Compensators",
                  "C. Basso -- Designing Control Loops for Linear and Switching Power Supplies (Artech, 2012)",
                  "A. Pressman -- Switching Power Supply Design, 3rd ed. (McGraw-Hill), Ch. 12",
                ]} />

                <EqnSection title="ERROR AMPLIFIER MODEL" content={[
                  {eq:"Op-amp EA: Gea(s) = Aol / ((1+s/ωp1)·(1+s/ωp2))",desc:"Two-pole model. ωp1 = 2π·GBW/Aol (dominant pole), ωp2 = 2π·GBW·tan(PM_ea) (HF pole)."},
                  {eq:"OTA/gm EA: Gea(s) = gm · Rout / (1 + s·Rout·Cout_ea)",desc:"Transconductance amplifier. Single pole at fp = 1/(2π·Rout·Cout). Aol = gm·Rout."},
                  {eq:"Op-amp: Gc_real(s) = Gc_ideal(s) / (1 + Gc_ideal(s)/Gea(s))",desc:"Op-amp EA loading correction. Feedback loading compresses gain and adds phase lag when |Gc| approaches |Gea|."},
                  {eq:"OTA: Gc_real(s) = gm · (Zcomp(s) ‖ Zout_ea(s))",desc:"OTA EA: gm current source drives into comp network in parallel with EA output impedance. Physically different from op-amp loading."},
                  {eq:"Zcomp(Type-II) = (R2+1/sC2) ‖ (1/sC1)",desc:"Type-II compensation network impedance seen from COMP pin to ground."},
                  {eq:"Zcomp(Type-III) = (R2+1/sC2) ‖ (1/sC1) ‖ (R3+1/sC3)",desc:"Type-III adds a third branch for the additional zero/pole pair."},
                  {eq:"Guideline: GBW(EA) ≥ unity-gain freq of Gc(s)",desc:"TI SNVA411A: EA GBW must exceed the compensator's own 0dB crossing, NOT the loop crossover."},
                  {eq:"φ_EA(fc) = -arctan(fc/fp1) - arctan(fc/fp2)",desc:"Phase loss from finite-bandwidth EA at the loop crossover frequency. Subtracts directly from phase margin."},
                  {eq:"CS delay: Gd(s) ≈ (1-s·td/2) / (1+s·td/2)",desc:"First-order Padé approximation of propagation delay. Adds phase lag of ~360·fc·td degrees."},
                  {eq:"COMP clamps: COMP_low → D=0, COMP_high → D=Dmax",desc:"When COMP hits a clamp, the loop is open -- nonlinear saturation. Affects transient recovery time."},
                ]} refs={[
                  "TI SNVA411A -- Error Amplifier Limitations in High Performance Regulator Applications",
                  "TI TPS54418A Datasheet -- gm EA model with Rout/Cout (SLVSC13)",
                  "C. Basso -- Understanding Op Amp Dynamic Response In A Type-2 Compensator",
                  "C. Basso -- Designing Control Loops for Linear and Switching Power Supplies (Artech, 2012)",
                ]} />

                <EqnSection title="AUTO-PLACEMENT STRATEGY" content={[
                  {eq:"TYPE-II: fz ← fp1, fp ← min(fz_esr, fsw/2)",desc:"Zero cancels plant pole, pole cancels ESR zero. Standard CM placement."},
                  {eq:"TYPE-III: fz1 ← f₀(LC)/2, fz2 ← f₀(LC)·2",desc:"Zeros straddle LC resonance. Provides ~+150deg boost centered at f₀(LC)."},
                  {eq:"TYPE-III: fp1 ← min(fz_esr, fsw/2), fp2 ← fsw/2",desc:"First pole cancels ESR zero, second provides HF rolloff."},
                  {eq:"|Gc(fc)|·|Gp(fc)|·H = 1  →  solve for fi",desc:"Integrator gain set for unity loop gain at target crossover (both types)."},
                ]} refs={[
                  "TI SNVA555 -- Demystifying Type II and Type III Compensators",
                  "C. Basso -- Switch-Mode Power Supplies: SPICE Simulations and Practical Designs (McGraw-Hill)",
                ]} />

                <EqnSection title="STABILITY CRITERIA & VALIDATION" content={[
                  {eq:"fc ≤ fsw/10 (typical)  |  fc ≤ fsw/5 (aggressive limit)",desc:"Averaged model validity requires crossover well below fsw"},
                  {eq:"Phase margin ≥ 45deg (target)  |  ≥ 30deg (minimum)",desc:"Adequate damping for well-behaved transient response"},
                  {eq:"Gain margin ≥ 10 dB (target)  |  ≥ 6 dB (minimum)",desc:"Robustness to component tolerance and operating-point shifts"},
                  {eq:"ζ ≈ (PM/90deg)·0.8",desc:"Approximate damping ratio mapping for transient estimation"},
                  {eq:"Overshoot ≈ exp(-πζ/√(1-ζ²)) x 100%",desc:"Standard 2nd-order overshoot formula"},
                  {eq:"t_settle(2%) ≈ 4/(ζ·ωn)",desc:"Time to remain within ±2% of final value"},
                ]} refs={[
                  "TI SNVA555 -- Demystifying Type II and Type III Compensators",
                  "TI SEM1900 -- Compensation Reference Guide",
                  "Ogata -- Modern Control Engineering, Ch. 5",
                ]} />

                <EqnSection title="OUTPUT CAPACITOR BANK" content={[
                  {eq:"Zcap_i(s) = s·ESL_i + ESR_i + 1/(s·C_i)",desc:"Single capacitor impedance: inductive above SRF, capacitive below."},
                  {eq:"Zbank(s) = 1 / Σ(1/Zcap_i(s))",desc:"Parallel combination: sum admittances, invert. Used in Gvi(s) and Gid(s)."},
                  {eq:"f_SRF = 1/(2π·√(ESL·C))",desc:"Self-resonant frequency: impedance minimum. Above SRF, cap is inductive."},
                  {eq:"Anti-resonance: occurs when one cap is inductive and another is capacitive at the same frequency",desc:"Parallel L-C resonance creates an impedance PEAK that can exceed either cap's ESR."},
                  {eq:"Ceff = Σ(Qty_i · C_i),  ESReff = 1/Σ(Qty_i/ESR_i)",desc:"Effective values for scalar estimates (fp1). Used when bank has single cap type with no ESL."},
                  {eq:"fz_esr (curve): frequency where |Zbank| transitions from capacitive to flat",desc:"For mixed banks (multi-type or with ESL), the ESR zero is found from the |Z| minimum of the impedance curve rather than the scalar 1/(2π·Ceff·ESReff) formula. Auto-placer uses the curve-derived value."},
                  {eq:"MLCC DC bias: enter derated capacitance, not nominal",desc:"X5R/X7R lose 20–80% capacitance at rated voltage. Check manufacturer curves."},
                ]} refs={[
                  "Murata -- Capacitor Impedance and Equivalent Circuit Model",
                  "Murata -- Antiresonance in Parallel Capacitor Networks",
                  "TI SNVA411A -- De-rate ceramic output capacitance for DC bias in loop modeling",
                ]} />

                <EqnSection title="AUDIO SUSCEPTIBILITY -- OUTPUT IMPEDANCE & PSRR" content={[
                  {eq:"Zout_open(s) = Gvi(s) / (1 + Ti(s))",desc:"Open-loop output impedance (standard mode). Inner current loop reduces Zout from Rload to Rload/(1+Ti(0)) at DC."},
                  {eq:"Zout_open(s) ≈ Rload || Zcap(s)  [gm_ps mode]",desc:"Integrated converter: current source has high output impedance → Zout is just load in parallel with capacitor bank."},
                  {eq:"Zout_cl(s) = Zout_open(s) / (1 + T(s))",desc:"Closed-loop Zout. Voltage feedback T(s) reduces output impedance by (1+T) below crossover. Above fc, Zout rises toward open-loop."},
                  {eq:"Gvg_ol(s) = D · Gvi(s) / (1 + Ti(s))",desc:"Open-loop audio susceptibility (vin→vout). Standard mode: inner current loop attenuates line disturbances."},
                  {eq:"Gvg_ol(s) ≈ D · Zout / (1 + gm_ps · Zout · He)  [gm_ps mode]",desc:"Integrated converter: gm_ps x Zout acts as the inner loop gain. He(s) rolls off at HF → rejection degrades near fsw/π."},
                  {eq:"Gvg_cl(s) = Gvg_ol(s) / (1 + T(s))",desc:"Closed-loop audio susceptibility. Voltage loop provides additional line rejection below crossover."},
                  {eq:"PSRR(f) = -20·log₁₀|Gvg_cl(f)|",desc:"Power Supply Rejection Ratio. Higher is better. Equals T(s) gain (in dB) plus inner loop rejection below fc."},
                  {eq:"Cascaded stability: |Zout_downstream| < |Zin_upstream|  ∀ f",desc:"Middlebrook criterion for cascaded converters. Zout_cl of the upstream stage must be below Zin of the downstream stage."},
                ]} refs={[
                  "R.D. Middlebrook -- Input Filter Considerations (IEEE IAS, 1976)",
                  "R. Erickson & D. Maksimovic -- Fundamentals of Power Electronics, 3rd ed., Ch. 9",
                  "TI SLVA059 -- PSRR vs Frequency for Linear Regulators and Switching Regulators",
                  "R.B. Ridley -- Audio Susceptibility of Power Converters (APEC, 1999)",
                ]} />

                <EqnSection title="INPUT FILTER -- MIDDLEBROOK CRITERION" content={[
                  {eq:"|Zout_filter(f)| < |Zin_converter(f)|  ∀ f",desc:"Sufficient condition for stability with input filter"},
                  {eq:"Zin ≈ Vin²/Pout  (negative incremental resistance)",desc:"Converter looks like constant-power (negative-R) load to filter"},
                  {eq:"Zout = (jωL) ‖ (Rd + 1/jωC)",desc:"Filter output impedance from L-C-Rd network"},
                ]} refs={[
                  "R.D. Middlebrook -- Input Filter Considerations (IEEE IAS, 1976)",
                  "R.D. Middlebrook -- Preventing Input-Filter Oscillations (Powercon 5, 1978)",
                ]} />

                <EqnSection title="TEMPERATURE DERATING FACTORS (PER CAP TYPE)" content={[
                  {eq:"Electrolytic: ESR x3.0 (-40degC) | x1.0 (25degC) | x0.6 (125degC) · Cap x0.50 | x1.0 | x0.80",desc:"ESR rises sharply at cold; capacitance drops significantly at both extremes"},
                  {eq:"Polymer: ESR x1.5 (-40degC) | x1.0 (25degC) | x0.9 (125degC) · Cap x0.95 | x1.0 | x0.92",desc:"Much more stable than electrolytic across temperature"},
                  {eq:"MLCC X7R: ESR x1.1 (-40degC) | x1.0 (25degC) | x1.1 (125degC) · Cap x0.80 | x1.0 | x0.85",desc:"ESR nearly flat; capacitance varies ±15–20%. Also derates with DC bias (enter derated C!)"},
                  {eq:"MLCC X5R: ESR x1.1 (-40degC) | x1.0 (25degC) | x1.2 (125degC) · Cap x0.60 | x1.0 | x0.75",desc:"Worst cap stability of all types; 25–40% loss at extremes. DC bias derating can be 50%+"},
                  {eq:"Inductance: x1.02 (-40degC) | x1.0 (25degC) | x0.97 (125degC)",desc:"Ferrite permeability shifts ±3–5% with temperature"},
                ]} refs={[
                  "Murata, Nichicon, Panasonic capacitor datasheets -- ESR vs Temp curves",
                  "TDK / Würth Elektronik ferrite material specs -- u vs Temp",
                ]} />

                <EqnSection title="LOAD STEP TRANSIENT" content={[
                  {eq:"ΔV_ESR = ΔI · ESR",desc:"Instantaneous ESR voltage step (fastest component)"},
                  {eq:"dV/dt = ΔI/Cout",desc:"Capacitor droop rate before loop responds"},
                  {eq:"Recovery: governed by ωn = 2πfc and ζ from PM",desc:"Bandwidth determines correction speed"},
                ]} refs={[
                  "TI SLVA630 -- Estimating Output Voltage Ripple and Transient Response",
                  "R. Ridley -- Analyzing Transient Response of Switching Regulators (2006)",
                ]} />
              </div>
              </TabErrorBoundary>
            )}

          </div>
        </div>
      </div>

      {/* ─── Live Activity Log Panel ─── */}
      <div style={{position:"fixed",bottom:showLog?250:0,right:20,zIndex:1000}}>
        <button onClick={()=>setShowLog(!showLog)} style={{
          background:"#1a2332",color:showLog?"#86efac":"#93c5fd",border:`1px solid ${showLog?"#22c55e":"#3b82f6"}`,
          borderRadius:"6px 6px 0 0",padding:"6px 18px",fontSize:11,cursor:"pointer",
          fontWeight:700,letterSpacing:"0.05em",fontFamily:"monospace",
          boxShadow:"0 -2px 8px rgba(0,0,0,0.5)",
        }}>
          {showLog ? "▾ LOG" : "▸ LOG"} {logEntries.length > 0 ? `(${logEntries.length})` : ""}
        </button>
      </div>
      {showLog && <div style={{
        position:"fixed",bottom:0,left:0,right:0,zIndex:999,
        height:250,background:"#0a0e13",borderTop:"2px solid #22c55e",
        display:"flex",flexDirection:"column",fontFamily:"'JetBrains Mono','Fira Code',monospace",
        boxShadow:"0 -4px 20px rgba(0,0,0,0.6)",
      }}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",padding:"4px 12px",borderBottom:"1px solid #1c2736"}}>
            <span style={{fontSize:10,color:"#4e6378"}}>ACTIVITY LOG — {logEntries.length} entries</span>
            <div style={{display:"flex",gap:6}}>
              <button onClick={()=>{
                // Full state snapshot for debugging — paste into chat for Claude to read
                const ic = IC_LIBRARY.find(x=>x.id===selectedIC);
                const capE = getCapBankEffective(capBank);
                const snap = [
                  `=== TOOL STATE SNAPSHOT ${new Date().toISOString()} ===`,
                  ``,
                  `── TOPOLOGY & INPUT ──`,
                  `Topology: ${topology}${isIsolated?` | Isolated`:""} | Plant mode: ${plantMode}`,
                  `Vin: ${vinMin}–${vinMax}V (nom=${vinNom.toFixed(1)}V, active=${vinActive}V ${vinCorner})`,
                  `Vout: ${vout}V ±${voutTol}% | Iout: ${iout}A | fsw: ${fsw}kHz`,
                  ...(isFlyback ? [`Lm: ${xfmrLm}µH (flyback energy storage, no output L)`] : [`L: ${L}µH`]),
                  ...(isIsolated ? [
                    `Transformer: Np=${xfmrNp} Ns=${xfmrNs} n=${sf(turnsRatio,4)} Lm=${xfmrLm}µH`,
                    `Vin_eff: ${sf(vinEffMin,2)}–${sf(vinEffMax,2)}V (=${sf(turnsRatio,4)}×Vin)`,
                    `D(nom)=${sf(Dnom*100,1)}% D(max)=${sf(Dmax*100,1)}% Dmax_constraint=${sf(DmaxConstraint*100,0)}% ${DmaxViolation?"⚠ VIOLATION":"✓ OK"}`,
                  ] : [`D(nom)=${sf(Dnom*100,1)}% D(max)=${sf(Dmax*100,1)}%`]),
                  ...(auxSecondaries.length > 0 ? [`Aux windings: ${auxSecondaries.map((a,i)=>`#${i+2}(Ns=${a.ns}${topology!=="flyback"?`,L=${a.lout_uH}µH`:""}, V=${a.vout}V, ${a.cap_qty||1}×${a.cap_uF||100}µF/${a.cap_esr_mOhm||20}mΩ)`).join(", ")}`] : []),
                  ``,
                  `── SENSE & SLOPE COMP ──`,
                  `Sense: ${senseMode} | Ri_eff=${sf(ri_eff,4)}V/A | Placement: ${sensePlacement}${isIsolated?` | Iso side: ${isoSenseSide}`:""}`,
                  ...(senseMode==="ct" ? [`CT: ${ctNs}:${ctNp} Rb=${ctRb}Ω`] : []),
                  plantMode==="gmps" ? `SC: ${scAus}A/µs ${scEnabled?"[APPLIED to gm_ps]":"[He only]"} | gm_ps=${sf(gmps,1)}S` : `Se: ${se}mV/µs`,
                  `LEB: ${tLEB}ns | CS delay: ${csDelay}ns`,
                  lmAffectsSn ? `Lm→Sn: ACTIVE (magnetizing ramp as equiv. ext. slope)` : `Lm→Sn: OFF`,
                  ``,
                  `── IC ──`,
                  `IC: ${ic?ic.name:"Custom"} ${ic?`(${ic.mfg})`:""} | Vref=${vref}V`,
                  `EA: ${eaType}${eaType==="opamp"?` Aol=${eaAol}dB GBW=${eaGBW}MHz`:eaType==="ota"?` gm=${eaGm}µA/V Rout=${eaRout}MΩ`:""}`,
                  `COMP clamps: ${compClampLow}–${compClampHigh}V | Isrc=${eaIsrc}µA Isnk=${eaIsnk}µA`,
                  ...(isIsolated ? [
                    ``,
                    `── ISOLATED FEEDBACK (${fbMode === "primary" ? "primary-side" : "optocoupler"}) ──`,
                    ...(fbMode === "opto" ? [
                      `CTR=${optoCTR} Rpullup=${optoRpullup}kΩ Rled=${optoRled}kΩ Copto=${optoCopto}nF`,
                      `optoGain=${sf(optoGain,3)} fp_opto=${fp_opto>0?fmtFreq(fp_opto):"∞"} H_dc=${sf(vref/vout*optoGain,4)}`,
                    ] : [
                      `Primary-side: H_dc=Vref/Vout=${sf(vref/vout,4)} (no opto gain, no opto pole)`,
                    ]),
                  ] : []),
                  ``,
                  `── CAP BANK ──`,
                  ...capSlots.map((s,i)=>`  Group${i+1}: ${s.qty}× ${s.c_uF}µF ESR=${s.esr_mOhm}mΩ ESL=${s.esl_nH}nH ${s.type}`),
                  `Ceff=${fmtSI(capE.Ceff,"F")} ESReff=${fmtSI(capE.ESReff,"R")}`,
                  ``,
                  `── COMPUTED PLANT ──`,
                  ...(pinfo ? [
                    `D=${sf(pinfo.D*100,1)}% D'=${sf(pinfo.Dprime*100,1)}% Mode=${pinfo.mode} Topology=${pinfo.topology||topology}`,
                    `mc=${sf(pinfo.mc,3)} Qp=${sf(pinfo.Qp,3)} factor=${sf(pinfo.factor,4)}${pinfo.factor<=0?" ⚠ UNSTABLE":""}`,
                    `Gvc0=${sf(pinfo.Gvc0_dB,1)}dB Rload=${sf(pinfo.rload,3)}Ω`,
                    `fp1=${fmtFreq(pinfo.fp1)} fz_ESR=${fmtFreq(pinfo.fz_esr)} f0_LC=${fmtFreq(pinfo.f0_LC)}`,
                    pinfo.fz_rhp?`RHPZ=${fmtFreq(pinfo.fz_rhp)} fc_limit=${fmtFreq(pinfo.fz_rhp/5)}`:null,
                    `Io_crit=${fmtSI(pinfo.Io_crit,"A")}`,
                    pinfo.Ti0!==undefined?`Ti0=${sf(pinfo.Ti0,2)} Fm=${sf(pinfo.Fm,4)}`:null,
                    pinfo.sn_inductor!==undefined?`Sn_ind=${sf(pinfo.sn_inductor,0)}A/s Sn_mag=${sf(pinfo.sn_mag||0,0)}A/s`:null,
                    pinfo.ctrlMode?`Ctrl: ${pinfo.ctrlMode}`:null,
                  ].filter(Boolean) : [`pinfo: not computed yet`]),
                  ``,
                  `── COMPENSATOR ──`,
                  `Type: ${compType} | fc target: ${fcTarget}kHz`,
                  ...(activeComp ? [
                    activeComp.type==="type2"?`fz_c=${fmtFreq(activeComp.fz_c)} fp_c=${fmtFreq(activeComp.fp_c)} fi=${fmtFreq(activeComp.fi)}`
                    :`fz1=${fmtFreq(activeComp.fz1)} fz2=${fmtFreq(activeComp.fz2)} fp1=${fmtFreq(activeComp.fp1)} fp2=${fmtFreq(activeComp.fp2)} fi=${fmtFreq(activeComp.fi)}`,
                  ] : [`Comp: not computed yet`]),
                  ``,
                  `── LOOP RESULTS ──`,
                  crossoverFreq>0?`fc=${fmtFreq(crossoverFreq)} (${sf(fcRatio*100,1)}% of fsw)${fcTargetMiss>0.3?" ⚠ MISS":""}`:null,
                  pm!==null?`PM=${sf(pm,1)}° ${pm<30?"⚠ LOW":pm<45?"⚠ MARGINAL":"✓ OK"}`:null,
                  gm!==null?`GM=${sf(gm,1)}dB ${gm<6?"⚠ LOW":"✓ OK"}`:null,
                  pm!==null&&pm<0?`Zout(DC)=N/A (loop unstable, PM=${sf(pm,1)}°)`:`Zout(DC)=${fmtSI(zout_dc,"R")}`,
                  psrr_dc!==undefined?`PSRR(DC)=${sf(psrr_dc,1)}dB`:null,
                  ``,
                  `── WARNINGS/ERRORS ──`,
                  ...(val?.errors||[]).map(e=>`❌ ${e}`),
                  ...(val?.warnings||[]).map(w=>`⚠ ${w}`),
                  (val?.errors?.length===0 && val?.warnings?.length===0) ? `✓ No warnings or errors` : null,
                  ``,
                  `── RECENT LOG ──`,
                  ...logEntries.slice(-15).map(e=>`${e.ts} [${e.category}] ${e.msg}`),
                  ``,
                  `=== END SNAPSHOT ===`,
                ].filter(x=>x!==null).join("\n");
                setSnapText(snap);
                addLog("SYS","Snapshot generated — select all and copy from the text box below");
              }} style={{fontSize:9,color:"#86efac",background:"#166534",border:"1px solid #22c55e",borderRadius:3,padding:"1px 10px",cursor:"pointer",fontWeight:700}}>📋 Snapshot</button>
              {snapText && <button onClick={()=>setSnapText("")} style={{fontSize:9,color:"#fbbf24",background:"transparent",border:"1px solid #fbbf24",borderRadius:3,padding:"1px 8px",cursor:"pointer"}}>✕ Close</button>}
              <button onClick={()=>{
                const text = logEntries.map(e=>`${e.ts} [${e.category}] ${e.msg}`).join("\n");
                setSnapText(text);
                addLog("SYS","Log displayed — select all and copy");
              }} style={{fontSize:9,color:"#93c5fd",background:"transparent",border:"1px solid #3b82f6",borderRadius:3,padding:"1px 8px",cursor:"pointer"}}>Copy Log</button>
              <button onClick={()=>{setLogEntries([]);addLog("SYS","Log cleared");}} style={{fontSize:9,color:"#ef4444",background:"transparent",border:"1px solid #ef4444",borderRadius:3,padding:"1px 8px",cursor:"pointer"}}>Clear</button>
            </div>
          </div>
          <div ref={logRef} style={{flex:1,overflow:"auto",padding:"4px 8px",fontSize:10,lineHeight:1.6}}>
            {snapText ? (
              <textarea
                readOnly
                value={snapText}
                onFocus={e=>e.target.select()}
                style={{width:"100%",height:"100%",background:"#0d1117",color:"#c9d1d9",border:"1px solid #22c55e",borderRadius:3,padding:8,fontSize:10,fontFamily:"monospace",resize:"none",boxSizing:"border-box",lineHeight:1.5}}
              />
            ) : (<>
            {logEntries.map((e, i) => {
              const catColors = {INPUT:"#38bdf8",XFMR:"#c084fc",SENSE:"#fbbf24",PLANT:"#06d6c2",LOOP:"#f5a623",COMP:"#a78bfa",OPTO:"#f472b6",IC:"#93c5fd",SYS:"#4e6378"};
              return <div key={i} style={{color:"#b0c4d8"}}>
                <span style={{color:"#4e6378"}}>{e.ts}</span>{" "}
                <span style={{color:catColors[e.category]||"#6b829e",fontWeight:700}}>[{e.category}]</span>{" "}
                {e.msg}
              </div>;
            })}
            {logEntries.length === 0 && <div style={{color:"#4e6378",fontStyle:"italic",padding:8}}>Change any parameter to see live activity...</div>}
            </>)}
          </div>
        </div>}

    </div>
  );
}

function LoopBlockDiagram({senseMode, sensePlacement, rshunt, gampDC, ri_eff, ctNs, ctNp, ctRb}) {
  const teal="#06d6c2",purple="#a78bfa",amber="#f5a623",bright="#e4edf6",dim="#4e6378",bg="#0b0f14",panelBg="#111820",bdr="#1c2736";
  // Helpers
  const Block=({x,y,w,h,color,label,sub})=>(
    <g>
      <rect x={x} y={y} width={w} height={h} rx={3} fill={bg} stroke={color} strokeWidth={1.8}/>
      <text x={x+w/2} y={sub?y+h/2-2:y+h/2+1} fill={color} textAnchor="middle" dominantBaseline="middle" fontSize={sub?13:13} fontFamily="'JetBrains Mono',monospace" fontWeight={600}>{label}</text>
      {sub&&<text x={x+w/2} y={y+h/2+13} fill={dim} textAnchor="middle" dominantBaseline="middle" fontSize={8.5} fontFamily="'IBM Plex Sans',sans-serif">{sub}</text>}
    </g>
  );
  const Sigma=({cx,cy,color})=>(
    <g>
      <circle cx={cx} cy={cy} r={13} fill={bg} stroke={color||bright} strokeWidth={1.5}/>
      <text x={cx} y={cy+1} fill={color||bright} textAnchor="middle" dominantBaseline="middle" fontSize={14} fontFamily="serif">Σ</text>
    </g>
  );
  const Arr=({x1,y1,x2,y2,color,markerId})=>(
    <line x1={x1} y1={y1} x2={x2} y2={y2} stroke={color||dim} strokeWidth={1.3} markerEnd={`url(#${markerId})`}/>
  );
  const SigLabel=({x,y,text:t,color})=>(
    <text x={x} y={y} fill={color||bright} fontSize={12} fontFamily="'JetBrains Mono',monospace" fontStyle="italic" textAnchor="middle" dominantBaseline="auto">{t}</text>
  );
  const PlusMin=({cx,cy,pside,mside})=>{
    const off=18;
    const pos={top:[cx,cy-off],bottom:[cx,cy+off],left:[cx-off,cy],right:[cx+off,cy]};
    return(<g>
      <text x={pos[pside][0]} y={pos[pside][1]} fill={bright} fontSize={11} textAnchor="middle" dominantBaseline="middle" fontFamily="serif" fontWeight={700}>+</text>
      <text x={pos[mside][0]} y={pos[mside][1]} fill={bright} fontSize={13} textAnchor="middle" dominantBaseline="middle" fontFamily="serif" fontWeight={700}>-</text>
    </g>);
  };

  // Layout constants
  const fwdY=90; // forward path center
  const fbInnerY=190; // inner feedback
  const fbOuterY=248; // outer feedback

  return (
    <div>
      <div style={{fontSize:10.5,color:dim,marginBottom:10}}>
        Showing all gain blocks in the peak current-mode buck model. The inner current loop (sampled-data He model) is absorbed into Gvc(s) in our computation.
      </div>
      <svg viewBox="0 0 800 280" style={{width:"100%",height:"auto",display:"block"}}>
        <defs>
          <marker id="at" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><path d="M0,0.5 L7,3 L0,5.5" fill={teal}/></marker>
          <marker id="ap" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><path d="M0,0.5 L7,3 L0,5.5" fill={purple}/></marker>
          <marker id="aa" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><path d="M0,0.5 L7,3 L0,5.5" fill={amber}/></marker>
          <marker id="ad" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><path d="M0,0.5 L7,3 L0,5.5" fill={dim}/></marker>
          <marker id="ab" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><path d="M0,0.5 L7,3 L0,5.5" fill={bright}/></marker>
          <marker id="am" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto"><path d="M0,0.5 L7,3 L0,5.5" fill={"#e879f9"}/></marker>
        </defs>

        {/* ---- Dashed boxes ---- */}
        <rect x={2} y={22} width={788} height={244} rx={6} fill="none" stroke={amber} strokeWidth={1.4} strokeDasharray="8 5" opacity={0.5}/>
        <text x={12} y={17} fill={amber} fontSize={11} fontFamily="'IBM Plex Sans',sans-serif" fontWeight={700} fontStyle="italic" opacity={0.8}>Outer Voltage Loop</text>
        <rect x={270} y={42} width={340} height={170} rx={5} fill="none" stroke={teal} strokeWidth={1.4} strokeDasharray="6 4" opacity={0.5}/>
        <text x={280} y={38} fill={teal} fontSize={11} fontFamily="'IBM Plex Sans',sans-serif" fontWeight={700} fontStyle="italic" opacity={0.8}>Inner Current Loop</text>

        {/* ---- Forward path ---- */}
        <text x={12} y={fwdY+4} fill={bright} fontSize={13} fontFamily="'JetBrains Mono',monospace" fontStyle="italic">v<tspan dy={3} fontSize={9}>ref</tspan></text>
        <Arr x1={42} y1={fwdY} x2={52} y2={fwdY} color={bright} markerId="ab"/>
        <Sigma cx={66} cy={fwdY} color={bright}/>
        <PlusMin cx={66} cy={fwdY} pside="left" mside="bottom"/>

        {/* ev → EA (new block) */}
        <Arr x1={79} y1={fwdY} x2={102} y2={fwdY} color={"#e879f9"} markerId="am"/>
        <SigLabel x={90} y={fwdY-10} text="ev" color={bright}/>
        <Block x={102} y={fwdY-22} w={50} h={44} color={"#e879f9"} label="EA" sub="Aol/gm"/>

        {/* EA → Gc(s) */}
        <Arr x1={152} y1={fwdY} x2={167} y2={fwdY} color={purple} markerId="ap"/>
        <Block x={167} y={fwdY-22} w={72} h={44} color={purple} label="Gc(s)" sub="Comp"/>

        {/* vc → Gdelay */}
        <Arr x1={239} y1={fwdY} x2={252} y2={fwdY} color={dim} markerId="ad"/>
        <SigLabel x={246} y={fwdY-10} text="vc" color={bright}/>

        {/* Σ2 -- inner summing junction */}
        <Sigma cx={286} cy={fwdY} color={teal}/>
        <PlusMin cx={286} cy={fwdY} pside="left" mside="bottom"/>

        {/* ei → Fm */}
        <Arr x1={299} y1={fwdY} x2={335} y2={fwdY} color={teal} markerId="at"/>
        <SigLabel x={316} y={fwdY-10} text="ei" color={teal}/>

        {/* Fm -- modulator */}
        <Block x={335} y={fwdY-22} w={72} h={44} color={teal} label="Fm" sub="Modulator"/>

        {/* d̂ → Gid(s) */}
        <Arr x1={407} y1={fwdY} x2={440} y2={fwdY} color={teal} markerId="at"/>
        <SigLabel x={422} y={fwdY-10} text="d̂" color={teal}/>

        {/* Gid(s) -- duty to inductor current */}
        <Block x={440} y={fwdY-22} w={80} h={44} color={teal} label="Gid(s)" sub="d̂ → îL"/>

        {/* îL junction dot */}
        <circle cx={536} cy={fwdY} r={3} fill={teal}/>
        <SigLabel x={550} y={fwdY-10} text="îL" color={teal}/>

        {/* îL → Gvi(s) */}
        <Arr x1={539} y1={fwdY} x2={570} y2={fwdY} color={teal} markerId="at"/>

        {/* Gvi(s) -- inductor current to output */}
        <Block x={570} y={fwdY-22} w={80} h={44} color={teal} label="Gvi(s)" sub="îL → v̂o"/>

        {/* → vo output */}
        <Arr x1={650} y1={fwdY} x2={700} y2={fwdY} color={bright} markerId="ab"/>

        {/* vo junction dot */}
        <circle cx={696} cy={fwdY} r={3} fill={bright}/>
        <text x={710} y={fwdY+5} fill={bright} fontSize={13} fontFamily="'JetBrains Mono',monospace" fontStyle="italic">v<tspan dy={3} fontSize={9}>o</tspan></text>

        {/* ---- Inner current feedback: îL → Ri·He(s) → Σ2 ---- */}
        {/* Down from îL junction */}
        <line x1={536} y1={fwdY+3} x2={536} y2={fbInnerY} stroke={teal} strokeWidth={1.3}/>
        {/* Left to Ri block */}
        <Arr x1={536} y1={fbInnerY} x2={460} y2={fbInnerY} color={teal} markerId="at"/>

        {/* Ri block */}
        <Block x={360} y={fbInnerY-19} w={100} h={38} color={teal} label={senseMode!=="simple"?"Kcs(s)":"Ri"} sub={senseMode!=="simple"?sensePlacement.replace("_"," "):"Current Sense"}/>

        {/* Left from Ri to Σ2 bottom */}
        <Arr x1={360} y1={fbInnerY} x2={286} y2={fbInnerY} color={teal} markerId="at"/>
        <line x1={286} y1={fbInnerY} x2={286} y2={fwdY+13} stroke={teal} strokeWidth={1.3}/>

        {/* ---- Outer voltage feedback: vo → H → Σ1 ---- */}
        {/* Down from vo junction */}
        <line x1={696} y1={fwdY+3} x2={696} y2={fbOuterY} stroke={amber} strokeWidth={1.3}/>
        {/* Left toward H block */}
        <Arr x1={696} y1={fbOuterY} x2={440} y2={fbOuterY} color={amber} markerId="aa"/>

        {/* H block */}
        <Block x={348} y={fbOuterY-18} w={72} h={36} color={amber} label="H" sub="Vref / Vout"/>

        {/* Left from H to Σ1 bottom */}
        <Arr x1={348} y1={fbOuterY} x2={66} y2={fbOuterY} color={amber} markerId="aa"/>
        <line x1={66} y1={fbOuterY} x2={66} y2={fwdY+13} stroke={amber} strokeWidth={1.3}/>

        {/* ---- Signal annotation: vfb ---- */}
        <SigLabel x={200} y={fbOuterY-8} text="vfb" color={amber}/>

      </svg>

      {/* Block descriptions */}
      <div style={{marginTop:12,display:"grid",gridTemplateColumns:"1fr 1fr",gap:8}}>
        {[
          {block:"EA",color:"#e879f9",desc:"Error amplifier. Op-amp (Aol/GBW) or OTA (gm·Zout). Finite bandwidth adds phase lag at crossover. When set to Ideal, has no effect."},
          {block:"Gc(s)",color:purple,desc:"Compensator network. Type-II or Type-III. EA loading correction applied when EA is non-ideal: Gc_real = Gc/(1 + Gc/Gea)."},
          {block:"Fm",color:teal,desc:"Modulator gain. Converts COMP voltage error to duty cycle perturbation d̂. For peak CM: Fm ≈ fsw/(Sn·mc)."},
          {block:"Gid(s)",color:teal,desc:"Duty-to-inductor-current. How duty perturbation drives inductor current. Contains the inductor pole."},
          {block:"Gvi(s)",color:teal,desc:"Inductor-current-to-output. Output LC filter and load: includes ESR zero and load pole fp1."},
          {block:senseMode!=="simple"?"Kcs(s)":"Ri",color:teal,desc:senseMode==="shunt"
            ?`Sense chain: Rshunt=${rshunt} mR x Gamp=${gampDC} → Ri_eff=${sf(ri_eff*1e3,1)} mR. Peak CM (${sensePlacement.replace("_"," ")}). Includes parasitic zero and amp bandwidth.`
            :senseMode==="ct"
            ?`CT sense: ${ctNs}:${ctNp} x Rb=${ctRb}R → Ri_eff=${sf(ri_eff,3)} V/A. High-pass (HP corner at fp_CT). Peak CM (${sensePlacement.replace("_"," ")}).`
            :"Current sense gain (V/A). Converts inductor current to voltage for the comparator."},
          {block:"He(s)",color:"#94a3b8",desc:"Sampled-data correction (Ridley). Adds double-pole at fsw/π. Shown as separate trace in sub-blocks view."},
          {block:"H",color:amber,desc:"Feedback divider. H = Vref/Vout. Scales output to the reference level."},
        ].map((b,i)=>(
          <div key={i} style={{background:bg,border:`1px solid ${bdr}`,borderRadius:4,padding:"8px 10px"}}>
            <span style={{fontFamily:"'JetBrains Mono',monospace",fontSize:12,color:b.color,fontWeight:600}}>{b.block}</span>
            <span style={{fontSize:10.5,color:dim,marginLeft:6}}>{b.desc}</span>
          </div>
        ))}
      </div>

      {/* Computed model note */}
      <div style={{marginTop:10,background:bg,border:`1px solid ${bdr}`,borderRadius:4,padding:"8px 12px"}}>
        <div style={{fontSize:11,color:bright,fontWeight:600,marginBottom:4}}>WHAT THIS TOOL COMPUTES</div>
        <div style={{fontSize:11,color:dim,lineHeight:1.6}}>
          The tool uses the inner-loop closure model as the primary plant. Ti = Fm·Gid·Kcs(s) is the physical inner loop (no He):
        </div>
        <div style={{fontFamily:"'JetBrains Mono',monospace",fontSize:12.5,color:teal,background:panelBg,borderRadius:3,padding:"5px 10px",border:`1px solid ${bdr}`,marginTop:6,marginBottom:4}}>
          Gvc(s) = Fm · Gid(s) · Gvi(s) / (1 + Fm · Gid(s) · Kcs(s))
        </div>
        <div style={{fontSize:11,color:dim,lineHeight:1.6}}>
          Kcs(s) is the sense chain: scalar Ri in simple mode, or Rshunt+Lpar x Gamp x Gfilter in shunt mode.
          This naturally transitions: when Ti(0) {"≫"} 1 → single-pole CM behavior (≈ Rload/Ri).
          When Ti(0) {"≪"} 1 (excess slope comp) → LC double-pole VM behavior (≈ Fm·Gvd).
          When Kcs rolls off at HF (amp BW), Ti drops and plant becomes more VM-like at those frequencies.
        </div>
        <div style={{fontFamily:"'JetBrains Mono',monospace",fontSize:11.5,color:"#ef4444",background:panelBg,borderRadius:3,padding:"5px 10px",border:`1px solid ${bdr}`,marginTop:6,marginBottom:4}}>
          Ridley reference: Gvc(s) = (Rload/Ri) · (1 + s/ωz_esr) / [(1 + s/ωp1) · He(s)]
        </div>
        <div style={{fontSize:11,color:dim}}>
          The Ridley closed-form (red dashed in sub-blocks view) always shows CM single-pole behavior. It's accurate when Ti(0) {"≫"} 1 but doesn't capture the VM transition.
        </div>
      </div>
    </div>
  );
}

function PanelBox({title,children}) {
  return (
    <div style={{background:"#111820",border:"1px solid #1c2736",borderRadius:5,padding:"10px 6px 2px"}}>
      <div style={{fontSize:10,color:"#4e6378",paddingLeft:48,fontWeight:700,letterSpacing:"0.08em",marginBottom:2}}>{title}</div>
      {children}
    </div>
  );
}

function DiagBox({title,items,color,bg}) {
  return (
    <div style={{background:bg,border:`1px solid ${color}`,borderRadius:5,padding:12}}>
      <div style={{fontSize:12,fontWeight:700,color,marginBottom:6}}>{title}</div>
      {items.map((e,i)=>(
        <div key={i} style={{fontSize:11.5,color:color==="#ef4444"?"#fca5a5":color==="#eab308"?"#fde68a":"#93c5fd",
          marginBottom:4,paddingLeft:8,borderLeft:`2px solid ${color}`}}>{e}</div>
      ))}
    </div>
  );
}

function EqnSection({title,content,refs,defaultOpen}) {
  const [open, setOpen] = useState(defaultOpen || false);
  return (
    <div style={{background:"#111820",border:"1px solid #1c2736",borderRadius:5,overflow:"hidden"}}>
      <div onClick={()=>setOpen(!open)} style={{padding:"10px 14px",cursor:"pointer",display:"flex",alignItems:"center",gap:8,userSelect:"none"}}>
        <span style={{fontSize:11,color:"#4e6378",fontFamily:"monospace",transition:"transform 0.15s",transform:open?"rotate(90deg)":"rotate(0deg)"}}>▶</span>
        <span style={{fontSize:12,fontWeight:700,color:"#e4edf6",letterSpacing:"0.06em",flex:1}}>{title}</span>
        <span style={{fontSize:9,color:"#4e6378"}}>{content.length} eqn{content.length!==1?"s":""}</span>
      </div>
      {open && <div style={{padding:"0 14px 14px"}}>
        {content.map((c,i)=>(
          <div key={i} style={{marginBottom:10}}>
            <div style={{fontFamily:"'JetBrains Mono','Fira Code',monospace",fontSize:12.5,
              color:"#06d6c2",background:"#0b0f14",borderRadius:3,padding:"6px 10px",
              border:"1px solid #1c2736",marginBottom:3,overflowX:"auto",whiteSpace:"nowrap"}}>
              {c.eq}
            </div>
            <div style={{fontSize:11,color:"#8899aa",paddingLeft:4}}>{c.desc}</div>
          </div>
        ))}
        {refs?.length>0&&(
          <div style={{marginTop:8,paddingTop:8,borderTop:"1px solid #1c2736"}}>
            <div style={{fontSize:10,color:"#4e6378",fontWeight:700,marginBottom:4,letterSpacing:"0.06em"}}>REFERENCES</div>
            {refs.map((r,i)=>(
              <div key={i} style={{fontSize:10.5,color:"#6b829e",paddingLeft:6,marginBottom:2}}>[{i+1}] {r}</div>
            ))}
          </div>
        )}
      </div>}
    </div>
  );
}

function CollapsiblePanel({title,defaultOpen,children}) {
  const [open, setOpen] = useState(defaultOpen || false);
  return (
    <div style={{background:"#111820",border:"1px solid #1c2736",borderRadius:5,overflow:"hidden"}}>
      <div onClick={()=>setOpen(!open)} style={{padding:"10px 14px",cursor:"pointer",display:"flex",alignItems:"center",gap:8,userSelect:"none"}}>
        <span style={{fontSize:11,color:"#4e6378",fontFamily:"monospace",transition:"transform 0.15s",transform:open?"rotate(90deg)":"rotate(0deg)"}}>▶</span>
        <span style={{fontSize:12,fontWeight:700,color:"#e4edf6",letterSpacing:"0.06em",flex:1}}>{title}</span>
      </div>
      {open && <div style={{padding:"0 14px 14px"}}>{children}</div>}
    </div>
  );
}

class TabErrorBoundary extends Component {
  constructor(props) { super(props); this.state = { hasError: false, error: null }; }
  static getDerivedStateFromError(error) { return { hasError: true, error }; }
  render() {
    if (this.state.hasError) {
      return (
        <div style={{padding:20,textAlign:"center"}}>
          <div style={{color:"#ef4444",fontSize:13,fontWeight:700,marginBottom:8}}>Tab render error</div>
          <div style={{color:"#7b8da0",fontSize:11,fontFamily:"monospace",marginBottom:12}}>{this.state.error?.message || "Unknown error"}</div>
          <button onClick={()=>this.setState({hasError:false,error:null})} style={{
            background:"#38bdf8",color:"#000",border:"none",borderRadius:4,padding:"6px 16px",
            fontSize:11,cursor:"pointer",fontWeight:600
          }}>Retry</button>
        </div>
      );
    }
    return this.props.children;
  }
}
