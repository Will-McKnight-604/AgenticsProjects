# Agent 3: JSON Configuration & Cache Reconciliation
## ENHANCED SPECIFICATION & IMPLEMENTATION GUIDE

**Agent ID:** 3 | **Priority:** ⭐⭐⭐ HIGH | **Phase:** 1 (Immediate)
**Status:** Template Agent - Model for other 9 agents
**Created:** 2026-02-22 | **Version:** 1.0

---

## 1. FUNCTIONAL RESPONSIBILITY (Enhanced)

### 1.1 Purpose (One-Liner)
Detect and resolve inconsistencies in JSON config/cache files; ensure data integrity across the design tool.

### 1.2 Problem Statement
The PEEC design tool manages **319 JSON files** across:
- User-created design configurations (`om_*.json`, `om_prescreen_*.json`)
- Cached solver results (`*_cache.json`)
- API responses from OpenMagnetics
- Visualization metadata and exports
- Validation benchmark data

**Current Issues:**
- ❌ No centralized validation against schema
- ❌ Cache invalidation logic unclear (when to refresh?)
- ❌ Orphaned entries: configs referencing deleted wires/cores
- ❌ Schema version drift: local files vs OpenMagnetics remote API
- ❌ Users see stale/contradictory data without warning
- ❌ No audit trail for who changed what and when

### 1.3 Scope Definition

**IN SCOPE (This Agent):**
- Validate local JSON files against known schemas
- Detect orphaned/stale entries
- Compare config before/after operations
- Generate validation reports with auto-fix suggestions
- Track cache coherency (TTL, dependencies)
- Handle schema migrations and backwards compatibility
- Provide data lineage (which designs depend on which configs)

**OUT OF SCOPE (Other Agents):**
- Making API calls to OpenMagnetics (→ Agent 6: API Bridge)
- Deciding what to design (→ Agent 5: Web Wizard Manager)
- Displaying configs to users (→ Agent 5: Web Wizard Manager)
- Testing the configs (→ Agent 4: Test Orchestrator)
- Solving designs (→ Agent 1: PEEC Optimizer)

### 1.4 Agent Boundaries

**Upstream Dependency:**
- None (entry point after user loads/creates config)

**Downstream Consumers:**
- Agent 1 (PEEC Optimizer): depends on clean geometry config
- Agent 2 (Winding Validator): depends on valid winding configs
- Agent 5 (Web Wizard): saves state → validates before save
- Agent 6 (API Bridge): uses cache coherency info

**Independent Agents:**
- Agent 4 (Test Orchestrator)
- Agent 7 (Loss Visualization)
- Agent 8 (Thermal Integrator)
- Agent 9 (Octave/MATLAB CI)
- Agent 10 (CAD Export)

---

## 2. INPUT/OUTPUT CONTRACTS

### 2.1 Input Specification

#### **Input Type 1: JSON Config File**
```json
{
  "config_file": {
    "path": "string (absolute or relative)",
    "format": "om_design.json | om_prescreen.json | om_excitation.json | custom",
    "load_mode": "readonly | validate | auto_fix"
  }
}
```

**Example:**
```json
{
  "config_file": {
    "path": "om_design_v1.json",
    "format": "om_design.json",
    "load_mode": "validate"
  }
}
```

#### **Input Type 2: Batch Validation (Multiple Files)**
```json
{
  "batch_validation": {
    "glob_pattern": "string (e.g., 'om_*.json')",
    "directory": "string (absolute path)",
    "recursive": "boolean",
    "schema_version": "string (e.g., '2024.02')"
  }
}
```

**Example:**
```json
{
  "batch_validation": {
    "glob_pattern": "om_*.json",
    "directory": "./",
    "recursive": true,
    "schema_version": "2024.02"
  }
}
```

#### **Input Type 3: Cache Coherency Check**
```json
{
  "cache_check": {
    "cache_files": ["string (paths)"],
    "reference_timestamp": "ISO8601 timestamp",
    "max_age_hours": "integer (default: 24)"
  }
}
```

**Example:**
```json
{
  "cache_check": {
    "cache_files": ["om_excitation_cache.json", "om_prescreen_losses.json"],
    "reference_timestamp": "2026-02-22T10:00:00Z",
    "max_age_hours": 24
  }
}
```

#### **Input Type 4: Schema Definition (Internal)**
```json
{
  "schema": {
    "name": "string (e.g., 'om_design_schema')",
    "version": "string (e.g., '2024.02')",
    "fields": {
      "field_name": {
        "type": "string | number | array | object | boolean",
        "required": "boolean",
        "default": "any",
        "description": "string",
        "validation_rule": "string (regex, range, enum, etc.)"
      }
    }
  }
}
```

**Example Schema Field:**
```json
{
  "frequency_hz": {
    "type": "number",
    "required": true,
    "validation_rule": "range: [1000, 10000000]",
    "description": "Operating frequency in Hz (1 kHz to 10 MHz)"
  }
}
```

---

### 2.2 Output Specification

#### **Output Type 1: Validation Report**
```json
{
  "validation_report": {
    "timestamp": "ISO8601",
    "status": "valid | warning | error",
    "summary": {
      "total_files": "integer",
      "valid_files": "integer",
      "invalid_files": "integer",
      "warning_files": "integer",
      "fixes_applied": "integer"
    },
    "details": [
      {
        "file": "string (path)",
        "status": "valid | warning | error",
        "messages": [
          {
            "type": "schema_mismatch | orphaned_reference | stale_cache | version_drift | migration_required",
            "severity": "info | warning | error",
            "field": "string (JSON path, e.g., '$.core_shape_id')",
            "current_value": "any",
            "expected_value": "any",
            "message": "Human-readable error message",
            "suggestion": "Recommended fix (if available)"
          }
        ],
        "fixes_suggested": [
          {
            "fix_id": "string (unique ID for this fix)",
            "action": "remove_field | update_value | migrate_schema | delete_file",
            "target": "string (JSON path)",
            "from_value": "any",
            "to_value": "any",
            "auto_fixable": "boolean",
            "risk_level": "low | medium | high"
          }
        ]
      }
    ],
    "cache_coherency": {
      "stale_entries": "integer",
      "orphaned_entries": "integer",
      "version_mismatches": "integer"
    },
    "data_lineage": {
      "design_id": "string",
      "depends_on_configs": ["string (list of file paths)"],
      "referenced_by": ["string (list of dependent files)"]
    }
  }
}
```

**Real Example Output:**
```json
{
  "validation_report": {
    "timestamp": "2026-02-22T15:30:45Z",
    "status": "warning",
    "summary": {
      "total_files": 45,
      "valid_files": 42,
      "invalid_files": 1,
      "warning_files": 2,
      "fixes_applied": 0
    },
    "details": [
      {
        "file": "om_design_v1.json",
        "status": "valid",
        "messages": [],
        "fixes_suggested": []
      },
      {
        "file": "om_prescreen_losses.json",
        "status": "warning",
        "messages": [
          {
            "type": "stale_cache",
            "severity": "warning",
            "field": "$.metadata.generated_at",
            "current_value": "2026-02-20T08:00:00Z",
            "expected_value": "2026-02-22T10:00:00Z",
            "message": "Cache generated 2+ days ago; may be stale",
            "suggestion": "Regenerate prescreen losses with current solver"
          }
        ],
        "fixes_suggested": [
          {
            "fix_id": "fix_001",
            "action": "regenerate_cache",
            "target": "$.metadata.generated_at",
            "from_value": "2026-02-20T08:00:00Z",
            "to_value": "2026-02-22T15:30:45Z",
            "auto_fixable": false,
            "risk_level": "medium"
          }
        ]
      },
      {
        "file": "om_excitation_cache.json",
        "status": "error",
        "messages": [
          {
            "type": "orphaned_reference",
            "severity": "error",
            "field": "$.core_shape_id",
            "current_value": "core_id_12345",
            "expected_value": "string from OpenMagnetics core database",
            "message": "Core ID 'core_id_12345' not found in OpenMagnetics database or local cache",
            "suggestion": "Either import core shape or update config to reference valid core"
          }
        ],
        "fixes_suggested": [
          {
            "fix_id": "fix_002",
            "action": "remove_field",
            "target": "$.core_shape_id",
            "from_value": "core_id_12345",
            "to_value": null,
            "auto_fixable": true,
            "risk_level": "high"
          }
        ]
      }
    ],
    "cache_coherency": {
      "stale_entries": 3,
      "orphaned_entries": 1,
      "version_mismatches": 0
    },
    "data_lineage": {
      "design_id": "design_001",
      "depends_on_configs": ["om_core_params.json", "om_wire_database.json"],
      "referenced_by": ["om_prescreen_config.json"]
    }
  }
}
```

#### **Output Type 2: Auto-Fix Confirmation**
```json
{
  "auto_fix_confirmation": {
    "timestamp": "ISO8601",
    "files_processed": "integer",
    "fixes_applied": [
      {
        "file": "string",
        "fix_id": "string",
        "status": "success | failed",
        "before_value": "any",
        "after_value": "any",
        "backup_created": "boolean (true if rollback possible)"
      }
    ],
    "rollback_available": "boolean",
    "rollback_id": "string (if available)"
  }
}
```

#### **Output Type 3: Data Lineage Graph**
```json
{
  "data_lineage": {
    "design_id": "string",
    "dependencies": {
      "core_definitions": {
        "source": "openmagnetics_database | local_cache",
        "files": ["string (paths)"],
        "last_updated": "ISO8601"
      },
      "wire_definitions": {
        "source": "openmagnetics_database | local_cache",
        "files": ["string (paths)"],
        "last_updated": "ISO8601"
      },
      "material_properties": {
        "source": "string",
        "files": ["string (paths)"],
        "last_updated": "ISO8601"
      }
    },
    "dependents": {
      "designs_using_this": ["string (design IDs)"],
      "simulations_depending_on": ["string (simulation IDs)"]
    }
  }
}
```

---

## 3. REQUIRED TOOLS & LIBRARIES

### 3.1 Core Tools (Required)

| # | Tool | Language | Purpose | Install | Docs |
|---|------|----------|---------|---------|------|
| 1 | **jsonschema** | Python | Validate JSON against schemas | `pip install jsonschema` | https://python-jsonschema.readthedocs.io/ |
| 2 | **Pydantic** | Python | Data validation using type hints | `pip install pydantic` | https://docs.pydantic.dev/ |
| 3 | **DuckDB** | Python | SQL queries over JSON files | `pip install duckdb` | https://duckdb.org/ |
| 4 | **deepdiff** | Python | Deep comparison of data structures | `pip install deepdiff` | https://deepdiff.readthedocs.io/ |
| 5 | **jsondiff** | Python | Human-readable JSON diffs | `pip install jsondiff` | https://github.com/xlwang/jsondiff |
| 6 | **SQLite** | Python | Local database for cache tracking | Built-in `sqlite3` | https://www.sqlite.org/ |

### 3.2 Optional Tools (Nice-to-Have)

| # | Tool | Purpose | Install | When to Use |
|---|------|---------|---------|-------------|
| 7 | **Redis** | High-performance cache layer | Docker or system package | For shared cache across services |
| 8 | **jsonpath-ng** | Query JSON with XPath-like syntax | `pip install jsonpath-ng` | Complex JSON navigation |
| 9 | **hypothesis** | Property-based testing | `pip install hypothesis` | Generate random invalid JSONs to test |
| 10 | **json-schema-to-markdown** | Auto-generate docs from schemas | `pip install json-schema-to-markdown` | Documentation generation |

### 3.3 Installation Commands

```bash
# Core dependencies
pip install jsonschema pydantic duckdb deepdiff jsondiff

# Optional
pip install redis-py jsonpath-ng hypothesis json-schema-to-markdown

# System dependencies (for SQLite3, if not installed)
apt-get install sqlite3  # Linux
brew install sqlite      # macOS
choco install sqlite     # Windows
```

### 3.4 Minimum Viable Setup
If limited by resources, start with:
```bash
pip install jsonschema deepdiff
# Use Python's built-in sqlite3 for database
# Use Python's built-in json module for parsing
```

---

## 4. ERROR HANDLING SPECIFICATION

### 4.1 Failure Modes & Recovery

#### **Failure Mode 1: Schema Not Found**

**Trigger:** User provides schema version that doesn't exist (e.g., `schema_version: "2025.01"` but only 2024.02 available)

**Error Message:**
```
ERROR: Schema version '2025.01' not found
  Available schemas:
    - 2024.02 (current)
    - 2024.01 (deprecated)
    - 2023.12 (legacy)

  Options:
    1. Use current schema: 2024.02
    2. Specify legacy schema: 2023.12
    3. Create custom schema
```

**Recovery Strategy:** Use current schema, log warning, allow user to override

**Code Example:**
```python
try:
    schema = load_schema(version="2025.01")
except SchemaNotFoundError as e:
    logger.warning(f"Schema {e.requested} not found. Using current: {CURRENT_SCHEMA}")
    schema = load_schema(version=CURRENT_SCHEMA)
    report.warnings.append(f"Fallback to schema {CURRENT_SCHEMA}")
```

---

#### **Failure Mode 2: Orphaned Reference (Stale ID)**

**Trigger:** Config references wire gauge `AWG_36_litz` but that wire no longer exists in database

**Error Message:**
```
ERROR: Orphaned reference in om_design_v1.json
  Field: $.winding.wire_gauge_id
  Current value: "AWG_36_litz"
  Problem: Wire not found in OpenMagnetics database or local cache

  Possible causes:
    1. Wire was deleted from supplier
    2. Database version mismatch
    3. Typo in wire ID

  Suggested fixes:
    a) Remove this field (auto-fixable, risk=high)
    b) Update to similar wire: "AWG_36_solid" (manual)
    c) Import wire definition from database (manual)
```

**Recovery Strategy:** Flag as error, suggest alternatives, don't auto-fix (too risky)

**Code Example:**
```python
try:
    wire = lookup_wire(wire_id="AWG_36_litz")
except WireNotFoundError:
    report.errors.append(ValidationError(
        field="$.winding.wire_gauge_id",
        message=f"Wire {wire_id} not found",
        suggestions=["Remove field", "Update to similar wire", "Import from database"],
        auto_fixable=False,
        risk_level="high"
    ))
```

---

#### **Failure Mode 3: Schema Version Drift**

**Trigger:** Config file was created with schema v2024.01 but current system uses v2024.02

**Error Message:**
```
WARNING: Schema version mismatch
  File: om_design_v1.json
  File schema version: 2024.01
  Current system version: 2024.02

  Changes between versions:
    - NEW: field "thermal_margin_celsius"
    - DEPRECATED: field "ambient_temperature" (use "ambient_temp_c")
    - RENAMED: "core_losses" → "core_loss_watts"
    - CHANGED: "frequency_hz" validation (now: 1kHz-10MHz, was: 100Hz-100MHz)

  Migration options:
    1. Auto-migrate to 2024.02 (recommended)
    2. Keep as 2024.01 (manual conversion on use)
    3. Validate against both schemas
```

**Recovery Strategy:** Offer auto-migration with rollback capability

**Code Example:**
```python
file_version = extract_schema_version(json_data)
if file_version != CURRENT_VERSION:
    migration = find_migration_path(file_version, CURRENT_VERSION)
    if migration.auto_safe:
        json_data = apply_migration(json_data, migration)
        report.migrations_applied.append(migration)
        # Create backup for rollback
        save_backup(json_data, backup_id=uuid.uuid4())
    else:
        report.warnings.append(f"Manual migration required: {migration.description}")
```

---

#### **Failure Mode 4: Cache Expiration (Stale Cache)**

**Trigger:** Cache file `om_excitation_cache.json` is 48 hours old but cache TTL is 24 hours

**Error Message:**
```
WARNING: Stale cache detected
  File: om_excitation_cache.json
  Generated: 2026-02-20 08:00:00 UTC (2 days ago)
  Cache TTL: 24 hours
  Current time: 2026-02-22 15:30:45 UTC

  Age: 55 hours 30 min (31.5 hours EXPIRED)

  Risk: Solver results may be inaccurate
  Recommendation: Regenerate cache with current solver
```

**Recovery Strategy:** Flag as warning, don't delete cache, suggest regeneration

**Code Example:**
```python
cache_age = datetime.now() - cache_timestamp
if cache_age > CACHE_TTL:
    report.warnings.append(StaleCache(
        file="om_excitation_cache.json",
        age_hours=cache_age.total_seconds() / 3600,
        ttl_hours=CACHE_TTL.total_seconds() / 3600,
        suggestion="Regenerate cache with current solver",
        auto_fixable=False  # Requires re-solving
    ))
    # Mark cache as "stale" but keep it
    json_data["_metadata"]["is_stale"] = True
```

---

#### **Failure Mode 5: Disk I/O Error**

**Trigger:** Config file is locked by another process or permission denied

**Error Message:**
```
ERROR: Cannot read config file
  File: om_design_v1.json
  Error: Permission denied (errno 13)

  Possible causes:
    1. File is locked by another process
    2. Insufficient permissions
    3. File is on unmounted drive

  Solutions:
    1. Close any open file handles (Excel, text editor, etc.)
    2. Check file permissions: chmod 644 om_design_v1.json
    3. Check disk is mounted and accessible
    4. Retry in 5 seconds
```

**Recovery Strategy:** Retry with exponential backoff, fail if persistent

**Code Example:**
```python
max_retries = 3
retry_delay = 1  # seconds

for attempt in range(max_retries):
    try:
        with open(filepath, 'r') as f:
            json_data = json.load(f)
        break
    except IOError as e:
        if attempt < max_retries - 1:
            logger.warning(f"I/O error (attempt {attempt+1}). Retrying in {retry_delay}s...")
            time.sleep(retry_delay)
            retry_delay *= 2  # exponential backoff
        else:
            raise FileAccessError(f"Cannot read {filepath}: {e}")
```

---

#### **Failure Mode 6: Invalid JSON Syntax**

**Trigger:** Config file contains malformed JSON (trailing comma, unquoted key, etc.)

**Error Message:**
```
ERROR: Invalid JSON syntax
  File: om_design_v1.json
  Line 42, Column 18

  Problem: Trailing comma in object
  ```json
  {
    "frequency": 100000,  ← INVALID: trailing comma
  }
  ```

  Fix: Remove the comma before the closing brace
```

**Recovery Strategy:** Point user to exact location, don't attempt repair (could lose data)

**Code Example:**
```python
try:
    json_data = json.load(f)
except json.JSONDecodeError as e:
    raise InvalidJSONError(
        file=filepath,
        line=e.lineno,
        column=e.colno,
        message=e.msg,
        context=get_context(filepath, e.lineno, e.colno)
    )
```

---

#### **Failure Mode 7: Missing Required Fields**

**Trigger:** Config missing mandatory field like `frequency_hz`

**Error Message:**
```
ERROR: Missing required field
  File: om_design_v1.json
  Field: frequency_hz
  Schema: om_design (v2024.02)

  This field is required because:
    - PEEC solver needs frequency for impedance matrix
    - Winding validator needs frequency for skin depth calculation

  Expected type: number (Hz, range: 1000-10000000)
  Example: "frequency_hz": 221000
```

**Recovery Strategy:** Flag as error, cannot auto-fix (requires user input)

**Code Example:**
```python
schema = load_schema("om_design", "2024.02")
try:
    jsonschema.validate(json_data, schema)
except jsonschema.ValidationError as e:
    if e.validator == 'required':
        missing_field = e.validator_value[0]  # Get missing field name
        report.errors.append(RequiredFieldMissing(
            field=missing_field,
            schema=schema,
            auto_fixable=False
        ))
```

---

#### **Failure Mode 8: Type Mismatch**

**Trigger:** Field has wrong type (e.g., `frequency_hz: "100k"` instead of `100000`)

**Error Message:**
```
ERROR: Type mismatch
  File: om_design_v1.json
  Field: frequency_hz
  Expected type: number
  Actual type: string ("100k")

  The value "100k" cannot be parsed as a number.

  Options:
    a) Fix automatically: "100k" → 100000 (requires parsing rule)
    b) Fix manually: Edit file and set numeric value
    c) Use different field: "frequency_description" (custom)
```

**Recovery Strategy:** Try parsing; if fails, flag as error

**Code Example:**
```python
def coerce_type(value, expected_type):
    if type(value) == expected_type:
        return value

    # Try coercion
    if expected_type == float:
        try:
            # Try parsing "100k" → 100000
            return parse_numeric_string(value)
        except ValueError:
            raise TypeMismatchError(f"Cannot convert {value!r} to {expected_type}")
```

---

### 4.2 Error Handling Matrix

| Failure Mode | Severity | Auto-Fixable | Rollback Possible | User Action |
|--------------|----------|--------------|-------------------|------------|
| Schema not found | ⚠️ Warning | ✅ Yes (fallback) | N/A | Accept or override |
| Orphaned reference | 🔴 Error | ❌ No | N/A | Update or remove |
| Schema version drift | ⚠️ Warning | ✅ Yes (migration) | ✅ Yes | Accept or reject |
| Stale cache | ⚠️ Warning | ❌ No (requires recompute) | N/A | Regenerate or use anyway |
| Disk I/O error | 🔴 Error | ✅ Yes (retry) | N/A | Fix permissions/locks |
| Invalid JSON syntax | 🔴 Error | ❌ No | N/A | Fix file manually |
| Missing required field | 🔴 Error | ❌ No | N/A | Add field with value |
| Type mismatch | ⚠️ Warning | ✅ Maybe (try parse) | N/A | Fix type or parse rule |

---

## 5. SUCCESS CRITERIA & ACCEPTANCE TESTS

### 5.1 Quantitative Metrics

| Metric | Target | How to Measure |
|--------|--------|-----------------|
| **Validation Speed** | <100ms per file | Time CLI execution for batch validation |
| **Detection Rate** | 100% of schema violations | Run against 50 intentionally-broken JSONs |
| **False Positive Rate** | <1% | Valid configs incorrectly flagged as invalid |
| **Auto-Fix Success** | 80%+ of suggested fixes work | Apply auto-fixes and re-validate |
| **Orphaned Entry Detection** | 100% recall | Manually create orphaned refs, validate detection |
| **Cache Expiry Detection** | 100% accuracy | Test with various TTL values |
| **Report Clarity** | >90% users understand suggestion | User feedback on error messages |

### 5.2 Qualitative Criteria

- ✅ Error messages are specific (show exact field path, not just "error in config")
- ✅ Suggestions are actionable (users can apply fix without confusion)
- ✅ All failures have recovery paths (no dead ends)
- ✅ Rollback capability for risky operations (migrate schema, apply auto-fixes)
- ✅ Data lineage is accurate (track all dependencies correctly)
- ✅ Performance acceptable on 319 JSON files (<5 seconds batch validate)
- ✅ Backwards compatibility with old schema versions (2024.01, 2023.12)

### 5.3 Acceptance Tests

**Test 1: Validate clean config**
```python
def test_valid_config_passes():
    config = load_clean_config()
    result = validate(config)
    assert result.status == "valid"
    assert len(result.errors) == 0
```

**Test 2: Detect schema mismatch**
```python
def test_detects_schema_version_drift():
    config = load_config("version_2024.01")
    result = validate(config, target_version="2024.02")
    assert "version_drift" in result.warnings
    assert result.migration is not None
```

**Test 3: Find orphaned reference**
```python
def test_detects_orphaned_wire_reference():
    config = {"wire_gauge_id": "NONEXISTENT_WIRE"}
    result = validate(config)
    assert any(e.type == "orphaned_reference" for e in result.errors)
    assert result.errors[0].field == "$.wire_gauge_id"
```

**Test 4: Detect stale cache**
```python
def test_detects_stale_cache():
    cache = load_cache("generated_48_hours_ago")
    result = check_cache_coherency(cache, ttl_hours=24)
    assert "stale_cache" in result.warnings
```

**Test 5: Batch validate 319 files in <5s**
```python
def test_batch_validation_performance():
    start = time.time()
    result = batch_validate("om_*.json", ".")
    elapsed = time.time() - start
    assert elapsed < 5.0, f"Batch validation took {elapsed}s (target: <5s)"
```

---

## 6. INTEGRATION POINTS

### 6.1 Upstream Dependencies
- **None** (Agent 3 is entry point)
- Triggered by: User action (load config, click "validate"), or automated checks

### 6.2 Downstream Consumers

| Consumer | Input | Use Case |
|----------|-------|----------|
| **Agent 1: PEEC Optimizer** | Clean geometry config | Validates config before building matrices |
| **Agent 2: Winding Validator** | Clean winding config | Validates config before layout checks |
| **Agent 5: Web Wizard** | Config validation result | Prevents invalid state save |
| **Agent 6: API Bridge** | Cache coherency info | Knows when to refresh remote data |
| **Test Suite** | Config validation | Pre-flight check before running tests |

### 6.3 Data Flow Diagram

```
User Action
  ↓
┌─────────────────────────────────┐
│ Agent 3: JSON Reconciler        │
│ (validate, detect, reconcile)   │
└──────────────┬──────────────────┘
               ↓
         Validation Report
              (JSON)
         ↙        ↓        ↘
        ↓         ↓         ↓
   [Clean]  [Warning]  [Error]
    Config   Config    Config
      ↓         ↓         ↓
      ├─────────┼─────────┤
      ↓         ↓         ↓
   Agent 1  Agent 2   [STOP]
   Agent 5  Agent 5   [Warn]
   Agent 6  Agent 6
```

### 6.4 Integration Test Scenario

**Scenario:** User loads config, Agent 3 validates, PEEC Optimizer uses result

```
Step 1: User loads "om_design_v1.json"
Step 2: Agent 3 validates against schema v2024.02
  - Status: ✅ Valid
  - No orphaned refs
  - No stale caches
Step 3: Agent 3 returns clean config to downstream
Step 4: Agent 1 (PEEC) receives config
  - Builds geometry from clean config
  - No validation errors
  - Solves successfully
```

---

## 7. IMPLEMENTATION ROADMAP

### Phase 1: Discovery (Week 1 - 2-3 days)
- [ ] Audit all 319 JSON files → catalog structure
- [ ] Identify 3-5 most common schemas
- [ ] Map current schema versions (where documented)
- [ ] Document existing validation rules (scattered across codebase)
- [ ] Identify 10-15 known validation issues in real configs

**Deliverable:** `JSON_AUDIT_REPORT.md` with schema catalog

---

### Phase 2: MVP Development (Weeks 2-3 - 2 weeks)

**Sprint 2a: Schema & Validation Framework (4-5 days)**
- [ ] Define and document 3 core schemas (om_design, om_prescreen, om_excitation)
- [ ] Implement `validate()` function using jsonschema
- [ ] Implement `compare_configs()` function using deepdiff
- [ ] Write 20+ unit tests for validation

**Sprint 2b: Error Handling & Reporting (4-5 days)**
- [ ] Implement ValidationReport JSON structure
- [ ] Build error message formatter (specific, actionable)
- [ ] Implement recovery strategies (8 failure modes from Section 4)
- [ ] Add rollback capability for auto-fixes

**Sprint 2c: Advanced Features (3-4 days)**
- [ ] Implement cache coherency checking (TTL, stale detection)
- [ ] Implement data lineage tracking
- [ ] Add schema migration (v2024.01 → v2024.02)
- [ ] Implement batch validation (all 319 files)

**Deliverable:** CLI tool + Python API, 30+ unit tests, <100ms per file

---

### Phase 3: Integration (Week 4 - 3-4 days)
- [ ] Wire into Agent 1 (PEEC) → pre-flight validation
- [ ] Wire into Agent 2 (Winding) → validate before packing checks
- [ ] Wire into Agent 5 (Wizard) → prevent invalid state save
- [ ] Add integration tests (test with actual PEEC/Winding code)
- [ ] Performance testing on full 319 file set

**Deliverable:** Integrated into 3 downstream agents

---

### Phase 4: Documentation & Handoff (1 week)
- [ ] Usage guide (CLI + Python API)
- [ ] Architecture diagram
- [ ] Troubleshooting guide
- [ ] Schema migration guide (for future versions)
- [ ] Training notebook

**Deliverable:** Complete docs + training materials

---

## 8. TOOLS SETUP CHECKLIST

### Installation
```bash
# Install core tools
pip install jsonschema pydantic duckdb deepdiff jsondiff

# Verify installation
python -c "import jsonschema, pydantic, duckdb, deepdiff, jsondiff; print('✅ All tools ready')"

# Optional: create virtual environment
python -m venv venv_agent3
source venv_agent3/bin/activate  # Linux/macOS
# or
venv_agent3\Scripts\activate  # Windows
```

### Verification
- [ ] `jsonschema` version >= 4.17 (supports draft 2020-12)
- [ ] `pydantic` version >= 2.0 (uses v2 API)
- [ ] `duckdb` version >= 0.9 (supports JSON functions)
- [ ] Python version >= 3.9

---

## 9. KEY FILES & LOCATIONS

### Input Files (to validate)
```
PEEC_Script/
├── om_design*.json                    (user designs)
├── om_prescreen*.json                 (prescreen configs)
├── om_excitation*.json                (excitation configs)
├── om_*_cache.json                    (cached results)
├── om_recommendation*.json            (recommendations)
├── om_visualization*.json             (viz metadata)
└── validation/results_*/
    └── *.json                         (benchmark results)
```

### Schema Files (to create)
```
schemas/
├── om_design_schema.json              (main design config)
├── om_prescreen_schema.json           (prescreen config)
├── om_excitation_schema.json          (excitation config)
├── om_cache_schema.json               (cache metadata)
└── migration/
    ├── 2024.01_to_2024.02.json       (schema migration rules)
    └── 2023.12_to_2024.01.json       (legacy migrations)
```

### Output Files (generated by Agent 3)
```
validation_reports/
├── latest_validation_report.json      (last full validation)
├── batch_validation_*.json            (per-batch reports)
└── lineage/
    └── design_id_lineage.json         (dependency graph)
```

---

## 10. DEPENDENCIES & CONSTRAINTS

### External Dependencies
- ✅ jsonschema library (Python)
- ✅ Deep inspection of 319 existing JSON files
- ⚠️ OpenMagnetics API schema (for wire/core validation)
  - May need to fetch/cache remote schema
  - Handle API version drift
  - Fallback to local snapshot

### Constraints
- 🔴 **Performance:** Validate all 319 files in <5 seconds
- 🟡 **Backwards compatibility:** Support schema v2024.01, v2023.12 (legacy)
- 🟡 **Data safety:** Never delete user data; always create backups before auto-fix
- 🟡 **Clear communication:** Error messages must be actionable by non-technical users

### Assumptions
- ✅ JSON files are UTF-8 encoded
- ✅ File paths are accessible (local filesystem)
- ✅ Schemas are versioned (e.g., "2024.02")
- ✅ Cache TTL is configurable (default: 24 hours)

---

## 11. SUCCESS STORIES & EXAMPLES

### Example 1: User loads stale config
**Before (without Agent 3):**
- User loads old config
- Runs PEEC solver
- Gets confusing results (config stale, results don't match reality)
- No indication something was wrong

**After (with Agent 3):**
```
Validation Report:
⚠️ WARNING: Config v2024.01 (system uses v2024.02)
   Recommended: Auto-migrate to v2024.02?

✅ Applied migration
✅ All required fields present
✅ No orphaned references
✅ Cache is fresh (generated 2 hours ago)

Ready to solve!
```

---

### Example 2: User accidentally deletes wire from database
**Before:**
- User deletes wire "AWG_36_litz"
- Config still references it
- PEEC solver fails with cryptic error
- User has to debug what happened

**After:**
```
Validation Report:
🔴 ERROR: File om_design_v1.json
   Field $.winding.wire_gauge_id
   Value: "AWG_36_litz"
   Problem: Wire not found in database

   Suggestion 1: Update to similar wire "AWG_36_solid"
   Suggestion 2: Import "AWG_36_litz" definition
   Suggestion 3: Remove this conductor

Data Lineage:
   om_design_v1.json depends on:
     └─ wire "AWG_36_litz" (NOT FOUND)
       └─ also referenced by: om_prescreen_config.json
```

User can immediately see the problem and its scope.

---

## 12. NEXT STEPS

### Immediate (This Sprint)
1. Review this specification
2. Feedback on error handling philosophy
3. Create JSON audit (Step 1 of Phase 1)

### Feedback Needed
- [ ] Are the 8 failure modes comprehensive? Any missing?
- [ ] Is auto-fix strategy right (conservative = no auto-fix unless very safe)?
- [ ] Accept schema version mismatch warnings? Or require upgrade?
- [ ] Acceptable performance target: <100ms per file, or <5s for 319?
- [ ] Data lineage tracking: critical, or nice-to-have?

### Ready to Build?
Once approved, Agent 3 development can start immediately with:
- Phase 1: JSON audit (2-3 days)
- Phase 2: MVP implementation (2 weeks)
- Phase 3: Integration (3-4 days)
- Phase 4: Documentation (1 week)

**Total: ~3 weeks to full implementation**

---

**Status:** ✅ Enhanced Specification Complete
**Template Ready:** Yes - Use this format for remaining 9 agents
**Next Agent:** Recommend enhancing Agent 1 (PEEC Optimizer) next - similar pattern

