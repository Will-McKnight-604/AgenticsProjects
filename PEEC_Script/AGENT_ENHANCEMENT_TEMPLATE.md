# Agent Enhancement Template
## How to Enhance Agents 1-10 Following Agent 3 Pattern

**Purpose:** Use this template to enhance remaining 9 agents in consistent format
**Based On:** AGENT_3_JSON_RECONCILER_ENHANCED.md
**Status:** Template Complete - Ready for Agents 1, 2, 4-10

---

## Quick Start: Copy-Paste Structure

For each agent (1, 2, 4-10), create a file:
```
AGENT_[N]_[AGENT_NAME]_ENHANCED.md
```

Then fill in sections 1-12 following this structure:

---

## Section-by-Section Instructions

### Section 1: FUNCTIONAL RESPONSIBILITY (10-15 minutes)

**What to include:**
- [ ] 1.1 Purpose (One-Liner) - Copy from PROJECT_AGENT_RECOMMENDATIONS.md
- [ ] 1.2 Problem Statement (2-3 paragraphs)
  - What's broken or missing
  - How many files/systems affected
  - User pain points
- [ ] 1.3 Scope Definition
  - What's IN SCOPE (this agent)
  - What's OUT OF SCOPE (other agents)
  - Clear boundaries with neighboring agents
- [ ] 1.4 Agent Boundaries
  - Upstream dependency (if any)
  - Downstream consumers (list agents)
  - Independent agents (list agents)

**Agent-Specific Tips:**

**Agent 1 (PEEC Optimizer):**
```
1.2 Problem: PEEC solver takes 0.5s per solve; filament count scales O(n²)
    Current limit: 10,000 filaments on 16GB systems
    User pain: 3+ second wait for interactive feedback is too slow

1.3 IN SCOPE: Matrix assembly, filament discretization, frequency sweeps
    OUT OF SCOPE: Winding design (Agent 2), visualization (Agent 7)
```

**Agent 2 (Winding Validator):**
```
1.2 Problem: Packing validation fails silently; users don't know if winding
    will actually fit in core window; 30+ winding configurations possible
    Current limit: No early DRC checks; errors found during manufacturing

1.3 IN SCOPE: Layout packing, clearance checks, constraint validation
    OUT OF SCOPE: Loss calculations (Agent 1), JSON config (Agent 3)
```

**Agent 4 (Test Orchestrator):**
```
1.2 Problem: 30+ validation scripts scattered across validation/ directory;
    manual invocation and result comparison; no unified pass/fail reporting
    Current limit: Takes 1+ hour to run all tests manually

1.3 IN SCOPE: Test discovery, unification, reporting, regression detection
    OUT OF SCOPE: Individual solver implementations (Agents 1-2, 5-7)
```

---

### Section 2: INPUT/OUTPUT CONTRACTS (15-25 minutes)

**Key Pattern:**
1. Define 3-4 input types (specific use cases)
2. For each input, provide:
   - JSON schema with field definitions
   - Real example
3. Define 2-3 output types with:
   - Full JSON structure
   - Real example output
   - Success/warning/error cases

**Tools to Help:**
- Use JSON Schema draft 2020-12 syntax
- https://json-schema.org/understanding-json-schema/
- https://jsonschema.net/ (schema generator from JSON examples)

**Agent-Specific Inputs:**

**Agent 1 (PEEC Optimizer):**
```
Input Type 1: Solver Request
{
  "geometry": {
    "conductors": "Nx6 array [x,y,w,h,I,phase]",
    "frequency_hz": "number (1k-10MHz)",
    "target_accuracy": "loss_percent (0-5)",
    "timeout_seconds": "number (1-60)"
  }
}

Output Type 1: Solver Result
{
  "solver_result": {
    "loss_watts": "number",
    "impedance": "Nf x Nf matrix",
    "runtime_seconds": "number",
    "speedup_vs_baseline": "1.5x",
    "filament_grid": {"Nx": 6, "Ny": 6}
  }
}
```

**Agent 2 (Winding Validator):**
```
Input Type 1: Winding Layout
{
  "winding_layout": {
    "core_window": {"width_mm": 10.5, "height_mm": 8.2},
    "layers": [
      {
        "wire_gauge": "AWG_28",
        "turns": 100,
        "strand_count": 44,
        "packing": "orthocyclic | random | layered"
      }
    ]
  }
}

Output Type 1: Packing Report
{
  "packing_report": {
    "status": "fits | exceeds | warning",
    "space_utilized_percent": 78,
    "violations": [
      {
        "layer": 1,
        "turn": 42,
        "issue": "insufficient_clearance",
        "distance_mm": 0.2,
        "required_mm": 0.5
      }
    ]
  }
}
```

**Agent 4 (Test Orchestrator):**
```
Input Type 1: Test Suite Request
{
  "test_suite": {
    "test_directories": ["validation/", "test_*.m"],
    "filters": {
      "tags": ["regression", "accuracy"],
      "exclude_slow": false
    },
    "parallel": true,
    "max_workers": 4
  }
}

Output Type 1: Test Report
{
  "test_report": {
    "total_tests": 147,
    "passed": 140,
    "failed": 5,
    "skipped": 2,
    "runtime_seconds": 245,
    "regressions": [
      {
        "test": "test_peec_solver_accuracy",
        "expected": 0.5,
        "actual": 1.2,
        "severity": "error"
      }
    ]
  }
}
```

---

### Section 3: REQUIRED TOOLS (10-15 minutes)

**Standard Format:**
1. Create table with 6-7 core tools (required)
2. Create table with 2-4 optional tools (nice-to-have)
3. List installation commands
4. Note minimum viable setup

**Common Tools by Agent Type:**
```
Scientific (Agents 1, 7, 8):
  - NumPy, SciPy, Matplotlib, Plotly

Validation (Agents 2, 3, 4):
  - jsonschema, Pydantic, pytest

Web (Agent 5):
  - Vue.js, Vitest, Three.js

Infrastructure (Agents 9, 10):
  - GitHub Actions, STEP/STL writers
```

**Copy from AGENT_TOOLS_REGISTRY.md:**
- Look up your agent's tools
- Copy tool names + docs links
- Paste into Section 3

**Example for Agent 1:**
```
Core Tools:
  1. MATLAB/Octave Profiler - https://mathworks.com/help/matlab/ref/profiler.html
  2. SuiteSparse - https://people.engr.org/~davis/suitesparse.html
  3. NumPy - https://numpy.org/
  4. pytest-benchmark - https://pytest-benchmark.readthedocs.io/
  5. Plotly - https://plotly.com/

Installation:
pip install numpy scipy pytest-benchmark plotly
```

---

### Section 4: ERROR HANDLING (30-45 minutes)

**Critical:** This is the most important section

**Pattern for Each Failure Mode:**
1. **Trigger** - What causes this error?
2. **Error Message** - Exact text user sees (be specific!)
3. **Recovery Strategy** - What the agent does
4. **Code Example** - Show how to implement

**Steps:**
1. List 6-8 common failure modes for your agent
2. For each, fill in Trigger/Message/Strategy/Code
3. Create error handling matrix (bottom of section)

**Agent-Specific Failure Modes:**

**Agent 1 (PEEC Optimizer):**
```
Failure Mode 1: Geometry Singularity
  Trigger: Two filaments at same location (distance < epsilon)
  Error: "Cannot invert impedance matrix (singular)"
  Recovery: Adjust filament grid, retry

Failure Mode 2: Timeout
  Trigger: Large geometry, solver exceeds time budget
  Error: "Solver timeout (30s max)"
  Recovery: Use cached result or coarse grid

Failure Mode 3: Out of Memory
  Trigger: >10,000 filaments on 16GB system
  Error: "Matrix too large for available memory"
  Recovery: Suggest reducing filament count or upgrading RAM
```

**Agent 2 (Winding Validator):**
```
Failure Mode 1: Insufficient Space
  Trigger: Winding layer doesn't fit in core window
  Error: "Layer exceeds window: 12mm > 10mm"
  Recovery: Suggest reducing turns or using thinner wire

Failure Mode 2: Wire Not Found
  Trigger: Requested wire gauge doesn't exist
  Error: "Wire gauge AWG_99 not found in database"
  Recovery: List available gauges, suggest closest match
```

**Agent 4 (Test Orchestrator):**
```
Failure Mode 1: Test File Not Found
  Trigger: Test script deleted or moved
  Error: "Test file validation/test_peec.m not found"
  Recovery: Auto-discover tests, skip missing files with warning

Failure Mode 2: Solver Crash
  Trigger: PEEC solver segfaults during test
  Error: "Test process exited with code 139 (SIGSEGV)"
  Recovery: Retry with coarse grid, mark test as flaky
```

---

### Section 5: SUCCESS CRITERIA (10-15 minutes)

**What to Include:**
- [ ] 5.1 Quantitative Metrics (5-7 metrics with targets)
- [ ] 5.2 Qualitative Criteria (bullet list, 7-8 items)
- [ ] 5.3 Acceptance Tests (5-6 code examples using pytest)

**Template for Metrics:**

| Metric | Target | How to Measure |
|--------|--------|-----------------|
| **Speed** | <Xs per [unit] | Run benchmark, time with stopwatch |
| **Accuracy** | >X% correct | Compare output against known-good baseline |
| **Completeness** | X% features working | Checklist of required capabilities |
| **Reliability** | X% success rate | Run 100 times, count failures |

**Agent-Specific Examples:**

**Agent 1 (PEEC Optimizer):**
```
| Metric | Target | How |
|--------|--------|-----|
| **Speedup** | >2x vs baseline | Time solver before/after optimization |
| **Accuracy** | <0.5% loss error | Compare vs reference solutions |
| **Scalability** | 10k filaments in <1s | Test on max geometry |
```

**Agent 2 (Winding Validator):**
```
| Metric | Target | How |
|--------|--------|-----|
| **Detection Rate** | 100% packing violations | Create 50 invalid layouts, validate all detected |
| **False Positives** | <1% | Valid layouts incorrectly flagged |
| **Performance** | <100ms per layout | Time validation on complex geometries |
```

**Agent 4 (Test Orchestrator):**
```
| Metric | Target | How |
|--------|--------|-----|
| **Test Speed** | <5min for 147 tests | Time full test suite |
| **Regression Detection** | 100% accuracy | Intentionally break code, verify detection |
| **Report Clarity** | >95% understand failures | User feedback on error messages |
```

---

### Section 6: INTEGRATION POINTS (10-15 minutes)

**Standard Sections:**
- [ ] 6.1 Upstream Dependencies (what feeds into this agent)
- [ ] 6.2 Downstream Consumers (what does this agent feed)
- [ ] 6.3 Data Flow Diagram (ASCII art showing information flow)
- [ ] 6.4 Integration Test Scenario (step-by-step walkthrough)

**Key Questions:**
- Which agents call this agent's API?
- What data format do they expect?
- What happens if this agent fails?
- Can this agent run in parallel with others?

**Agent-Specific Integration:**

**Agent 1 (PEEC Optimizer):**
```
Upstream: JSON Reconciler (validates config) → PEEC Optimizer
Downstream: Loss Visualization (uses loss output), Thermal (uses loss)
Parallel with: Agent 2 (Winding Validator)
```

**Agent 4 (Test Orchestrator):**
```
Upstream: Octave/MATLAB CI (compiles code)
Downstream: Dashboard display, regression alerts
Triggered by: CI/CD pipeline, developer request
```

---

### Section 7: IMPLEMENTATION ROADMAP (15-20 minutes)

**Copy Structure from Agent 3:**
1. **Phase 1: Discovery** (2-3 days)
   - What to audit/explore
   - Key deliverables

2. **Phase 2: MVP Development** (2-3 weeks)
   - Break into 2-3 sprints
   - Specific deliverables per sprint

3. **Phase 3: Integration** (3-4 days)
   - Wire into downstream agents
   - Integration tests

4. **Phase 4: Documentation** (1 week)
   - Usage guide, examples
   - Architecture docs

**Agent-Specific Timeline:**

**Agent 1 (PEEC Optimizer):**
```
Phase 1: Profile solver (identify bottlenecks)
Phase 2a: Implement SuiteSparse interface
Phase 2b: Implement caching layer
Phase 2c: Implement frequency sweep parallelization
Phase 3: Integrate into PEEC pipeline
Phase 4: Docs + performance tuning guide
```

**Agent 2 (Winding Validator):**
```
Phase 1: Audit winding algorithms
Phase 2a: Build collision detection
Phase 2b: Implement DRC checker
Phase 2c: Add IEC clearance rules
Phase 3: Integrate into wizard
Phase 4: Create validation rule library
```

---

### Section 8: TOOLS SETUP CHECKLIST (5 minutes)

**Template:**
```bash
# Install core tools
pip install [tool1] [tool2] [tool3]

# Verify installation
python -c "import [tool1], [tool2]; print('✅ Tools ready')"

# Optional: virtual environment
python -m venv venv_agent[N]
source venv_agent[N]/bin/activate
```

---

### Section 9: KEY FILES & LOCATIONS (5 minutes)

**Standard Structure:**
```
PEEC_Script/
├── AGENT_[N]_[name].py          (implementation)
├── test_agent_[N].py            (unit tests)
└── validation/
    └── agent_[N]_results/       (output directory)
```

**Agent-Specific Locations:**

**Agent 1:**
```
peec_solve_frequency.m            (main solver)
kernels/                          (C++ bindings)
validation/results_*/             (benchmark data)
```

**Agent 2:**
```
build_multifilar_winding.m        (winding builder)
openmagnetics_winding_layout.m    (layout checker)
plot_*.m                          (visualization)
```

---

### Section 10: DEPENDENCIES & CONSTRAINTS (10 minutes)

**What to Include:**
- [ ] External dependencies (libraries, APIs, databases)
- [ ] Performance constraints (speed, memory, parallelism)
- [ ] Data safety constraints (no data loss, backups, reversibility)
- [ ] Compatibility constraints (versions, platforms)
- [ ] Assumptions (data format, directory structure)

**Template:**
```
External Dependencies:
  ✅ [Tool/Library] - [Link]
  ✅ [API/Service] - [Link]
  ⚠️ [Optional] - [Link]

Constraints:
  🔴 [Hard constraint]: [Description]
  🟡 [Soft constraint]: [Description]

Assumptions:
  ✅ [Assumption about data/system]
```

---

### Section 11: SUCCESS STORIES (10 minutes)

**Pattern:**
1. Show what happens WITHOUT the agent
2. Show what happens WITH the agent
3. Show the improvement

**Example Format:**
```
## Example [N]: [User Scenario]

**Before (without Agent X):**
- User does X
- Problem occurs
- No clear indication what's wrong
- Takes Y minutes to debug

**After (with Agent X):**
- User does X
- Agent X detects problem immediately
- Clear error message with suggestions
- User can fix in 30 seconds
```

**Agent-Specific Examples:**

**Agent 1:**
```
## Example 1: Designer wants interactive feedback
Before: 3+ second wait per solve (too slow for iteration)
After: <200ms per solve with optimization (real-time feedback)
```

**Agent 2:**
```
## Example 2: Designer packs too many turns
Before: Packing succeeds locally, fails during manufacturing
After: Packing checker immediately shows violation, suggests fixes
```

**Agent 4:**
```
## Example 3: Developer breaks something
Before: Run 147 tests manually (1+ hour)
After: Agent runs in 5 min, shows exact failing test
```

---

### Section 12: NEXT STEPS (5 minutes)

**Standard Closing:**
```
## Immediate (This Sprint)
1. Review this specification
2. Feedback on [specific decision point]
3. [Next actionable item]

## Feedback Needed
- [ ] Is approach correct?
- [ ] Are success metrics achievable?
- [ ] [Agent-specific question]

## Ready to Build?
Once approved, development timeline is:
Phase 1: X days
Phase 2: Y weeks
Phase 3: Z days
Phase 4: W days
Total: _____ weeks
```

---

## Filling in Agent-Specific Content

### Quick Reference: What Each Agent Does

| Agent | Primary Responsibility | Key Failure Modes | Success Metric |
|-------|----------------------|-------------------|-----------------|
| **1** | Optimize PEEC solver speed | Singularity, timeout, OOM | <200ms per solve |
| **2** | Validate winding packing | Space exceeded, wire not found | 100% violation detection |
| **3** | Reconcile JSON configs ✅ DONE | Schema drift, orphaned refs | <100ms per file |
| **4** | Orchestrate tests | Missing tests, solver crash | <5min for 147 tests |
| **5** | Manage wizard state | Race conditions, stale data | All transitions tested |
| **6** | Bridge OpenMagnetics API | Timeout, API change, version drift | 100% availability with fallback |
| **7** | Visualize loss density | Invalid data, rendering timeout | <1s to render 10k points |
| **8** | Integrate thermal effects | Unstable equation, convergence | Hotspot accuracy ±5°C |
| **9** | Cross-platform CI | Compilation error, version mismatch | Pass on Octave 10.3 + MATLAB 2024a |
| **10** | Export to CAD | Missing geometry, invalid STEP | Manufacturable STEP file |

---

## Recommended Agents to Enhance Next

**Priority Order:**
1. ✅ **Agent 3 (JSON Reconciler)** - DONE (this template is based on it)
2. **Agent 1 (PEEC Optimizer)** - Feeds everything downstream; highest impact
3. **Agent 2 (Winding Validator)** - Catches design errors early; high priority
4. **Agent 4 (Test Orchestrator)** - Quality assurance critical
5. Agent 5-10 (medium priority, can be done in parallel)

---

## Version Control & Collaboration

### File Naming Convention
```
AGENT_[NUMBER]_[AGENT_NAME]_ENHANCED.md

Examples:
  AGENT_1_PEEC_OPTIMIZER_ENHANCED.md
  AGENT_2_WINDING_VALIDATOR_ENHANCED.md
  AGENT_4_TEST_ORCHESTRATOR_ENHANCED.md
```

### Git Workflow
```bash
# Create branch for each agent enhancement
git checkout -b enhance/agent-1-peec-optimizer

# Work on specification
# ... edit AGENT_1_*.md ...

# Commit when ready
git add AGENT_1_*.md
git commit -m "Enhance Agent 1: PEEC Optimizer specification

Includes:
  - Input/output contracts with JSON schemas
  - 8 failure modes with recovery strategies
  - Success metrics (speed, accuracy, scalability)
  - Implementation roadmap (4 phases, 3 weeks total)
  - Integration points with downstream agents

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"

# Push when approved
git push origin enhance/agent-1-peec-optimizer
```

---

## Estimated Time per Agent

| Section | Time | Notes |
|---------|------|-------|
| 1. Functional Responsibility | 10-15 min | Most time on understanding |
| 2. Input/Output Contracts | 15-25 min | Use https://jsonschema.net/ |
| 3. Required Tools | 10-15 min | Copy from AGENT_TOOLS_REGISTRY.md |
| 4. Error Handling | 30-45 min | **Most critical section** |
| 5. Success Criteria | 10-15 min | Copy pattern from Agent 3 |
| 6. Integration Points | 10-15 min | Use dependency diagram from Overlap Analysis |
| 7. Implementation Roadmap | 15-20 min | Adapt phase structure to agent |
| 8-12. Admin Sections | 30-45 min | Setup, files, next steps |
| **TOTAL PER AGENT** | **2-3 hours** | Can be done in 1-2 working days |

**For all 9 remaining agents: ~18-27 hours of work**

---

## Checklist: Before Submitting Enhanced Spec

- [ ] Section 1: Clear problem statement and boundaries
- [ ] Section 2: JSON schemas are valid (test with validator)
- [ ] Section 2: Examples show success + error cases
- [ ] Section 3: All tools have links + installation commands
- [ ] Section 4: 6-8 failure modes with actionable recovery
- [ ] Section 4: Error messages are specific (not generic)
- [ ] Section 5: Metrics are measurable + achievable
- [ ] Section 5: Acceptance tests use pytest syntax
- [ ] Section 6: Integration diagram is clear and complete
- [ ] Section 7: Roadmap breaks into 4-5 phases with deliverables
- [ ] Section 11: 2-3 real examples showing before/after
- [ ] Overall: Consistent format with Agent 3
- [ ] Overall: 5,000-8,000 words (similar length to Agent 3)
- [ ] Overall: Readable by architect, developer, QA

---

**Template Version:** 1.0
**Last Updated:** 2026-02-22
**Based On:** AGENT_3_JSON_RECONCILER_ENHANCED.md (616 lines, ~6,000 words)

**Start with Agent 1 next!**

