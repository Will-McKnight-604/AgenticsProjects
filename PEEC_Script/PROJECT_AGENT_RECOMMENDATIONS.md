# Project Agent Recommendations
**Analysis Date:** 2026-02-22
**Project:** PEEC Electromagnetic Field Solver + OpenMagnetics Integration
**Scope:** Full-stack system (1162 files, MATLAB/Python/Vue, 3-layer architecture)

---

## Executive Summary

This is a sophisticated electromagnetic design tool combining:
- **MATLAB/Octave engine** - PEEC 2D solver, winding builder, visualization
- **Python bridges** - OpenMagnetics API, recommendation engine, loss pre-screening
- **Vue 3 SPA** - Interactive designer, wizards, cross-referencing tools
- **FastAPI backend** - Plotting, exports, async task queue (Celery), HPC integration

**Key Data Patterns:**
- High-frequency JSON configuration/cache files (319 JSON files)
- Large numerical matrices (PEEC impedance, ~8MB per 1000 filaments)
- Tightly integrated multi-language pipeline (MATLAB → Python → Web)
- Real-time visualization with SVG/3D outputs
- Wizard-driven design workflow with pre-populated parameters
- Validation framework with 30+ benchmark test cases

---

## Part 1: AGENTS BENEFICIAL FOR THIS PROJECT

### 1. **PEEC Matrix Optimizer Agent** ⭐⭐⭐ (High Priority)

**Purpose:** Optimize electromagnetic impedance matrix computations and filament discretization.

**Why It's Needed:**
- PEEC solver (`peec_solve_frequency.m`) is computationally intensive
- Filament count scales as O(n²) in solver complexity
- Current limit: ~10,000 filaments on 16GB systems
- Users need sub-second feedback for interactive design

**Capabilities:**
- Profile PEEC solver bottlenecks (matrix assembly, frequency sweeps)
- Auto-tune filament grid (6×6 default) based on conductor geometry and target accuracy
- Implement sparse matrix representations for multi-frequency sweeps
- Recommend mesh refinement strategies (adaptive vs uniform)
- Cache impedance matrices intelligently for repeated designs
- Parallelize frequency-sweep computations

**Scope:** Mostly MATLAB code in `peec_solve_frequency.m`, `peec_build_geometry.m`, interaction with `kernels/` (C++ Eigen bindings)

**Transferability:** 🟢 Very High
- Matrix optimization patterns apply to all FEM/PEEC-based solvers
- Filament discretization heuristics useful for any 3D conductor analysis
- Caching strategies transferable to scientific computing generally
- Multi-frequency sweep parallelization applies to frequency response analysis everywhere

---

### 2. **Winding Layout & Packing Validator Agent** ⭐⭐⭐ (High Priority)

**Purpose:** Validate and optimize multi-filar conductor layouts, orthocyclic packing, and vertical stacking.

**Why It's Needed:**
- Multi-filar generation (`build_multifilar_winding.m`) is complex and error-prone
- Packing validation (`openmagnetics_winding_layout.m`) has silent failures
- No real-time feedback on packing efficiency or clearance violations
- Users manually verify layouts for feasibility

**Capabilities:**
- Pre-flight validation: check wire gauge, strand count, core window fit
- Detect packing failures early (layer overflow, clearance violations)
- Suggest alternative winding strategies (swap layers, reduce strands)
- Visualize packing density heatmaps
- Compare orthocyclic vs random vs layered packing efficiency
- Integrate with IEC insulation standards (creepage/clearance rules)
- Generate DRC (design rule check) reports

**Scope:** MATLAB files: `build_multifilar_winding.m`, `openmagnetics_winding_layout.m`, visualization in `plot_*.m`

**Transferability:** 🟢 Very High
- Packing optimization applies to multi-strand wires, PCB routing, 3D bin packing
- Constraint validation frameworks transferable to design rule checking
- Visualization heatmaps useful for any density/stress analysis
- Geometry collision detection applies broadly

---

### 3. **JSON Configuration & Cache Reconciliation Agent** ⭐⭐⭐ (High Priority)

**Purpose:** Detect and resolve inconsistencies in JSON config/cache files; manage database corruption.

**Why It's Needed:**
- 319 JSON files across configs, caches, and exports
- Reported corruption in `openmagnetics_api_interface.m`
- No validation of database integrity
- Cache invalidation logic unclear
- Users may see stale or contradictory data

**Capabilities:**
- Validate JSON against MAS schema and custom schemas
- Detect orphaned/stale cache entries vs current design state
- Compare configs before/after wizard handoff
- Reconcile wire/core database versions
- Generate validation reports with auto-fix suggestions
- Implement cache coherency checks (TTL, dependency tracking)
- Detect schema migrations and handle backwards compatibility
- Provide data lineage (which designs depend on which configs)

**Scope:** All JSON files, especially in root and `validation/results*/` directories

**Transferability:** 🟢 Very High
- JSON schema validation applies to any config-driven system
- Cache reconciliation patterns transferable to build systems, caching layers
- Data lineage tracking useful for dependency analysis, debug workflows
- Migration management applies to database upgrades everywhere

---

### 4. **Multi-Language Test & Validation Orchestrator Agent** ⭐⭐ (High Priority)

**Purpose:** Streamline 30+ validation/benchmark scripts; unify testing across MATLAB/Python/Web.

**Why It's Needed:**
- 30+ validation scripts scattered across `validation/` directory
- Manual invocation and result comparison (FFT, MAS, hyperband, real cases)
- No unified reporting (pass/fail rates, performance regression detection)
- Octave version incompatibilities not systematically checked
- Test maintenance burden high (duplicate setup logic)

**Capabilities:**
- Auto-discover and catalog all test/validation scripts
- Create unified test runner (skip/run/parallel execution)
- Abstract test input/output patterns (FFT vs MAS vs hyperband)
- Unified reporting: accuracy vs reference, runtime, solver tuning curves
- Detect performance regressions across commits
- Matrix comparison utilities (tolerance, rel/abs error)
- Generate HTML dashboards showing benchmark trends
- Implement CI/CD hooks for continuous validation
- Fallback to local testing if HPC backend unavailable

**Scope:** `validation/` directory (30+ scripts), `test_*.m` files, integration with backend

**Transferability:** 🟢 Very High
- Multi-language test orchestration applies to microservice stacks, polyglot projects
- Benchmark regression detection applies to performance-critical systems
- Unified reporting frameworks transferable to observability systems
- CI/CD integration patterns universal

---

### 5. **OpenMagnetics API & Database Bridge Agent** ⭐⭐ (Medium Priority)

**Purpose:** Manage API calls to OpenMagnetics; handle database queries, schema validation, fallback strategies.

**Why It's Needed:**
- `openmagnetics_api_interface.m` needs debugging/restoration
- Multiple Python files independently call OpenMagnetics APIs
- No centralized error handling or retry logic
- Supplier database access limited
- Cache invalidation unpredictable
- Schema version mismatches with MAS format

**Capabilities:**
- Unify API calls across Python/MATLAB layers
- Implement intelligent caching (separate wire/core/material DBs)
- Handle API timeouts, retries, fallback to local JSON databases
- Validate responses against MAS schema before use
- Detect breaking changes in remote schemas
- Provide offline mode (pre-cached database fallback)
- Rate-limit API calls intelligently
- Generate API usage statistics/logs

**Scope:** MATLAB: `openmagnetics_api_interface.m`, Python: `*.py` files that call OpenMagnetics

**Transferability:** 🟢 High
- API bridge patterns apply to any multi-service architecture
- Caching strategies transferable to CDN/cache layers
- Schema validation applies to API integrations everywhere
- Offline fallback patterns useful for resilience engineering

---

### 6. **Web Wizard & State Machine Manager Agent** ⭐⭐ (Medium Priority)

**Purpose:** Debug and optimize wizard workflows; manage state transitions between wizards and designer.

**Why It's Needed:**
- 9 gaps/inconsistencies documented in `WIZARD_WORKFLOW_DEEP_DIVE.md`
- Landing vs header launcher mismatch (Coming Soon claims vs actual exposure)
- Async race conditions in process() calls
- CMC/DMC use legacy layout (different from converter base)
- Forward wizard parameter mismatches
- Engine-loader gating doesn't reset tool state consistently

**Capabilities:**
- State machine visualization and validation (Xstate, Miro diagrams)
- Detect unreachable states, deadlocks, race conditions
- Unit test wizard transitions and parameter passing
- Validate handoff integrity (wizard → designer parameter mapping)
- Compare legacy vs modern wizard UI patterns
- Generate state flow documentation
- Implement state reset middleware
- Debug parameter loss across route transitions

**Scope:** Vue components in `WebFrontend-main/src/components/Wizards/`, `views/Wizards*.vue`, Pinia stores

**Transferability:** 🟢 High
- State machine patterns apply to any workflow automation system
- UI/UX consistency checking frameworks transferable to design systems
- Async/await race condition detection useful for any async-heavy frontend
- Test harnesses for state transitions apply to state management libraries

---

### 7. **Loss Density & Field Visualization Agent** ⭐⭐ (Medium Priority)

**Purpose:** Enhance loss visualization, accuracy validation, and optimization recommendations.

**Why It's Needed:**
- Current loss/field visualization is 2D static images
- No validation of loss calculation accuracy vs measured data
- Loss density plots don't highlight high-loss regions (yet)
- Visualization doesn't guide optimization (e.g., "increase wire gauge in layer 3")
- SVG exports are static (no interactivity)

**Capabilities:**
- Validate loss calculations against reference data
- Generate interactive loss density heatmaps (3D exploration)
- Identify loss hotspots and suggest remedies
- Optimize winding arrangement to minimize loss
- Compare loss distribution across multi-filar configurations
- Generate CAM-ready visualization for manufacturing
- Provide loss breakdown by mechanism (skin, proximity, core)
- Export to ParaView/Tecplot for advanced analysis

**Scope:** MATLAB: `plot_loss_density.m`, `plot_current_density.m`, Python: `generate_om_visualization.py`, Web: loss display components

**Transferability:** 🟢 Medium
- Field visualization patterns apply to any FEM/FEA solver (CFD, structural, thermal)
- Hotspot detection algorithms apply to heat dissipation analysis
- Optimization suggestion frameworks useful for any design tool
- Interactive visualization frameworks (WebGL, VTK, ParaView) broadly applicable

---

### 8. **Thermal Integration & Temperature Rise Estimator Agent** ⭐ (Medium Priority - Future Work)

**Purpose:** Add temperature-aware loss calculations, thermal constraint checking, ambient parameter propagation.

**Why It's Needed:**
- Current loss models assume isothermal conditions
- Ambient temperature stored but not used in loss calculations
- No thermal circuit model (hotspot rise, convection, core heat dissipation)
- Users cannot assess thermal margins in designs
- Efficiency varies significantly with temperature (not captured)
- Future roadmap explicitly mentions "thermal integration"

**Capabilities:**
- Implement loss-temperature coupling (Steinmetz scaling with T)
- Build thermal RC network (core, windings, ambient)
- Estimate winding hotspot temperature
- Generate thermal margins report vs insulation class
- Optimize thermal design (add cooling, increase wire gauge)
- Validate against IEC 60085 temperature limits
- Export thermal data for 3D CFD (boundary conditions)
- Sensitivity analysis: thermal performance vs design parameters

**Scope:** New code (mostly), interfaces with existing loss calculations

**Transferability:** 🟢 High
- Thermal modeling applies to any heat-generating component (motors, converters, CPUs, etc.)
- Temperature-dependent material properties transferable to materials science tools
- Thermal constraint checking applies to mechanical design, CFD, IC layout
- RC thermal networks are standard across embedded systems, automotive, power electronics

---

### 9. **Octave/MATLAB Compatibility & CI/CD Agent** ⭐ (Low-Medium Priority)

**Purpose:** Ensure code compatibility across Octave 10.3+ and MATLAB; automate validation.

**Why It's Needed:**
- Project runs on Octave (open-source) but aims MATLAB compatibility
- Some functions deprecated or missing in Octave (`validateattributes`, etc.)
- No automated compatibility testing in CI/CD
- Windows/Linux path handling inconsistencies
- C++ kernel compilation not tested in CI
- User environment variations not tracked

**Capabilities:**
- Linter for Octave vs MATLAB syntax differences
- Automated multi-platform test matrix (Octave 10.3, MATLAB 2024a+, Windows/Linux)
- Polyfill library for deprecated functions
- CI/CD pipeline setup (GitHub Actions, GitLab CI)
- Performance regression testing (timing benchmarks)
- Automated bug report generation when tests fail
- Version pinning and dependency management (Octave packages, MATLAB toolboxes)

**Scope:** All MATLAB files, build configuration, CI/CD

**Transferability:** 🟢 High
- Compatibility testing applies to any multi-version or multi-platform codebase
- CI/CD patterns universal
- Linting frameworks apply to any language
- Performance benchmarking applies broadly

---

### 10. **CAD Export & Manufacturing Integration Agent** ⭐ (Low Priority - Planned Feature)

**Purpose:** Export designs to STEP/STL; validate manufacturability.

**Why It's Needed:**
- Roadmap includes "CAD export (STEP, STL)"
- No current mechanism to transfer digital design to manufacturing
- Users manually model core/winding geometry in CAD
- No DFM (design for manufacturing) checks

**Capabilities:**
- Export core geometry to STEP (ready for machining/FEA)
- Export winding path to DXF (PCB coil, 3D winding guide)
- Generate manufacturing drawings with tolerances
- Check manufacturability (wire gauge availability, winding feasibility)
- Estimate production cost (material + labor)
- Generate test plans (winding continuity, insulation breakdown, inductance measurement)
- Integrate with vendor design tools (Fair-Rite, Würth, etc.)

**Scope:** New agent; interfaces with existing geometry builders

**Transferability:** 🟢 Medium
- CAD export patterns apply to any design tool (EDA, PCB, mechanical)
- DFM checking frameworks useful across manufacturing domains
- Manufacturing integration applies to supply chain systems

---

## Part 2: AGENTS BENEFICIAL FOR OTHER CODING PROJECTS

Below are the top agents with broad applicability across engineering/scientific software:

### **Tier 1: Universally Applicable (Use in 80%+ of Projects)**

#### A. **JSON Schema Validator & Auto-Fixer Agent**
- Validates configs against schemas, detects stale entries, suggests fixes
- **Applies to:** Config-driven systems, microservices, data pipelines, CI/CD
- **Examples:** Kubernetes configs, Terraform plans, GitHub Actions workflows, API specs

#### B. **Multi-Language Test Orchestrator Agent**
- Unified test runner across languages, regression detection, dashboard reporting
- **Applies to:** Polyglot codebases, microservices, research codebases
- **Examples:** Java+Python services, MATLAB+C++ projects, Node+Go backends

#### C. **State Machine Validator & Debugger Agent**
- Detects unreachable states, race conditions, deadlocks in workflows
- **Applies to:** Event-driven systems, workflow engines, UI state management
- **Examples:** Kafka pipelines, Redux/Vuex stores, Temporal workflows, async state machines

#### D. **API Bridge & Caching Orchestrator Agent**
- Unifies multi-service API calls, intelligent caching, fallback strategies
- **Applies to:** Distributed systems, integration layers, resilience engineering
- **Examples:** Microservice middleware, data lake aggregators, federated queries

#### E. **Data Lineage & Dependency Tracer Agent**
- Maps data/config flow through system; detects stale/orphaned entries
- **Applies to:** Data pipelines, scientific workflows, build systems
- **Examples:** dbt projects, Nextflow pipelines, Make/Bazel dependency graphs

---

### **Tier 2: Domain-Specific but Transferable (Use in 30-50% of Projects)**

#### F. **Performance Regression Detector Agent**
- Benchmarking, trend analysis, anomaly detection
- **Applies to:** Performance-critical systems, scientific computing, real-time systems
- **Examples:** ML model training, database query optimization, game engine optimization

#### G. **Numerical Solver & Matrix Optimizer Agent**
- Profiles compute bottlenecks, tunes algorithm parameters, caching strategies
- **Applies to:** Scientific computing, ML, robotics, physics simulation
- **Examples:** TensorFlow/PyTorch optimization, finite element analysis, CFD solvers

#### H. **Interactive Visualization & Hotspot Analyzer Agent**
- Generates heatmaps, 3D visualizations, identifies optimization regions
- **Applies to:** FEM/FEA tools, data exploration, HPC visualization
- **Examples:** ParaView/Tecplot post-processing, thermal/stress analysis, ML activation maps

#### I. **Thermal/Physics Simulation Integrator Agent**
- Couples multi-physics models, implements material property tables, constraint checking
- **Applies to:** Multiphysics tools, embedded systems, automotive/aerospace
- **Examples:** Thermal management systems, battery modeling, structural-thermal coupling

#### J. **Multi-Platform Compatibility Agent**
- Tests across OS/language versions, auto-fixes compatibility, CI/CD setup
- **Applies to:** Cross-platform libraries, open-source projects, embedded systems
- **Examples:** C/C++ libraries, Python packages, web frameworks

---

### **Tier 3: Specialized (Use in 10-30% of Projects)**

#### K. **Manufacturing Integration & DFM Checker Agent**
- CAD export, tolerances, cost estimation, vendor integration
- **Applies to:** Hardware design tools, embedded systems, IoT
- **Examples:** PCB design tools, 3D printing workflows, industrial automation

#### L. **Markdown & Documentation Analyzer Agent**
- Validates docs consistency, auto-generates API reference, catches outdated examples
- **Applies to:** Any well-documented project
- **Examples:** API docs, research papers, software architecture docs

#### M. **Jupyter Notebook Quality Agent**
- Checks reproducibility, detects stale kernels, validates dependencies
- **Applies to:** Data science, research, educational content
- **Examples:** ML tutorials, research notebooks, data analysis workflows

---

## Part 3: RECOMMENDED AGENT STACK FOR THIS PROJECT

### **Phase 1 (Immediate - Months 1-2)**
Priority: Solve critical bottlenecks and validation gaps

1. **PEEC Matrix Optimizer** - Unlock real-time feedback at scale
2. **JSON Configuration Reconciler** - Restore data integrity
3. **Multi-Language Test Orchestrator** - Unified validation
4. **Winding Layout Validator** - Catch packing errors early

### **Phase 2 (Short-Term - Months 2-4)**
Priority: Improve UX and reduce manual effort

5. **Web Wizard State Machine Manager** - Fix documented gaps
6. **OpenMagnetics API Bridge** - Centralize database/API logic
7. **Loss Visualization Enhancer** - Interactive hotspot analysis
8. **Octave/MATLAB Compatibility** - Ensure cross-platform stability

### **Phase 3 (Medium-Term - Months 4-6)**
Priority: Advanced features and manufacturing integration

9. **Thermal Integration Simulator** - Temperature-aware design
10. **CAD Export & DFM Checker** - Manufacturing readiness

---

## Part 4: IMPLEMENTATION ROADMAP

### For Each Agent:

1. **Discovery Phase** (1-2 weeks)
   - Map existing code patterns
   - Identify data flows and failure modes
   - Scope first MVP

2. **MVP Development** (2-4 weeks)
   - Core functionality (e.g., validator for JSON, runner for tests)
   - Unit tests within agent's domain
   - Integration test with one actual project component

3. **Integration Phase** (1-2 weeks)
   - Connect to main workflow
   - Add hooks/callbacks
   - Real-world validation

4. **Documentation & Handoff** (1 week)
   - Usage guide
   - Architecture diagram
   - Maintenance notes

---

## Part 5: KEY METRICS FOR AGENT SUCCESS

### Quantitative
- **PEEC Optimizer:** Reduce solver time from 0.5s → 0.1s for typical 2-winding case
- **Test Orchestrator:** Run full validation suite in <5 minutes (parallel), visualize 30+ results
- **JSON Reconciler:** Detect 100% of config drift; suggest fixes in <100ms
- **State Machine Validator:** Catch all wizard transition bugs pre-deployment

### Qualitative
- Users report "faster feedback loops"
- Manual validation steps drop by 70%
- Fewer bug reports about data inconsistency
- Confidence in cross-platform (Octave/MATLAB) compatibility increases

---

## Part 6: RISK MITIGATION

### Key Risks & Mitigation Strategies

| Risk | Mitigation |
|------|-----------|
| PEEC matrix optimization breaks solver accuracy | Regression testing against all 30+ validation cases before merge |
| JSON schema changes break agent validation | Version-aware schema loading; detect breaking changes; alert user |
| Multi-language test orchestrator has false positives | Calibrate tolerances using known-good baseline; manual review of first 10 failures |
| Wizard state machine changes break existing workflows | State flow unit tests; manual QA through all 16 wizard types |
| Thermal simulator gives inaccurate hotspot predictions | Validate against measured data from 3+ transformer designs |

---

## Appendix: File Organization for Agents

### Agent-to-Codebase Mapping

**PEEC Matrix Optimizer**
- Primary: `PEEC_Script/peec_solve_frequency.m`, `peec_build_geometry.m`
- Secondary: `kernels/` (C++ interface), `validation/results*/` (benchmark data)

**Winding Layout Validator**
- Primary: `PEEC_Script/build_multifilar_winding.m`, `openmagnetics_winding_layout.m`
- Secondary: `plot_*.m` (visualization), OpenMagnetics wire database

**JSON Configuration Reconciler**
- Primary: Root `.json` files (319 total), especially `om_*.json`, `openmagnetics_*.json`
- Secondary: MAS schema docs, `validation/` test cases

**Multi-Language Test Orchestrator**
- Primary: `validation/` directory (30+ scripts), `test_*.m` files, Python test files
- Secondary: CI/CD config (none currently; create new)

**OpenMagnetics API Bridge**
- Primary: `openmagnetics_api_interface.m`, Python files (`*.py` with API calls)
- Secondary: OpenMagnetics database JSON files, MAS schema

**Web Wizard State Manager**
- Primary: `WebFrontend-main/src/components/Wizards/`, `src/views/Wizards*.vue`
- Secondary: `src/stores/` (Pinia state), `src/router/` (routing logic)

**Loss Visualization**
- Primary: `plot_loss_density.m`, `plot_current_density.m`, `generate_om_visualization.py`
- Secondary: SVG export logic, field solver results

**Thermal Integration**
- Primary: New code (design interface with loss calculations)
- Secondary: Material database JSON files, IEC 60085 standard references

**Octave/MATLAB Compatibility**
- Primary: All `*.m` files, C++ kernel build config
- Secondary: CI/CD config (create new), version matrices

**CAD Export & DFM**
- Primary: New code (STEP/STL writers)
- Secondary: Core geometry builders, manufacturing tolerances database

---

**End of Report**

This analysis provides a complete blueprint for building agents that solve real problems in this project while transferring knowledge to 100+ other engineering codebases.
