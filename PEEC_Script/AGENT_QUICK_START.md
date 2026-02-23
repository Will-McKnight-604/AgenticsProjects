# Agent Quick Start Guide

**Jump to your situation below:**

---

## 🎯 I Just Reviewed the Analysis – What Now?

### Step 1: Choose Your Timeline
- **🟢 2 weeks** → Start Batch 1 (Agents 1-3)
- **🟡 4 weeks** → Start Batch 1-2 (Agents 1-6)
- **🔴 8 weeks** → Start all Phase 1 (Agents 1-10)

### Step 2: Read the Priority Matrix
Open `AGENT_PRIORITY_MATRIX.md`
- See the Gantt chart for your timeline
- Check the "Recommended Execution Order" section
- Use the "Success Criteria Checklist" to track progress

### Step 3: Pick Batch 1, 2, or 3
Use the table below to see what each batch solves

---

## 📋 Agent Batches at a Glance

### **Batch 1 (Week 1-2): Foundation** – 3 Agents in Parallel
These solve critical bottlenecks. Start all 3 at once; they don't depend on each other.

| Agent | Solves | Success = | Time |
|-------|--------|-----------|------|
| **PEEC Matrix Optimizer** | Solver too slow (0.5s → 0.1s) | Solver <200ms | 2-4 wks |
| **Winding Layout Validator** | Packing errors caught late | DRC in <100ms | 2-4 wks |
| **JSON Config Reconciler** | Data corruption, stale configs | 100% drift detection | 2-3 wks |

**Why start here:** These fix core architecture issues. Everything else depends on them.

---

### **Batch 2 (Week 2-3): Quality & Integration** – 3 Agents in Parallel
Run after Batch 1 starts, in parallel with Batch 1's final week.

| Agent | Solves | Success = | Time |
|-------|--------|-----------|------|
| **Test Orchestrator** | 30 manual test scripts | <5min full suite, trends | 2-3 wks |
| **Wizard State Manager** | 9 documented wizard bugs | All bugs fixed, tested | 2-3 wks |
| **API Bridge** | API calls scattered, no error handling | Centralized, cached, fallback | 2-3 wks |

**Why this batch:** Ensures quality of Batch 1. Prepares for Batch 3 features.

---

### **Batch 3 (Week 4+): UX & Stability** – 4 Agents, Parallel or Sequential
Run after Batch 2 starts. Can run in parallel or sequence depending on team size.

| Agent | Solves | Success = | Time |
|-------|--------|-----------|------|
| **Loss Visualization** | Static plots, no optimization hints | Interactive 3D hotspot maps | 2-4 wks |
| **Octave/MATLAB CI** | No cross-platform testing | CI passes all versions/OS | 1-2 wks |
| **Thermal Integration** | Isothermal assumption invalid | Temperature-aware design | 3-4 wks |
| **CAD Export** | No DFM, manual CAD modeling | STEP/STL exports, DFM checks | 2-3 wks |

**Why this batch:** Features, not fixes. Build on solid foundation from Batches 1-2.

---

## 🚀 Quick Decision Tree

**Q: What's slowing down my users?**
- A: Solver speed → Build **PEEC Matrix Optimizer**
- A: Data bugs → Build **JSON Config Reconciler**
- A: Design errors → Build **Winding Layout Validator**

**Q: What's slowing down my team?**
- A: Manual validation → Build **Test Orchestrator**
- A: Wizard bugs → Build **Wizard State Manager**
- A: Scattered APIs → Build **API Bridge**

**Q: What features do I need?**
- A: Better loss insights → Build **Loss Visualization**
- A: Thermal analysis → Build **Thermal Integration**
- A: CAD/manufacturing → Build **CAD Export**
- A: Cross-platform → Build **Octave/MATLAB CI**

---

## 📊 Batch 1 Deep Dive

### Agent #1: PEEC Matrix Optimizer
**Problem:** Solver takes 0.5s; users want <100ms for interactive design

**Solution Steps:**
1. Profile `peec_solve_frequency.m` (identify hot spots)
2. Implement filament grid auto-tuning (fewer filaments = faster, with accuracy check)
3. Add impedance matrix caching (avoid recomputation for same geometry)
4. Parallelize frequency sweeps (use parfor)
5. Implement sparse matrix representation

**Success = Solver <200ms for typical 2-winding case**

**Estimated Effort:** 2-4 weeks
**Key Files:** `peec_solve_frequency.m`, `peec_build_geometry.m`, `validation/` (benchmark data)

---

### Agent #2: Winding Layout Validator
**Problem:** Multi-filar packing fails silently; users find errors post-design

**Solution Steps:**
1. Add pre-flight DRC (wire gauge in database? strands fit in window? clearance OK?)
2. Implement packing efficiency calculator (% core window used)
3. Detect layer overflow, clearance violations
4. Suggest alternative layouts (swap layers, reduce strands)
5. Real-time validation UI feedback

**Success = Catch all packing errors in <100ms; suggest fixes**

**Estimated Effort:** 2-4 weeks
**Key Files:** `build_multifilar_winding.m`, `openmagnetics_winding_layout.m`, wire database JSON

---

### Agent #3: JSON Config Reconciler
**Problem:** 319 JSON files with no validation; corruption reported

**Solution Steps:**
1. Define schemas for all JSON types (om_*, design_export, om_visualization, etc.)
2. Build validator that checks all files against schemas
3. Detect stale entries (cached results older than inputs changed)
4. Generate auto-fix suggestions (remove orphaned configs, reset TTL, etc.)
5. Implement cache coherency checks (A changed, so invalidate B)

**Success = 100% config drift detection; auto-fix suggestions in <100ms**

**Estimated Effort:** 2-3 weeks
**Key Files:** All `.json` files (319 total), MAS schema docs, `openmagnetics_api_interface.m`

---

## 📅 Timeline Example: "I Have 1 Month"

### Week 1 (Mon-Fri)
**Batch 1 Discovery & Setup**
- Mon-Tue: Profile PEEC solver (identify bottlenecks)
- Tue-Wed: Map winding layout code (understand packing algorithm)
- Wed-Thu: Catalog 319 JSON files (schema analysis)
- Thu-Fri: Set up test infrastructure (runner scripts, benchmarks)

### Week 2 (Mon-Fri)
**Batch 1 MVP Development**
- Mon-Tue: Implement PEEC caching layer
- Tue-Wed: Build winding DRC validator
- Wed-Thu: Implement JSON schema validation
- Thu-Fri: Integration testing + refine

### Week 3 (Mon-Fri)
**Batch 2 Start + Batch 1 Polish**
- Mon: Deploy PEEC, Winding, JSON agents
- Tue-Wed: Build test orchestrator
- Thu-Fri: Start wizard state machine fixes

### Week 4 (Mon-Fri)
**Batch 2 Completion + Early Batch 3**
- Mon-Tue: Complete API bridge
- Wed-Thu: Finalize wizard fixes
- Thu-Fri: Start loss visualization / Octave CI

**Result:** Batch 1 + most of Batch 2 done. Users see 3-5x solver speedup, better validation, fixed wizard bugs.

---

## ✅ Success Criteria (Copy-Paste to Your Project Tracker)

### Batch 1 Done When:
- [ ] PEEC solver benchmark <200ms (was 500ms)
- [ ] Winding validator catches 100% of packing failures, <100ms
- [ ] JSON reconciler validates all 319 files, suggests fixes
- [ ] All changes tested against 30+ validation cases (zero regressions)

### Batch 2 Done When:
- [ ] Full validation suite runs in <5 minutes (parallel), visualizes results
- [ ] All 9 wizard bugs fixed (test each transition)
- [ ] API calls centralized; offline fallback tested
- [ ] Caching working (measured with hit rates)

### Batch 3 Done When:
- [ ] Loss visualizations interactive; hotspots identified
- [ ] CI/CD passes on Octave 10.3 + MATLAB 2024a, Windows & Linux
- [ ] Thermal model integrates; hotspot predictions within 5% of measured
- [ ] CAD export generates valid STEP/STL; DFM checks working

---

## 🎓 Understanding the Analysis Documents

### Three Documents Provided:
1. **PROJECT_AGENT_RECOMMENDATIONS.md** (10 pages)
   - Read: Full analysis of each agent, architectural context
   - When: During planning & design

2. **AGENT_PRIORITY_MATRIX.md** (10 pages)
   - Read: Timeline, resource allocation, risk map
   - When: During scheduling & resource planning

3. **AGENT_ANALYSIS_SUMMARY.md** (5 pages)
   - Read: TL;DR of all agents, key metrics
   - When: Executive briefing, stakeholder alignment

4. **AGENT_QUICK_START.md** (this file, 3 pages)
   - Read: Decide which agents to build
   - When: Day 1, project kickoff

---

## 🔗 Related Documentation

In your project (PEEC_Script/ directory):
- `WEB_ARCHITECTURE_AND_WORKFLOWS.md` - Frontend/backend details
- `WIZARD_WORKFLOW_DEEP_DIVE.md` - Specific wizard bugs (agent #5 fixes these)
- `PROJECT_SUMMARY.md` - Project status
- `schema.md` - MAS schema definition (agent #3 uses this)
- `magnetic.md` - PEEC solver details (agent #1 optimizes this)

---

## 💡 Pro Tips

### Tip #1: Parallel Execution is Key
**Batch 1 agents don't depend on each other.** Start all 3 simultaneously (Week 1), not sequentially. This cuts 10+ days off timeline.

### Tip #2: Test Early & Often
Each agent should have unit tests before integration. Use `validation/` directory as your benchmark suite.

### Tip #3: Document as You Go
Agent implementation = documentation opportunity. Update README, API docs, schema docs as you code.

### Tip #4: Measure Everything
Before/after metrics are critical:
- PEEC solver: 0.5s → ? (measure)
- Validation: 30 manual scripts → <5min auto (measure)
- Bugs: 9 wizard gaps → 0 (measure)

### Tip #5: Pick Low-Hanging Fruit First
Within each agent, prioritize quick wins:
- PEEC Optimizer: Start with caching (easy), then sparse matrix (hard)
- JSON Reconciler: Start with schema validation (easy), then lineage tracking (hard)
- Winding Validator: Start with clearance checks (easy), then packing optimization (hard)

---

## 🆘 Stuck? Use This Checklist

**Agent isn't fitting into the timeline?**
- [ ] Are you running agents in parallel? (Batch 1 should be 3 parallel, not sequential)
- [ ] Are you scoping the MVP tightly? (e.g., PEEC Optimizer: just caching, not sparse matrix)
- [ ] Do you have the right tools? (profilers, testing frameworks, schema validators)

**Don't know where to start in the code?**
- [ ] Read the "Key Files" for your agent (listed above)
- [ ] Look for "TODO", "FIXME", "XXX" comments (hints from previous devs)
- [ ] Check `validation/` directory for test cases that exercise the code

**Agent keeps hitting dependencies?**
- [ ] Are you implementing Batch 1 agents in parallel? (They should be independent)
- [ ] Have you built the abstraction layer first? (e.g., API Bridge makes agent #2, #3 cleaner)
- [ ] Can you stub out the dependency and implement it later? (defer, don't block)

---

## 📞 Questions to Ask

1. **For stakeholders:**
   - "Do we prioritize performance (PEEC), reliability (JSON), or quality (Test)?"
   - "What's our timeline? 2, 4, or 8 weeks?"
   - "Which pain point affects users most?"

2. **For architects:**
   - "Can we parallelize Batch 1 agents (3 teams) or do we sequence them (1 team)?"
   - "Do we have profiling tools for PEEC optimizer?"
   - "What's our schema versioning strategy for JSON reconciler?"

3. **For QA/Validation:**
   - "Can we use the 30+ validation scripts as agent benchmarks?"
   - "Do we have measured data to validate thermal integration against?"
   - "Can we set up CI/CD for Octave/MATLAB compatibility?"

---

## 🎯 One-Pager Decision Guide

| If You... | Build This First |
|-----------|------------------|
| Have 2 weeks | Batch 1 (PEEC, Winding, JSON) |
| Have 4 weeks | Batch 1-2 (add Test, Wizard, API) |
| Have 8 weeks | Batch 1-3 (add Loss Viz, CI, Thermal, CAD) |
| Need speed | PEEC Matrix Optimizer (#1) |
| Need reliability | JSON Config Reconciler (#3) |
| Need validation | Test Orchestrator (#4) |
| Need UX fixes | Wizard State Manager (#5) |
| Need code cleanup | API Bridge (#6) |
| Need features | Loss Viz (#7), Thermal (#9), CAD (#10) |
| Need stability | Octave/MATLAB CI (#8) |

---

**Ready to start? Open `AGENT_PRIORITY_MATRIX.md` and pick your Batch.**

---

**Last Updated:** 2026-02-22
**Status:** Ready to use
**Questions?** Review the full analysis docs or the FAQ sections in `PROJECT_AGENT_RECOMMENDATIONS.md`
