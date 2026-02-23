# Agent Priority & Impact Matrix

## Quick Decision Table

| # | Agent Name | Priority | Project Impact | Transferability | Timeline | Start Date |
|---|---|---|---|---|---|---|
| 1 | **PEEC Matrix Optimizer** | ⭐⭐⭐ High | 🟢 Critical (solve bottleneck) | 🟢 Very High | 2-4 weeks | Week 1 |
| 2 | **Winding Layout Validator** | ⭐⭐⭐ High | 🟢 Critical (catch errors) | 🟢 Very High | 2-4 weeks | Week 1 |
| 3 | **JSON Config Reconciler** | ⭐⭐⭐ High | 🟢 Critical (data integrity) | 🟢 Very High | 2-3 weeks | Week 1 |
| 4 | **Test Orchestrator** | ⭐⭐⭐ High | 🟡 Important (reduce toil) | 🟢 Very High | 2-3 weeks | Week 2 |
| 5 | **Wizard State Manager** | ⭐⭐ Medium | 🟡 Important (fix bugs) | 🟢 High | 2-3 weeks | Week 3 |
| 6 | **OpenMagnetics API Bridge** | ⭐⭐ Medium | 🟡 Important (unify code) | 🟢 High | 2-3 weeks | Week 3 |
| 7 | **Loss Visualization** | ⭐⭐ Medium | 🟡 Important (UX) | 🟢 Medium | 2-4 weeks | Week 4 |
| 8 | **Octave/MATLAB CI/CD** | ⭐ Low-Medium | 🟡 Important (stability) | 🟢 High | 1-2 weeks | Week 4 |
| 9 | **Thermal Integration** | ⭐ Medium (Future) | 🟢 High value | 🟢 High | 3-4 weeks | Month 2 |
| 10 | **CAD Export & DFM** | ⭐ Low (Planned) | 🟡 Important (feature) | 🟢 Medium | 2-3 weeks | Month 2 |

---

## Timeline Gantt (Months 1-2)

```
Week 1:  [===== PEEC Optimizer =====] [===== Winding Validator =====] [===== JSON Reconciler =====]
Week 2:  [===== PEEC Optimizer =====] [===== Test Orchestrator =====]
Week 3:  [===== Wizard State Mgr =====] [===== API Bridge =====]
Week 4:  [===== Loss Viz =====] [===== Octave/MATLAB CI =====]
Week 5:  [===== Thermal Integration =====] [===== CAD Export =====]
```

---

## Impact vs Effort Graph

```
High Impact │
            │  ●1 (PEEC Opt)    ●3 (JSON)
            │    ●2 (Wind Layout)    ●4 (Test)
            │              ●5 (Wizard)
            │           ●6 (API Bridge)
            │        ●7 (Loss Viz)    ●9 (Thermal)
            │     ●8 (Octave)              ●10 (CAD)
Low Impact  │
            └─────────────────────────────────
              Low Effort         High Effort
```

---

## Recommended Execution Order

### **Batch 1 (Parallel, Week 1-2)** - Foundation
Start these simultaneously; they're independent:

1. **PEEC Matrix Optimizer** - unblocks performance-sensitive workflows
2. **Winding Layout Validator** - catches data validity issues
3. **JSON Config Reconciler** - ensures data integrity foundation

**Why together:** No cross-dependencies. Addresses core architecture weaknesses. High ROI on early effort.

---

### **Batch 2 (Week 2-3)** - Integration & Quality

4. **Multi-Language Test Orchestrator** - validates Batch 1 improvements
5. **Wizard State Machine Manager** - fixes documented UX gaps
6. **OpenMagnetics API Bridge** - centralizes external dependencies

**Why here:** Built on confidence from Batch 1. Reduce technical debt before adding features.

---

### **Batch 3 (Week 4+)** - UX & Stability

7. **Loss Visualization Enhancer** - improve user experience
8. **Octave/MATLAB Compatibility** - ensure cross-platform stability
9. **Thermal Integration** - roadmap feature (Month 2)
10. **CAD Export & DFM** - long-term manufacturing integration (Month 2+)

---

## Success Criteria Checklist

### Batch 1 Success (End of Week 2)
- [ ] PEEC solver < 0.2s for typical 2-winding case (was 0.5s)
- [ ] Winding validator catches all packing failures with <100ms validation time
- [ ] JSON reconciler validates 100% of configs, suggests fixes

### Batch 2 Success (End of Week 3)
- [ ] Full validation suite runs in <5 minutes parallel, visualizes all results
- [ ] All 9 wizard gaps fixed; state transitions tested
- [ ] API calls centralized; caching working; offline mode fallback tested

### Batch 3 Success (End of Week 4+)
- [ ] Loss visualizations interactive; hotspots identified
- [ ] CI/CD passes on Octave 10.3 + MATLAB 2024a, Windows & Linux
- [ ] Thermal model integrates; hotspot predictions validated vs. measured data

---

## Risk Heat Map

```
PEEC Opt        🟡 MEDIUM    (accuracy regression risk)
Wind Validator  🟡 MEDIUM    (edge cases in corner geometries)
JSON Reconciler 🟢 LOW       (schema-based validation)
Test Orch       🟡 MEDIUM    (false positive risk in tolerance matching)
Wizard State    🟡 MEDIUM    (state explosion with 16 wizards)
API Bridge      🟡 MEDIUM    (API breaking changes)
Loss Viz        🟢 LOW       (visualization-only, no solver changes)
Octave/MATLAB   🟡 MEDIUM    (version-specific quirks)
Thermal         🟠 HIGH      (physics coupling complexity)
CAD Export      🟢 LOW       (isolated feature)
```

---

## Resource Allocation (Estimated Agent-Days)

| Agent | Discovery | MVP | Integration | Docs | Total |
|-------|-----------|-----|-------------|------|-------|
| PEEC Optimizer | 3 | 7 | 3 | 2 | **15 days** |
| Winding Validator | 2 | 5 | 2 | 1 | **10 days** |
| JSON Reconciler | 2 | 4 | 2 | 1 | **9 days** |
| Test Orchestrator | 2 | 6 | 3 | 2 | **13 days** |
| Wizard State Mgr | 2 | 5 | 3 | 2 | **12 days** |
| API Bridge | 2 | 5 | 2 | 1 | **10 days** |
| Loss Visualization | 2 | 6 | 2 | 2 | **12 days** |
| Octave/MATLAB CI | 1 | 4 | 2 | 1 | **8 days** |
| Thermal Integration | 3 | 8 | 3 | 2 | **16 days** |
| CAD Export & DFM | 2 | 6 | 2 | 1 | **11 days** |
| **TOTAL (10 agents)** | | | | | **116 days** |

**Parallelization:** Batch 1 (3 parallel) = 12 days effective. Batch 2 (3 parallel) = 13 days. Batch 3 (4 parallel) = 16 days. **Total: ~40 days actual calendar** (assuming 3-4 concurrent agents).

---

## Cross-Project Applicability

### Agents Useful in 80%+ of Projects
- ✅ JSON Config Reconciler
- ✅ Test Orchestrator
- ✅ State Machine Validator
- ✅ API Bridge & Caching

### Agents Useful in 30-50% of Projects
- ✅ PEEC Matrix Optimizer (→ any FEM/FEA solver)
- ✅ Performance Regression Detector (→ ML, databases, games)
- ✅ Loss Visualization (→ thermal, stress, CFD analysis)
- ✅ Octave/MATLAB Compatibility (→ cross-platform C/C++)

### Agents Useful in 10-30% of Projects
- ✅ Thermal Integration (→ automotive, power electronics, embedded)
- ✅ CAD Export & DFM (→ hardware design, PCB, 3D printing)

---

## Monthly Roadmap

### Month 1: Solve Bottlenecks
- **Weeks 1-2:** Batch 1 (PEEC, Winding, JSON)
- **Weeks 3-4:** Batch 2 (Test, Wizard, API) + early Batch 3

### Month 2: Stability & Features
- **Weeks 1-2:** Batch 3 UX improvements (Loss, CI/CD)
- **Weeks 2-4:** Thermal integration + CAD export kickoff

### Month 3+: Advanced Features
- Finalize CAD export, DFM checking
- Real-world validation (user feedback on agent workflows)
- Document lessons learned → apply to other projects

---

## Example: "I Have 2 Weeks, What Do I Build?"

**Answer: Batch 1 (3 agents in parallel)**

1. **PEEC Matrix Optimizer** - Focus on profile + caching (skip advanced sparse matrix)
2. **Winding Layout Validator** - Focus on basic DRC (clearance, overflow)
3. **JSON Config Reconciler** - Focus on schema validation + auto-fix (skip lineage)

**Deliverables:** User sees faster solver, catches packing errors, data integrity validated. Road clear for Batch 2.

---

## Example: "I Have 1 Month, What Do I Build?"

**Answer: Batch 1 + Batch 2**

Execute Batches 1-2 in parallel (2-3 agents per week). By end of Month 1:
- Solver 3-5x faster
- Validation suite automated
- Wizard bugs fixed
- Data integrity assured
- Foundation for Month 2 advanced features

---

**Last Updated:** 2026-02-22
**Branch:** optimization
**Next Review:** After Batch 1 completion (end of Week 2)
