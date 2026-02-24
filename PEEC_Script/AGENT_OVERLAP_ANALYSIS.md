# Sub-Agent Overlap & Dependencies Analysis
**Date:** 2026-02-22
**Purpose:** Eliminate functional redundancy, clarify agent responsibilities, provide tools & documentation links

---

## Executive Summary

**Overlap Status:** ✅ Minimal overlap with clear responsibility boundaries
**Dependency Issues:** 3 critical producer-consumer relationships identified
**Missing Tools:** 12 specialized tools need to be listed
**Documentation Gaps:** Enhanced descriptions needed for 7 agents

---

## Part 1: Functional Overlap Analysis

### 1.1 Zero-Overlap Agents (Fully Distinct)
✅ **No responsibility overlap detected**

| Agent | Owns | Does NOT Own |
|-------|------|-------------|
| **PEEC Optimizer** | PEEC matrix assembly, filament discretization, frequency sweep parallelization | Winding layout, web state, visualization |
| **Winding Validator** | Layout packing, wire gauge checks, collision detection, DRC reports | Electromagnetic simulation, web UI, JSON config |
| **JSON Reconciler** | Config validation, schema enforcement, cache coherency, data lineage | Test orchestration, PEEC solving, thermal modeling |
| **Test Orchestrator** | Test discovery, unified runner, regression detection, dashboard | Individual solver implementations, web UI |
| **Web Wizard Manager** | State transitions, parameter passing, route consistency, UI sync | MATLAB/Octave execution, JSON persistence |
| **API Bridge** | OpenMagnetics calls, caching, fallbacks, schema validation | Winding logic, PEEC solving, visualization |
| **Loss Visualization** | Interactive heatmaps, hotspot identification, accuracy validation | Winding design, JSON config, thermal simulation |
| **Thermal Integrator** | Temperature coupling, RC networks, hotspot estimation, IEC checks | Electromagnetic solving, manufacturing, web UI |
| **Octave/MATLAB CI** | Cross-platform testing, linting, performance benchmarking, version management | Business logic of each solver |
| **CAD Export** | STEP/STL generation, DFM checks, cost estimation, vendor integration | Electromagnetic design, thermal analysis, web UI |

---

### 1.2 Minor Overlap Zones (Requires Boundary Clarity)

#### **A. JSON Reconciler ↔ API Bridge**

| Agent | Responsibility |
|-------|-----------------|
| **JSON Reconciler** | Validates *local* JSON files (configs, caches, user designs) against schema |
| **API Bridge** | Manages *remote* OpenMagnetics database; handles schema mismatches with remote API; caches remote data locally |

**Boundary:** JSON Reconciler validates LOCAL state; API Bridge ensures REMOTE↔LOCAL sync consistency.

**Action:** Add explicit note in both agent descriptions:
- JSON Reconciler: "Does NOT manage remote API calls or remote database state"
- API Bridge: "Does NOT validate user-created configs; delegates to JSON Reconciler if needed"

---

#### **B. Loss Visualization ↔ PEEC Optimizer**

| Agent | Responsibility |
|-------|-----------------|
| **PEEC Optimizer** | Improves PEEC solver speed/accuracy; tunes filament grid |
| **Loss Visualization** | Analyzes and displays loss *results*; validates accuracy |

**Boundary:** PEEC Optimizer optimizes the *calculation*; Loss Visualization optimizes the *display* and *analysis* of results.

**Action:**
- PEEC Optimizer: "Focuses on solver performance, NOT visualization"
- Loss Visualization: "Depends on accurate PEEC results; validates solver output"

---

#### **C. Thermal Integrator ↔ PEEC Optimizer**

| Agent | Responsibility |
|-------|-----------------|
| **PEEC Optimizer** | Computes filament-level power loss accurately and quickly |
| **Thermal Integrator** | Uses loss outputs; couples with temperature effects on material properties |

**Boundary:** PEEC is "isothermal"; Thermal layers temperature-dependent effects on top.

**Action:**
- Both agents document: "Thermal Integrator consumes PEEC Optimizer outputs; PEEC Optimizer is temperature-agnostic"

---

#### **D. Test Orchestrator ↔ Octave/MATLAB CI**

| Agent | Responsibility |
|-------|-----------------|
| **Test Orchestrator** | Runs validation scripts, compares results, generates dashboards, detects regressions |
| **Octave/MATLAB CI** | Ensures code compiles/runs across platforms; linting, version compatibility |

**Boundary:** CI validates *compilability* and *syntax*; Test Orchestrator validates *correctness* and *performance*.

**Action:** Document CI as prerequisite to Test Orchestrator:
- Octave/MATLAB CI runs first (pre-commit)
- Test Orchestrator runs second (post-merge)

---

## Part 2: Producer-Consumer Dependencies

### 2.1 Critical Dependency Chain

```
┌─────────────────────┐
│  JSON Reconciler    │  (Data Integrity Gatekeeper)
└──────────┬──────────┘
           ↓ (validates config/cache state)
    ┌──────────────────────────────┬────────────────┬────────────────┐
    ↓                              ↓                ↓                ↓
┌─────────┐                   ┌─────────┐      ┌──────────┐     ┌──────┐
│ PEEC    │                   │ API     │      │ Winding  │     │ Web  │
│Optimizer│                   │Bridge   │      │Validator │     │Wizard│
└────┬────┘                   └────┬────┘      └──────────┘     └──────┘
     ↓ (loss output)               ↓ (remote data)
     │                             │
     └─────────┬────────────────────┘
               ↓
         ┌──────────────────┐
         │ Loss             │
         │ Visualization    │
         └────┬─────────────┘
              ↓
         ┌─────────────────┐
         │ Thermal         │
         │ Integrator      │
         └─────────────────┘
```

**Critical Sequence:**
1. **JSON Reconciler** validates all configs → enables other agents
2. **PEEC Optimizer** + **API Bridge** run in parallel (independent)
3. **Loss Visualization** depends on PEEC output
4. **Thermal Integrator** depends on Loss Visualization

**Action Items:**
- Document explicit input/output contracts for each agent
- Create validation checkpoints between agents
- Add error handling for upstream failures

---

## Part 3: Tools & Documentation Links

### 3.1 Tools Each Agent Needs

#### **Agent 1: PEEC Matrix Optimizer**
**Current Tools:** Basic MATLAB profiler, matrix inspection
**Missing Tools:**
- [ ] **Callgrind/flame graph profiler** - Identify bottleneck functions
- [ ] **Sparse matrix library** (SuiteSparse, ARPACK) - Alternative implementations
- [ ] **FFT-based inductance calculator** - Reference for comparison
- [ ] **Multi-threading library** (parfor, GNU Parallel) - Parallelization framework
- [ ] **Benchmark regression tracker** - Performance trend analysis

**Documentation Links:**
- MathWorks MATLAB Profiler: https://mathworks.com/help/matlab/ref/profiler.html
- Octave profiler: https://octave.org/doc/v10.3.0/Profiling.html
- ARPACK: https://www.caam.rice.edu/software/ARPACK/
- SuiteSparse (KLU): https://people.engr.org/~davis/suitesparse.html

---

#### **Agent 2: Winding Layout & Packing Validator**
**Current Tools:** Basic geometry checks
**Missing Tools:**
- [ ] **Collision detection library** (CGAL, Eigen) - Wire overlap detection
- [ ] **Orthocyclic packing optimizer** - Algorithm reference (Miltenoff, Wallerstein)
- [ ] **IEC 60664-1 insulation database** - Creepage/clearance rules
- [ ] **Visualization library** (VTK, Mayavi) - 3D packing heatmaps
- [ ] **Wire database** (Mogami, Litz tables) - Strand count, resistance per meter
- [ ] **DRC checker** - Design rule checking framework

**Documentation Links:**
- IEC 60664-1 (Insulation Coordination): https://webstore.iec.ch/
- Mogami wire database: https://www.mogami-wire.co.jp/
- CGAL (Collision Detection): https://www.cgal.org/
- VTK visualization: https://vtk.org/

---

#### **Agent 3: JSON Configuration Reconciler**
**Current Tools:** Basic JSON parsing
**Missing Tools:**
- [ ] **JSON Schema validator** (jsonschema, AJV) - Schema enforcement
- [ ] **Data lineage tracker** - Dependency mapping
- [ ] **Diff tools** (deepdiff, jsondiff) - Config comparison
- [ ] **Migration engine** - Schema version upgrades
- [ ] **TTL cache manager** - Cache invalidation logic
- [ ] **Orphaned entry detector** - Stale data cleanup

**Documentation Links:**
- JSON Schema: https://json-schema.org/
- jsonschema Python: https://python-jsonschema.readthedocs.io/
- AJV (JavaScript): https://ajv.js.org/
- DeepDiff: https://deepdiff.readthedocs.io/

---

#### **Agent 4: Multi-Language Test Orchestrator**
**Current Tools:** Manual script invocation
**Missing Tools:**
- [ ] **Test framework abstraction** (pytest, unittest, MUnit) - Unified test runner
- [ ] **Benchmark regression detector** (pytest-benchmark, airspeed-velocity) - Performance trend analysis
- [ ] **Matrix comparison utilities** (numpy.testing, MATLAB `isequal` wrappers) - Tolerance-aware comparison
- [ ] **HTML dashboard generator** (Plotly, Matplotlib) - Result visualization
- [ ] **CI/CD hooks** (GitHub Actions, GitLab CI) - Automated execution
- [ ] **Fallback coordinator** - Local vs HPC backend switching

**Documentation Links:**
- pytest: https://docs.pytest.org/
- MUnit (MATLAB unit tests): https://mathworks.com/help/matlab/unit-testing-framework.html
- airspeed-velocity: https://asv.readthedocs.io/
- pytest-benchmark: https://pytest-benchmark.readthedocs.io/

---

#### **Agent 5: Web Wizard & State Machine Manager**
**Current Tools:** Basic Vue inspection
**Missing Tools:**
- [ ] **State machine validator** (XState, Statecharts) - State graph validation
- [ ] **Async race condition detector** (Jest, Vitest) - Race detection framework
- [ ] **State flow visualizer** (Miro, Graphviz) - Diagram generation
- [ ] **Unit test harness** (Vitest, Jest) - State transition testing
- [ ] **Route consistency checker** - Parameter handoff validation
- [ ] **State reset middleware** - Test isolation

**Documentation Links:**
- XState: https://xstate.js.org/
- Vue Router: https://router.vuejs.org/
- Jest: https://jestjs.io/
- Vitest: https://vitest.dev/

---

#### **Agent 6: OpenMagnetics API & Database Bridge**
**Current Tools:** Direct HTTP calls
**Missing Tools:**
- [ ] **API client library** (requests, httpx, fetch-retry) - Unified HTTP interface
- [ ] **Cache manager** (redis-py, lru_cache) - Intelligent caching
- [ ] **Retry/fallback handler** (tenacity, retry-async) - Resilience patterns
- [ ] **Schema validator** (jsonschema, pydantic) - API response validation
- [ ] **Rate limiter** (ratelimit, slowapi) - API quota management
- [ ] **Local database fallback** (SQLite, JSON file) - Offline mode

**Documentation Links:**
- OpenMagnetics API: https://openmagnetics.com/
- Requests library: https://requests.readthedocs.io/
- Pydantic: https://docs.pydantic.dev/
- Tenacity (retry): https://tenacity.readthedocs.io/

---

#### **Agent 7: Loss Density & Field Visualization**
**Current Tools:** Basic MATLAB plotting
**Missing Tools:**
- [ ] **3D visualization library** (WebGL, Three.js, Plotly 3D) - Interactive heatmaps
- [ ] **Hotspot detector** (scipy.ndimage, skimage) - Peak finding algorithm
- [ ] **ParaView/Tecplot exporter** - Advanced analysis format
- [ ] **SVG generator** (svg.py, D3.js) - Static/interactive exports
- [ ] **Loss decomposition analyzer** (skin vs proximity vs core) - Loss mechanism breakdown
- [ ] **Optimization suggester** - Rule-based recommendations (e.g., "increase wire gauge in layer 3")

**Documentation Links:**
- Three.js: https://threejs.org/
- Plotly 3D: https://plotly.com/python/
- ParaView: https://www.paraview.org/
- scipy.ndimage: https://scipy.org/

---

#### **Agent 8: Thermal Integration & Temperature Rise Estimator**
**Current Tools:** None (new agent)
**Missing Tools:**
- [ ] **Thermal RC network solver** (scipy.linalg, sympy) - Circuit solver
- [ ] **Steinmetz loss model** - Temperature-dependent loss scaling
- [ ] **Material property database** (MPS database, IEC 61248) - Temperature-dependent conductivity, permeability
- [ ] **IEC 60085 validator** - Insulation class temperature limits
- [ ] **3D CFD exporter** (OpenFOAM, ANSYS format) - Thermal boundary conditions
- [ ] **Sensitivity analyzer** (SALib, UQpy) - Parameter sensitivity

**Documentation Links:**
- IEC 60085 (Insulation Classes): https://webstore.iec.ch/
- Steinmetz equation: https://en.wikipedia.org/wiki/Steinmetz%27s_equation
- SALib (Sensitivity Analysis): https://salib.readthedocs.io/
- scipy.linalg: https://scipy.org/

---

#### **Agent 9: Octave/MATLAB Compatibility & CI/CD**
**Current Tools:** Manual testing
**Missing Tools:**
- [ ] **Linter** (Octave Code Analyzer, mlint) - Syntax/style checking
- [ ] **Polyfill library** - Deprecated function wrappers
- [ ] **CI/CD platform** (GitHub Actions, GitLab CI) - Automated testing
- [ ] **Multi-version test matrix** - Octave 10.3, MATLAB 2024a+, Windows/Linux
- [ ] **Performance benchmark suite** (pytest-benchmark) - Regression detection
- [ ] **Dependency manager** (Octave Forge, MATLAB Add-On Explorer) - Package tracking

**Documentation Links:**
- Octave: https://www.gnu.org/software/octave/
- MATLAB Lint (mlint): https://mathworks.com/help/matlab/matlab_env/lint-code.html
- GitHub Actions: https://docs.github.com/en/actions
- Octave Forge: https://octave.sourceforge.io/

---

#### **Agent 10: CAD Export & Manufacturing Integration**
**Current Tools:** None (new agent)
**Missing Tools:**
- [ ] **STEP file writer** (pyassimp, CadQuery, pythonocc) - 3D geometry export
- [ ] **STL file writer** (stl, numpy-stl) - 3D mesh export
- [ ] **DXF writer** (dxfwrite, ezdxf) - 2D winding path export
- [ ] **Tolerance calculator** - Manufacturing tolerance database
- [ ] **Cost estimator** - Material + labor cost model
- [ ] **DFM checker** (Autodesk, Solidworks API) - Manufacturability validation
- [ ] **Vendor integration** (Fair-Rite, Würth APIs) - Component availability

**Documentation Links:**
- CadQuery: https://cadquery.readthedocs.io/
- STEP format: https://en.wikipedia.org/wiki/ISO_10303
- ezdxf: https://ezdxf.readthedocs.io/
- Fair-Rite: https://www.fair-rite.com/
- Würth Elektronik: https://www.we-online.com/

---

## Part 4: Enhanced Agent Descriptions

### Current Issue
All agents have functional descriptions but lack:
1. **Input/Output JSON schemas** - What each agent expects/produces
2. **Error handling specifications** - Failure modes and recovery
3. **Tool dependencies** - Required external libraries
4. **Success criteria** - Measurable acceptance tests
5. **Integration checkpoints** - Where agent fits in workflow

---

### Enhanced Description Template

```markdown
## Agent: [Name]

**Purpose:** [One-line summary]

### 1. Functional Responsibility
[Current description expanded with boundaries]

### 2. Input/Output Contracts
**Inputs:**
- `input_config.json` - Schema: [JSON Schema ref]
- `geometry_struct.mat` - MATLAB struct with fields: [list]

**Outputs:**
- `results_report.json` - Schema: [JSON Schema ref]
- Performance metrics in metrics.csv

### 3. Tool Dependencies
- Required: [Tool 1] ([link](url)), [Tool 2] ([link](url))
- Optional: [Tool 3] ([link](url))

### 4. Error Handling
- **Upstream failure** (missing input): Return structured error with suggestion
- **Timeout**: Graceful degradation to cached result
- **Schema mismatch**: Report specific field differences

### 5. Success Criteria
- [ ] Criterion 1 (quantitative)
- [ ] Criterion 2 (qualitative)

### 6. Integration Points
- Depends on: [Agent X output]
- Feeds into: [Agent Y input]
- Independent: [Agents Z1, Z2]
```

---

## Part 5: Recommended Enhancements

### For Each Agent, Add:

#### **Section A: Input/Output Contracts**

**PEEC Optimizer**
```json
{
  "input": {
    "conductors": "Nx6 array [x,y,w,h,I,phase]",
    "geometry_hints": {
      "complexity_score": "0-100 (auto-computed)",
      "target_speed": "ms per solve"
    }
  },
  "output": {
    "tuned_config": {
      "Nx": "filaments in x",
      "Ny": "filaments in y",
      "cache_hits": "estimated cache hit rate"
    },
    "speedup_estimate": "1.5x baseline"
  }
}
```

**JSON Reconciler**
```json
{
  "input": {
    "config_files": ["path/to/*.json"],
    "schema_version": "2024.02"
  },
  "output": {
    "validation_report": {
      "valid_files": 45,
      "invalid_files": 3,
      "fixes_applied": ["file1.json: field_x removed (orphaned)"]
    }
  }
}
```

---

#### **Section B: Tool Availability & Installation**

Each agent should list:
```markdown
### Required Tools

| Tool | Purpose | Install |
|------|---------|---------|
| jsonschema | Config validation | `pip install jsonschema` |
| pytest-benchmark | Perf regression | `pip install pytest-benchmark` |
```

---

#### **Section C: Failure Modes & Recovery**

```markdown
### Failure Modes

| Mode | Cause | Recovery |
|------|-------|----------|
| "Input geometry missing" | Upstream not ready | Wait, retry with timeout |
| "API timeout" | Network latency | Fall back to cached data |
| "Schema mismatch" | Version drift | Report exact fields, suggest migration |
```

---

## Part 6: Recommended Additions to Each Agent Document

### Add to All 10 Agents:

1. **JSON Input/Output Schemas** - Make contracts explicit
2. **Tool Dependency Matrix** - Table of required/optional tools
3. **Error Handling Spec** - How agent fails and recovers
4. **Success Metrics** - Quantitative acceptance tests
5. **Integration Diagram** - How agent connects to others

---

## Part 7: Non-Overlap Validation

### Checklist: Does Agent X overlap with Agent Y?

For each pair below, answer: **Does Agent X do any of Agent Y's work?**

| Pair | Overlap? | Boundary |
|------|----------|----------|
| PEEC ↔ Winding | ❌ No | PEEC=solver; Winding=layout |
| PEEC ↔ JSON | ❌ No | PEEC=compute; JSON=validation |
| PEEC ↔ Test | ❌ No | PEEC=algorithm; Test=correctness |
| PEEC ↔ Web Wizard | ❌ No | PEEC=backend; Web=frontend |
| PEEC ↔ API Bridge | ❌ No | PEEC=solver; API=database |
| PEEC ↔ Loss Viz | ⚠️ **Minor** | PEEC outputs → Loss visualizes |
| PEEC ↔ Thermal | ⚠️ **Minor** | PEEC outputs → Thermal consumes |
| PEEC ↔ CI | ❌ No | PEEC=logic; CI=infrastructure |
| PEEC ↔ CAD Export | ❌ No | PEEC=design; CAD=output format |
| Winding ↔ JSON | ❌ No | Winding=logic; JSON=storage |
| Winding ↔ Test | ❌ No | Winding=feature; Test=validation |
| Winding ↔ Web Wizard | ⚠️ **Minor** | Winding used in wizard flow |
| Winding ↔ API Bridge | ⚠️ **Minor** | Winding depends on wire database |
| Winding ↔ Loss Viz | ❌ No | Winding=design; Viz=analysis |
| Winding ↔ Thermal | ❌ No | Winding=layout; Thermal=temp |
| Winding ↔ CI | ❌ No | Winding=logic; CI=infra |
| Winding ↔ CAD Export | ⚠️ **Minor** | CAD outputs winding path |
| JSON ↔ Test | ❌ No | JSON=config; Test=validation |
| JSON ↔ Web Wizard | ⚠️ **Minor** | Wizard saves state to JSON |
| JSON ↔ API Bridge | ⚠️ **Minor** | API caches remote data locally |
| JSON ↔ Loss Viz | ❌ No | JSON=config; Viz=output |
| JSON ↔ Thermal | ❌ No | JSON=config; Thermal=compute |
| JSON ↔ CI | ❌ No | JSON=data; CI=testing |
| JSON ↔ CAD Export | ❌ No | JSON=config; CAD=output |
| Test ↔ Web Wizard | ⚠️ **Minor** | Test may validate wizard flows |
| Test ↔ API Bridge | ❌ No | Test=validation; API=data access |
| Test ↔ Loss Viz | ❌ No | Test=correctness; Viz=display |
| Test ↔ Thermal | ❌ No | Test=methodology; Thermal=feature |
| Test ↔ CI | ⚠️ **Minor** | CI runs before/after Test |
| Test ↔ CAD Export | ❌ No | Test=core logic; CAD=output |
| Web Wizard ↔ API Bridge | ⚠️ **Minor** | Wizard calls API Bridge for data |
| Web Wizard ↔ Loss Viz | ⚠️ **Minor** | Wizard may trigger visualization |
| Web Wizard ↔ Thermal | ❌ No | Wizard=UI; Thermal=compute |
| Web Wizard ↔ CI | ❌ No | Wizard=frontend; CI=infra |
| Web Wizard ↔ CAD Export | ⚠️ **Minor** | Wizard may trigger CAD export |
| API Bridge ↔ Loss Viz | ❌ No | API=data; Viz=display |
| API Bridge ↔ Thermal | ❌ No | API=database; Thermal=compute |
| API Bridge ↔ CI | ❌ No | API=logic; CI=testing |
| API Bridge ↔ CAD Export | ❌ No | API=data; CAD=output |
| Loss Viz ↔ Thermal | ⚠️ **Minor** | Thermal may use Viz output |
| Loss Viz ↔ CI | ❌ No | Viz=output; CI=testing |
| Loss Viz ↔ CAD Export | ❌ No | Viz=display; CAD=export |
| Thermal ↔ CI | ❌ No | Thermal=feature; CI=infra |
| Thermal ↔ CAD Export | ⚠️ **Minor** | CAD may export thermal data |
| CI ↔ CAD Export | ❌ No | CI=testing; CAD=output |

**Legend:** ❌ No overlap | ⚠️ Minor (producer-consumer) | 🔴 Major (needs refactoring)

**Result:** ✅ **All overlaps are producer-consumer relationships, not functional duplicates**

---

## Part 8: Recommended Action Items

### Immediate (This Week)
- [ ] Add Input/Output JSON schemas to all 10 agent descriptions
- [ ] Create tool dependency matrix for each agent
- [ ] List error handling spec for each agent
- [ ] Link to external tool documentation

### Short-Term (Next 2 Weeks)
- [ ] Create `AGENT_TOOLS_REGISTRY.md` - Central catalog of all tools with links
- [ ] Create `AGENT_INTEGRATION_DIAGRAM.md` - Visual dependency graph
- [ ] Create `AGENT_FAILURE_MODES.md` - Comprehensive error handling spec
- [ ] Update `PROJECT_AGENT_RECOMMENDATIONS.md` with enhanced templates

### Medium-Term (Month 1)
- [ ] Build stub implementations of input/output validators
- [ ] Create integration tests between agent pairs
- [ ] Document actual tool versions used in each agent
- [ ] Create troubleshooting guide for common failures

---

## Summary Table

| Agent | Overlap Risk | Missing Docs | Missing Tools | Priority |
|-------|-------------|--------------|---------------|----------|
| 1. PEEC Optimizer | 🟢 Low (producer) | Input/output schemas, error handling | 5 tools | High |
| 2. Winding Validator | 🟢 Low | Input/output schemas, DRC rules | 6 tools | High |
| 3. JSON Reconciler | 🟡 Medium (gateway) | Error handling, migration spec | 6 tools | High |
| 4. Test Orchestrator | 🟢 Low | Test framework abstraction, fallback logic | 6 tools | High |
| 5. Web Wizard Manager | 🟡 Medium (UI state) | State flow diagram, test harness | 6 tools | Medium |
| 6. API Bridge | 🟡 Medium (data access) | Retry/fallback logic, rate limiting | 6 tools | Medium |
| 7. Loss Visualization | 🟢 Low (consumer) | Hotspot detection rules, export formats | 6 tools | Medium |
| 8. Thermal Integrator | 🟢 Low (new feature) | All documentation | 6 tools | Medium |
| 9. Octave/MATLAB CI | 🟢 Low (infrastructure) | Compatibility matrix, version pinning | 6 tools | Low |
| 10. CAD Export | 🟢 Low (new feature) | Tolerance specs, DFM rules | 7 tools | Low |

---

**Next Step:** Which agent should we enhance first? Recommend starting with **Agent 3 (JSON Reconciler)** since it's a critical gatekeeper for all others.

