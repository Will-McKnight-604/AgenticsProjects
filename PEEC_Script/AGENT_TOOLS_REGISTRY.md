# Sub-Agent Tools & Libraries Registry
**Date:** 2026-02-22
**Purpose:** Central catalog of all tools, libraries, and documentation links for 10 sub-agents

---

## Quick Navigation

| Tool Category | Count | Link |
|---------------|-------|------|
| **Performance Profiling** | 4 | [→ Section A](#section-a-performance-profiling) |
| **Matrix & Scientific Computing** | 6 | [→ Section B](#section-b-matrix--scientific-computing) |
| **Validation & Schema** | 5 | [→ Section C](#section-c-validation--schema) |
| **Testing & Regression Detection** | 5 | [→ Section D](#section-d-testing--regression-detection) |
| **Visualization & Graphics** | 5 | [→ Section E](#section-e-visualization--graphics) |
| **Data & Configuration Management** | 5 | [→ Section F](#section-f-data--configuration-management) |
| **API & Web Services** | 5 | [→ Section G](#section-g-api--web-services) |
| **3D CAD & Geometry** | 6 | [→ Section H](#section-h-3d-cad--geometry) |
| **Compatibility & CI/CD** | 5 | [→ Section I](#section-i-compatibility--cicd) |
| **Physics & Simulation** | 4 | [→ Section J](#section-j-physics--simulation) |
| **Standards & Databases** | 5 | [→ Section K](#section-k-standards--databases) |

---

## Section A: Performance Profiling

### A1. MATLAB/Octave Profiler
- **Purpose:** Profile PEEC solver bottlenecks
- **Language:** MATLAB/Octave native
- **Agent:** PEEC Optimizer
- **Docs:** https://mathworks.com/help/matlab/ref/profiler.html
- **Installation:** Built-in
- **Use Case:** Identify which functions consume 70-80% of runtime
- **Typical Output:** Flame graph showing call hierarchy and time spent per function

### A2. Octave Profiler
- **Purpose:** CPU profiling for Octave-specific code
- **Language:** Octave native
- **Agent:** PEEC Optimizer, Octave/MATLAB CI
- **Docs:** https://octave.org/doc/v10.3.0/Profiling.html
- **Installation:** Built-in
- **Use Case:** Compare Octave vs MATLAB performance on same code
- **Typical Output:** `.prof` file with detailed timing breakdown

### A3. py-spy
- **Purpose:** Profile Python code (async, multi-threaded)
- **Language:** Python
- **Agent:** Test Orchestrator, Thermal Integrator
- **Docs:** https://github.com/benfred/py-spy
- **Installation:** `pip install py-spy`
- **Use Case:** Identify bottlenecks in OpenMagnetics API calls
- **Typical Output:** Flame graph compatible with standard tools

### A4. GPerfTools (Google Performance Tools)
- **Purpose:** High-performance profiling for C++ kernels
- **Language:** C/C++
- **Agent:** PEEC Optimizer (kernels/), Octave/MATLAB CI
- **Docs:** https://github.com/gperftools/gperftools
- **Installation:** System package: `apt-get install google-perftools` (Linux)
- **Use Case:** Profile C++ PEEC kernels for bottlenecks
- **Typical Output:** CPU profile, heap profiler, thread contention

---

## Section B: Matrix & Scientific Computing

### B1. SuiteSparse (KLU, UMFPACK)
- **Purpose:** Sparse matrix solvers, more efficient than dense for large systems
- **Language:** C/Fortran (interfaces: MATLAB, Python)
- **Agent:** PEEC Optimizer
- **Docs:** https://people.engr.org/~davis/suitesparse.html
- **Installation:** MATLAB: `suitesparse` (built-in); Python: `scikit-sparse`
- **Use Case:** Replace dense matrix solve with sparse solver for impedance matrix
- **Typical Speedup:** 5-10x for realistic winding geometries with sparse structure

### B2. ARPACK (Eigenvalue Solver)
- **Purpose:** Large eigenvalue problems, useful for modal analysis
- **Language:** Fortran (interfaces: MATLAB, Python, Julia)
- **Agent:** PEEC Optimizer, Thermal Integrator
- **Docs:** https://www.caam.rice.edu/software/ARPACK/
- **Installation:** MATLAB: `eigs()` (built-in); Python: `scipy.sparse.linalg`
- **Use Case:** Extract dominant frequency modes for tuning filament mesh
- **Typical Use:** Compute first 5 eigenvalues of impedance matrix

### B3. NumPy/SciPy (Python)
- **Purpose:** Numerical computing, matrix operations, optimization
- **Language:** Python
- **Agent:** Test Orchestrator, Thermal Integrator, Loss Visualization, JSON Reconciler
- **Docs:** https://numpy.org/, https://scipy.org/
- **Installation:** `pip install numpy scipy`
- **Use Case:** Matrix comparison, optimization, statistical analysis
- **Key Functions:** `np.allclose()`, `scipy.linalg.solve()`, `scipy.optimize.minimize()`

### B4. JAX (Automatic Differentiation)
- **Purpose:** Compute gradients for optimization (future use)
- **Language:** Python
- **Agent:** PEEC Optimizer (future), Thermal Integrator (future)
- **Docs:** https://jax.readthedocs.io/
- **Installation:** `pip install jax jaxlib`
- **Use Case:** Compute derivatives of loss w.r.t. winding geometry for optimization
- **Typical Use:** Gradient-based tuning of filament grid

### B5. SymPy
- **Purpose:** Symbolic math, analytical solutions
- **Language:** Python
- **Agent:** Thermal Integrator
- **Docs:** https://www.sympy.org/
- **Installation:** `pip install sympy`
- **Use Case:** Derive thermal RC circuit equations analytically
- **Typical Use:** Solve Laplace equation for heat flow

### B6. Eigen (C++ Linear Algebra)
- **Purpose:** High-performance matrix operations in C++
- **Language:** C++
- **Agent:** Kernels/, PEEC Optimizer
- **Docs:** https://eigen.tuxfamily.org/
- **Installation:** Include-only header library; clone into `kernels/`
- **Use Case:** Optimize PEEC matrix assembly in C++
- **Typical Speedup:** 3-5x vs naive dense matrix multiplication

---

## Section C: Validation & Schema

### C1. JSON Schema
- **Purpose:** Define and validate JSON structure
- **Language:** JSON specification
- **Agent:** JSON Reconciler, API Bridge, Test Orchestrator
- **Docs:** https://json-schema.org/
- **Use Case:** Define schemas for om_*.json config files, API responses
- **Typical File:** `schemas/openmagnetics_design_schema.json`

### C2. jsonschema (Python)
- **Purpose:** JSON Schema validation in Python
- **Language:** Python
- **Agent:** JSON Reconciler, API Bridge
- **Docs:** https://python-jsonschema.readthedocs.io/
- **Installation:** `pip install jsonschema`
- **Use Case:** Validate user-created JSON configs before processing
- **Typical Code:** `jsonschema.validate(instance, schema)`

### C3. AJV (JavaScript/TypeScript)
- **Purpose:** JSON Schema validation (fastest implementation)
- **Language:** JavaScript/TypeScript
- **Agent:** Web Wizard Manager
- **Docs:** https://ajv.js.org/
- **Installation:** `npm install ajv`
- **Use Case:** Validate wizard state before saving to JSON
- **Typical Code:** `const validate = ajv.compile(schema); validate(data)`

### C4. Pydantic (Python)
- **Purpose:** Data validation using Python type hints
- **Language:** Python
- **Agent:** API Bridge, Test Orchestrator, Thermal Integrator
- **Docs:** https://docs.pydantic.dev/
- **Installation:** `pip install pydantic`
- **Use Case:** Validate OpenMagnetics API responses before use
- **Typical Code:** `class DesignSpec(BaseModel): winding_count: int`

### C5. Hypothesis (Property-Based Testing)
- **Purpose:** Generate random test inputs to find edge cases
- **Language:** Python
- **Agent:** Test Orchestrator
- **Docs:** https://hypothesis.readthedocs.io/
- **Installation:** `pip install hypothesis`
- **Use Case:** Generate random winding configurations and verify solver stability
- **Typical Code:** `@given(conductors=some_strategy())`

---

## Section D: Testing & Regression Detection

### D1. pytest
- **Purpose:** Python testing framework
- **Language:** Python
- **Agent:** Test Orchestrator, all agents
- **Docs:** https://docs.pytest.org/
- **Installation:** `pip install pytest`
- **Use Case:** Unify test runner across Python code in the project
- **Typical Structure:** `test_*.py` files with functions named `test_*()`

### D2. pytest-benchmark
- **Purpose:** Performance benchmarking and regression detection
- **Language:** Python
- **Agent:** Test Orchestrator, PEEC Optimizer
- **Docs:** https://pytest-benchmark.readthedocs.io/
- **Installation:** `pip install pytest-benchmark`
- **Use Case:** Track solver runtime trends; detect performance regressions
- **Typical Code:** `def test_peec_speed(benchmark): benchmark(peec_solve, ...)`

### D3. airspeed-velocity (asv)
- **Purpose:** Multi-version performance tracking
- **Language:** Python
- **Agent:** PEEC Optimizer, Octave/MATLAB CI
- **Docs:** https://asv.readthedocs.io/
- **Installation:** `pip install asv`
- **Use Case:** Compare PEEC solver speed across git commits
- **Typical Output:** Web dashboard showing performance timeline

### D4. MATLAB Unit Test Framework (munit)
- **Purpose:** Unit testing in MATLAB
- **Language:** MATLAB
- **Agent:** Test Orchestrator, Octave/MATLAB CI
- **Docs:** https://mathworks.com/help/matlab/unit-testing-framework.html
- **Installation:** Built-in (MATLAB R2013a+)
- **Use Case:** Validate individual MATLAB functions
- **Typical Structure:** `classdef test_peec < matlab.unittest.TestCase`

### D5. Vitest
- **Purpose:** Fast Vue.js component testing
- **Language:** JavaScript/TypeScript
- **Agent:** Web Wizard Manager, Test Orchestrator
- **Docs:** https://vitest.dev/
- **Installation:** `npm install -D vitest`
- **Use Case:** Unit test wizard state transitions
- **Typical Code:** `it('should transition state', () => { ... })`

---

## Section E: Visualization & Graphics

### E1. Plotly (3D Interactive)
- **Purpose:** Interactive 3D plots in browser
- **Language:** Python, JavaScript, R
- **Agent:** Loss Visualization, Thermal Integrator, Test Orchestrator
- **Docs:** https://plotly.com/python/ and https://plotly.com/javascript/
- **Installation:** Python: `pip install plotly`; JavaScript: `npm install plotly.js`
- **Use Case:** Interactive loss density heatmaps, 3D winding visualization
- **Typical Output:** HTML file with embedded 3D viewer

### E2. Three.js
- **Purpose:** WebGL 3D graphics in browser
- **Language:** JavaScript
- **Agent:** Loss Visualization, Web Wizard Manager
- **Docs:** https://threejs.org/
- **Installation:** `npm install three`
- **Use Case:** Real-time 3D winding preview in web UI
- **Typical Scene:** Render core + winding with loss heatmap overlay

### E3. VTK (Visualization Toolkit)
- **Purpose:** Scientific visualization, 3D data
- **Language:** C++, Python, JavaScript
- **Agent:** Loss Visualization, Thermal Integrator, Winding Validator
- **Docs:** https://vtk.org/
- **Installation:** Python: `pip install vtk`; C++: system package
- **Use Case:** Export loss/field data to ParaView-compatible format
- **Typical Format:** `.vtu` (VTK Unstructured Grid)

### E4. Matplotlib
- **Purpose:** 2D static plots, analysis visualizations
- **Language:** Python
- **Agent:** Test Orchestrator, Loss Visualization, Thermal Integrator
- **Docs:** https://matplotlib.org/
- **Installation:** `pip install matplotlib`
- **Use Case:** Generate 2D heatmaps, convergence plots, benchmark dashboards
- **Typical Use:** `plt.imshow(loss_matrix, cmap='hot')`

### E5. Graphviz (DOT format)
- **Purpose:** Generate flowcharts and dependency graphs
- **Language:** DOT (specification), with Python/JavaScript bindings
- **Agent:** Web Wizard Manager, Test Orchestrator, JSON Reconciler
- **Docs:** https://graphviz.org/
- **Installation:** System package: `apt-get install graphviz` (Linux); Python: `pip install graphviz`
- **Use Case:** Visualize wizard state machine, agent dependency graph
- **Typical Output:** `.svg` diagram showing state transitions

---

## Section F: Data & Configuration Management

### F1. deepdiff (Python)
- **Purpose:** Deep comparison of complex data structures
- **Language:** Python
- **Agent:** JSON Reconciler, Test Orchestrator
- **Docs:** https://deepdiff.readthedocs.io/
- **Installation:** `pip install deepdiff`
- **Use Case:** Compare JSON configs before/after design changes
- **Typical Code:** `DeepDiff(config1, config2, ignore_order=True)`

### F2. jsondiff (Python)
- **Purpose:** Compute diff of JSON structures
- **Language:** Python
- **Agent:** JSON Reconciler, Test Orchestrator
- **Docs:** https://github.com/xlwang/jsondiff
- **Installation:** `pip install jsondiff`
- **Use Case:** Generate human-readable JSON change reports
- **Typical Output:** Diff showing removed/added/modified fields

### F3. SQLite (Database)
- **Purpose:** Lightweight embedded database for local fallback
- **Language:** SQL
- **Agent:** API Bridge, JSON Reconciler
- **Docs:** https://www.sqlite.org/
- **Installation:** Built-in (Python: `sqlite3`)
- **Use Case:** Cache OpenMagnetics wire/core database locally
- **Typical Table:** `wires` with columns (gauge, resistance_per_m, strand_count, ...)

### F4. Redis (In-Memory Cache)
- **Purpose:** High-performance caching layer
- **Language:** C/Lua (client libraries: Python, JavaScript, ...)
- **Agent:** API Bridge, PEEC Optimizer, Test Orchestrator
- **Docs:** https://redis.io/
- **Installation:** System package or Docker: `docker run -d redis`
- **Use Case:** Cache expensive API responses, geometry matrices
- **Typical TTL:** 1 hour for OpenMagnetics data, 24 hours for geometry

### F5. DuckDB (Query Engine)
- **Purpose:** SQL queries over JSON and other formats
- **Language:** C/C++ (Python bindings)
- **Agent:** JSON Reconciler, Test Orchestrator
- **Docs:** https://duckdb.org/
- **Installation:** `pip install duckdb`
- **Use Case:** Query 319 JSON config files to find stale entries
- **Typical Query:** `SELECT filename FROM read_json_auto('om_*.json') WHERE timestamp < '2024-01-01'`

---

## Section G: API & Web Services

### G1. Requests (Python)
- **Purpose:** HTTP client library
- **Language:** Python
- **Agent:** API Bridge, Test Orchestrator
- **Docs:** https://requests.readthedocs.io/
- **Installation:** `pip install requests`
- **Use Case:** Make OpenMagnetics API calls
- **Typical Code:** `response = requests.get('https://api.openmagnetics.com/...')`

### G2. httpx (Python)
- **Purpose:** Modern HTTP client with async support
- **Language:** Python
- **Agent:** API Bridge, Test Orchestrator
- **Docs:** https://www.python-httpx.org/
- **Installation:** `pip install httpx`
- **Use Case:** Async API calls with timeout and retry logic
- **Typical Code:** `async with httpx.AsyncClient() as client: ...`

### G3. Tenacity (Retry Library)
- **Purpose:** Automatic retry with exponential backoff
- **Language:** Python
- **Agent:** API Bridge
- **Docs:** https://tenacity.readthedocs.io/
- **Installation:** `pip install tenacity`
- **Use Case:** Retry OpenMagnetics API calls on timeout
- **Typical Code:** `@retry(wait=wait_exponential(), stop=stop_after_attempt(3))`

### G4. slowapi (Rate Limiting)
- **Purpose:** Rate limiting middleware for FastAPI
- **Language:** Python
- **Agent:** API Bridge
- **Docs:** https://slowapi.readthedocs.io/
- **Installation:** `pip install slowapi`
- **Use Case:** Respect OpenMagnetics API rate limits
- **Typical Code:** `@limiter.limit("100/hour")`

### G5. OpenAPI/Swagger
- **Purpose:** API documentation specification
- **Language:** YAML/JSON
- **Agent:** API Bridge, all agents
- **Docs:** https://www.openapis.org/
- **Use Case:** Document OpenMagnetics API contract
- **Typical File:** `openapi.yaml` with all endpoints, parameters, schemas

---

## Section H: 3D CAD & Geometry

### H1. CadQuery
- **Purpose:** Programmatic CAD design in Python
- **Language:** Python (wrapper around OCP)
- **Agent:** CAD Export, Winding Validator
- **Docs:** https://cadquery.readthedocs.io/
- **Installation:** `pip install cadquery`
- **Use Case:** Generate STEP files from core/winding geometry
- **Typical Code:** `box = cq.Workbench().box(10, 10, 5); box.save("core.step")`

### H2. pythonocc (OpenCASCADE Bindings)
- **Purpose:** Low-level CAD kernel in Python
- **Language:** Python (C++ backend: OpenCASCADE)
- **Agent:** CAD Export, Winding Validator
- **Docs:** https://github.com/tpaviot/pythonocc-core
- **Installation:** `pip install pythonocc-core`
- **Use Case:** More advanced CAD operations than CadQuery
- **Typical Use:** Boolean operations, advanced geometry

### H3. trimesh
- **Purpose:** Work with 3D triangular meshes
- **Language:** Python
- **Agent:** CAD Export, Loss Visualization, Winding Validator
- **Docs:** https://trimesh.org/
- **Installation:** `pip install trimesh`
- **Use Case:** Generate STL files, check mesh for intersections
- **Typical Code:** `mesh = trimesh.creation.box(extents=[10,10,5]); mesh.export("box.stl")`

### H4. ezdxf (DXF File Writer)
- **Purpose:** Create DXF (2D CAD) files
- **Language:** Python
- **Agent:** CAD Export
- **Docs:** https://ezdxf.readthedocs.io/
- **Installation:** `pip install ezdxf`
- **Use Case:** Export winding path as 2D DXF for PCB or manufacturing guide
- **Typical Code:** `dxf = ezdxf.new(); dxf.add_lwpolyline(points); dxf.saveas("winding.dxf")`

### H5. CGAL (Computational Geometry)
- **Purpose:** Collision detection, geometric algorithms
- **Language:** C++ (Python bindings: pybind11)
- **Agent:** Winding Validator
- **Docs:** https://www.cgal.org/
- **Installation:** System package + bindings, or use via `cgal-swig-bindings`
- **Use Case:** Detect wire overlaps in packing
- **Typical Algorithm:** 3D intersection detection

### H6. OpenSCAD
- **Purpose:** Programmatic 3D solid modeling
- **Language:** Scripting language
- **Agent:** CAD Export, Winding Validator
- **Docs:** https://openscad.org/
- **Installation:** System package: `apt-get install openscad`
- **Use Case:** Parametric core geometry generation
- **Typical Output:** `.scad` script that generates geometry

---

## Section I: Compatibility & CI/CD

### I1. GitHub Actions
- **Purpose:** CI/CD platform (GitHub-native)
- **Language:** YAML workflow syntax
- **Agent:** Octave/MATLAB CI, Test Orchestrator
- **Docs:** https://docs.github.com/en/actions
- **Use Case:** Run tests on every commit; test across Octave 10.3, MATLAB 2024a+, Windows/Linux
- **Typical File:** `.github/workflows/test.yml`

### I2. GitLab CI
- **Purpose:** CI/CD platform (GitLab-native)
- **Language:** YAML pipeline syntax
- **Agent:** Octave/MATLAB CI, Test Orchestrator
- **Docs:** https://docs.gitlab.com/ee/ci/
- **Use Case:** Alternative to GitHub Actions if using GitLab
- **Typical File:** `.gitlab-ci.yml`

### I3. MATLAB Linter (mlint)
- **Purpose:** Check MATLAB code for errors and style issues
- **Language:** MATLAB native
- **Agent:** Octave/MATLAB CI
- **Docs:** https://mathworks.com/help/matlab/matlab_env/lint-code.html
- **Use Case:** Find unused variables, deprecated functions
- **Typical Code:** `checkcode("peec_solve_frequency.m")`

### I4. Octave Code Analyzer
- **Purpose:** Static analysis for Octave
- **Language:** Octave native
- **Agent:** Octave/MATLAB CI
- **Docs:** https://octave.org/doc/v10.3.0/
- **Use Case:** Check Octave compatibility issues
- **Typical Issue:** Function names that differ between MATLAB/Octave

### I5. m2html
- **Purpose:** Generate HTML documentation from MATLAB/Octave code
- **Language:** MATLAB
- **Agent:** Octave/MATLAB CI, Documentation
- **Docs:** https://www.artefact.tk/software/matlab/m2html/
- **Use Case:** Auto-generate API reference from code comments
- **Typical Output:** HTML with cross-referenced function signatures

---

## Section J: Physics & Simulation

### J1. Steinmetz Equation Implementation
- **Purpose:** Temperature-dependent core loss model
- **Language:** Formula (implemented in Python/MATLAB)
- **Agent:** Thermal Integrator
- **Reference:** [Steinmetz's Equation](https://en.wikipedia.org/wiki/Steinmetz%27s_equation)
- **Formula:** `P = k * f^x * B^y * T^z`
- **Use Case:** Scale core loss with temperature variation
- **Typical Coefficients:** f=1.6, x=2.3, y=2.8 (ferrite)

### J2. Thermal RC Network Solver
- **Purpose:** Solve transient thermal circuit
- **Language:** Python (scipy.linalg or sympy)
- **Agent:** Thermal Integrator
- **Typical Network:** R_core-to-ambient, R_winding-to-core, C_core, C_winding
- **Use Case:** Estimate hotspot rise vs time
- **Typical Solve:** `scipy.linalg.solve(A, b)` for steady-state; ODE solver for transient

### J3. Material Property Database
- **Purpose:** Temperature-dependent conductivity, permeability
- **Language:** JSON data + Python loader
- **Agent:** Thermal Integrator
- **Sources:**
  - IEC 61248 (Copper): https://webstore.iec.ch/
  - MPS (Material Property System): Proprietary
  - NIST MatWeb: https://matweb.com/
- **Use Case:** Lookup resistivity vs temperature for copper winding
- **Typical Data:** `copper_resistivity = 1.68e-8 * (1 + 0.0039 * (T - 20))`

### J4. FEA Mesh Generator
- **Purpose:** Generate tetrahedral/hexahedral mesh for CFD export
- **Language:** Python (pygmsh, pyvista)
- **Agent:** Thermal Integrator, Loss Visualization
- **Docs:** https://pygmsh.readthedocs.io/
- **Installation:** `pip install pygmsh`
- **Use Case:** Create boundary conditions for CFD analysis
- **Typical Tool:** Export to OpenFOAM format

---

## Section K: Standards & Databases

### K1. IEC 60085 (Insulation Classes)
- **Purpose:** Temperature limits for insulation materials
- **Agent:** Thermal Integrator, Winding Validator
- **Docs:** https://webstore.iec.ch/
- **Class A:** 105°C (Thermal class)
- **Class B:** 130°C
- **Class F:** 155°C
- **Class H:** 180°C
- **Use Case:** Validate hotspot temperature against insulation class

### K2. IEC 60664-1 (Clearance & Creepage)
- **Purpose:** Safety distances for insulation
- **Agent:** Winding Validator
- **Docs:** https://webstore.iec.ch/
- **Parameters:** Voltage, pollution degree, material group
- **Use Case:** Check wire-to-wire and wire-to-core clearances
- **Database:** Map voltage → required clearance distance

### K3. OpenMagnetics Database
- **Purpose:** Magnetic component library (cores, wires, suppliers)
- **Agent:** API Bridge, Winding Validator
- **Docs:** https://openmagnetics.com/
- **API:** RESTful JSON API
- **Data:** 1300+ core shapes, 500+ wire gauges, supplier availability
- **Use Case:** Validate winding feasibility; check component availability
- **Format:** MAS (Magnetic Analysis Suite) schema

### K4. Wire & Cable Standards
- **Purpose:** Standard wire gauges (AWG, metric), conductor properties
- **Agent:** Winding Validator, PEEC Optimizer
- **Standards:**
  - AWG (American Wire Gauge): https://en.wikipedia.org/wiki/American_wire_gauge
  - IEC 60228 (Conductor Sizes): https://webstore.iec.ch/
  - Mogami Wire: https://www.mogami-wire.co.jp/
- **Use Case:** Look up resistance per meter, current capacity
- **Typical Database:** JSON with columns: gauge, diameter_mm, resistance_ohm_per_m, current_max_A

### K5. Fair-Rite Core Database
- **Purpose:** Ferrite core characteristics and availability
- **Agent:** CAD Export, API Bridge
- **Docs:** https://www.fair-rite.com/
- **Data:** Permeability, loss curves, part numbers, dimensions
- **Use Case:** Check if selected core is in stock; validate STEP models
- **Integration:** API or web scraping for real-time availability

---

## Installation Quick Start

### Python Essentials
```bash
pip install numpy scipy matplotlib plotly pytest pytest-benchmark pydantic jsonschema deepdiff duckdb httpx tenacity requests
```

### Web Development
```bash
npm install plotly.js three.js vitest ajv
```

### Scientific Computing
```bash
pip install sympy jax cadquery trimesh ezdxf
```

### System Dependencies
```bash
# Linux
apt-get install graphviz openscad google-perftools sqlite3 redis-server

# macOS
brew install graphviz openscad gperftools sqlite redis

# Windows
choco install graphviz openscad redis
```

---

## Tool-to-Agent Mapping Matrix

| Tool | PEEC | Winding | JSON | Test | Wizard | API | Loss | Thermal | CI | CAD | Comments |
|------|------|---------|------|------|--------|-----|------|---------|----|----|----------|
| MATLAB Profiler | ✅ | - | - | - | - | - | - | - | ✅ | - | Core performance analysis |
| SuiteSparse | ✅ | - | - | - | - | - | - | ✅ | - | - | Matrix acceleration |
| pytest | - | - | ✅ | ✅ | - | ✅ | - | ✅ | ✅ | - | Unified test framework |
| Plotly | - | - | - | ✅ | - | - | ✅ | ✅ | - | - | Dashboard visualization |
| Three.js | - | - | - | - | ✅ | - | ✅ | - | - | - | Browser 3D graphics |
| jsonschema | - | - | ✅ | - | - | ✅ | - | - | - | - | Config validation |
| Pydantic | - | - | ✅ | - | - | ✅ | - | ✅ | - | - | Data validation |
| OpenMagnetics API | - | ✅ | - | - | ✅ | ✅ | - | - | - | - | Database access |
| CadQuery | - | - | - | - | - | - | - | - | - | ✅ | STEP file generation |
| GitHub Actions | - | - | - | ✅ | - | - | - | - | ✅ | - | CI/CD infrastructure |
| Thermal RC Solver | - | - | - | - | - | - | - | ✅ | - | - | Hotspot estimation |
| CGAL | - | ✅ | - | - | - | - | - | - | - | ✅ | Collision detection |

---

## Recommended Tool Installation Order

**Phase 1: Core Infrastructure (Week 1)**
1. pytest, jsonschema, pydantic
2. GitHub Actions workflow setup
3. MATLAB/Octave linters

**Phase 2: Scientific Computing (Week 2)**
1. numpy, scipy, sympy
2. Plotly for visualization
3. SuiteSparse bindings

**Phase 3: API & Data (Week 3)**
1. httpx, tenacity, slowapi
2. OpenMagnetics API client
3. Redis/SQLite local cache

**Phase 4: Specialized Tools (Week 4)**
1. CadQuery, trimesh, ezdxf
2. VTK for advanced visualization
3. CGAL for collision detection

---

**Next Step:** Review this registry and identify which tools are already available in your environment. Run:
```bash
python -c "import numpy; print('✅ NumPy available')"
```

