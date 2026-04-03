# Index: Dynamic Field Visibility System

**Project**: PEEC Proximity Loss Analysis Tool
**Component**: topology_wizard.m Dynamic Field Visibility
**Version**: 1.0
**Date**: 2026-02-27
**Status**: Ready for Integration

## Document Structure

This implementation package contains comprehensive documentation organized by use case:

### Quick Navigation

| Need | Document | Time |
|------|----------|------|
| **Overview** | README_TOPOLOGY_VISIBILITY.md | 5 min |
| **Integration** | STEP_BY_STEP_INTEGRATION.md | 15 min |
| **Reference** | QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt | 3 min |
| **Code Examples** | UPDATED_CALLBACKS_EXAMPLE.m | 5 min |
| **Detailed Guide** | INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md | 20 min |
| **Code Changes** | BEFORE_AFTER_COMPARISON.md | 10 min |

## Files in This Package

### 1. Core Implementation

#### topology_field_visibility_system.m (750 lines)
**Purpose**: Complete visibility management system
**Contains**:
- Metadata definitions for all 9 topologies
- Field visibility functions
- Value collection utilities
- Topology categorization helpers

**Key Functions**:
```
get_topology_metadata(topology_key)
update_field_visibility(fig, topology_key)
get_visible_fields_for_topology(topology_key)
get_topology_output_type(topology_key)
collect_gui_field_values(fig, topology_key)
rebuild_output_spec_table(fig, topology_key)
```

**When to use**: Copy to same directory as topology_wizard.m

### 2. Documentation (Ordered by Use Case)

#### README_TOPOLOGY_VISIBILITY.md (400 lines)
**Purpose**: Executive summary and quick start
**Best for**: First-time readers, overview seekers
**Sections**:
- Executive summary
- Key features
- Quick start (5 min)
- Architecture overview
- Core functions reference
- Testing section
- Future enhancements

**Time to read**: 5-10 minutes

#### STEP_BY_STEP_INTEGRATION.md (600 lines)
**Purpose**: Detailed step-by-step integration guide
**Best for**: Implementing the system
**Sections**:
- Prerequisites
- 10 numbered steps with code snippets
- Verification procedures
- Testing checklist
- Troubleshooting section
- Success criteria

**Time to complete**: 15-20 minutes integration + 10 min testing

#### INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md (500 lines)
**Purpose**: Complete technical integration guide
**Best for**: Understanding all details
**Sections**:
- Overview and architecture
- Function references with usage examples
- Topology metadata reference table
- 6 integration steps with code blocks
- Field name mapping
- Example use cases
- Testing checklist
- Future enhancement roadmap

**Time to read**: 20-30 minutes

#### QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt (300 lines)
**Purpose**: Quick lookup reference
**Best for**: Looking up specific information while coding
**Sections**:
- Quick start checklist
- Core functions summary
- Topology categories
- Field requirements matrix
- Field name mapping
- Callback updates needed
- Common usage patterns
- Troubleshooting FAQ

**Time to use**: 1-2 minutes per lookup

#### UPDATED_CALLBACKS_EXAMPLE.m (350 lines)
**Purpose**: Complete code snippets to integrate
**Best for**: Copy/paste during implementation
**Sections**:
- Updated cb_topology_changed()
- Updated cb_n_outputs()
- Updated cb_n_outputs_plus()
- Updated cb_n_outputs_minus()
- New code in build_gui()
- Updated cb_compute_topology()
- Updated collect_gui_field_values()
- Updated cb_toggle_optional()
- Helper usage examples

**How to use**: Copy each function block into topology_wizard.m

#### BEFORE_AFTER_COMPARISON.md (400 lines)
**Purpose**: Side-by-side code comparison
**Best for**: Understanding what changes
**Sections**:
- 4 major callback changes with before/after
- Key changes tables
- Benefits of each change
- New functions added (7 functions)
- Implementation complexity analysis
- Testing impact section
- Backward compatibility notes
- Code statistics

**Time to read**: 10-15 minutes

## Quick Start Paths

### Path 1: "Just Make It Work" (25 minutes)

1. Read README_TOPOLOGY_VISIBILITY.md (5 min)
2. Follow STEP_BY_STEP_INTEGRATION.md (15 min)
3. Run tests (5 min)

**Result**: Fully integrated and tested system

### Path 2: "Understand Everything" (45 minutes)

1. Read README_TOPOLOGY_VISIBILITY.md (5 min)
2. Study BEFORE_AFTER_COMPARISON.md (10 min)
3. Read INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md (20 min)
4. Follow STEP_BY_STEP_INTEGRATION.md (10 min)

**Result**: Deep understanding + integrated system

### Path 3: "I Just Need the Reference" (5 minutes)

1. Use QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt as bookmark
2. Copy code from UPDATED_CALLBACKS_EXAMPLE.m as needed
3. Refer to README_TOPOLOGY_VISIBILITY.md for overview

**Result**: Reference card for integration

### Path 4: "Custom Implementation" (variable)

1. Review INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md for detailed API
2. Copy topology_field_visibility_system.m to your directory
3. Integrate only the functions you need
4. Use UPDATED_CALLBACKS_EXAMPLE.m as templates

**Result**: Custom integration tailored to your needs

## File Dependencies

```
topology_field_visibility_system.m
    ↓
topology_wizard.m (requires above file)
    ↓
Callbacks that must be updated:
    - cb_topology_changed()
    - cb_n_outputs()
    - cb_n_outputs_plus()
    - cb_n_outputs_minus()
    - cb_toggle_optional()
    - build_gui()
```

## Recommended Reading Order

### For Integration

1. **Start**: README_TOPOLOGY_VISIBILITY.md
   - Get context and overview
   - Understand what you're implementing
   - 5-10 minutes

2. **Then**: STEP_BY_STEP_INTEGRATION.md
   - Follow each step exactly
   - Copy code from UPDATED_CALLBACKS_EXAMPLE.m
   - Verify after each step
   - 20-30 minutes

3. **Reference**: QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt
   - Keep open while coding
   - Quick answers to specific questions
   - 1-2 minutes per lookup

### For Understanding

1. **Start**: README_TOPOLOGY_VISIBILITY.md
   - Executive summary
   - Architecture overview
   - 5 minutes

2. **Then**: BEFORE_AFTER_COMPARISON.md
   - See what changes
   - Understand benefits
   - 10-15 minutes

3. **Then**: INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md
   - Deep dive into each function
   - Complete architecture explanation
   - 20-30 minutes

4. **Reference**: QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt
   - Keep for quick lookups
   - 1-2 minutes per lookup

### For Implementation Review

1. **Check**: UPDATED_CALLBACKS_EXAMPLE.m
   - See exact code to integrate
   - Compare with your changes
   - 5-10 minutes

2. **Verify**: STEP_BY_STEP_INTEGRATION.md Step 10
   - Use testing checklist
   - Ensure all functionality works
   - 10-15 minutes

## Integration Checklist

### Pre-Integration
- [ ] Backup topology_wizard.m (original.backup)
- [ ] Read README_TOPOLOGY_VISIBILITY.md
- [ ] Understand the 9 topologies
- [ ] Have MATLAB/Octave open

### During Integration
- [ ] Copy topology_field_visibility_system.m to script directory
- [ ] Add path setup to topology_wizard.m
- [ ] Update cb_topology_changed() callback
- [ ] Update cb_n_outputs() callback
- [ ] Update cb_n_outputs_plus() callback
- [ ] Update cb_n_outputs_minus() callback
- [ ] Update cb_toggle_optional() callback
- [ ] Add initialization to build_gui()
- [ ] Check for syntax errors

### Testing
- [ ] Run topology_wizard
- [ ] Select each topology from dropdown
- [ ] Verify N outputs spinner visibility
- [ ] Test optional fields toggle
- [ ] Run full workflow (compute + recommendations)
- [ ] Check MATLAB command window for errors

### Post-Integration
- [ ] Commit changes to git
- [ ] Document any custom modifications
- [ ] Keep this documentation file with project
- [ ] Review QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt as needed

## Key Concepts

### Metadata System
Every topology has metadata defining:
- Display name
- Whether it's isolated (transformer required)
- Number of outputs (single or multi)
- Required fields (always visible)
- Optional fields (shown with toggle)

### Field Visibility
- **Required**: Always visible for a topology
- **Optional**: Shown only when toggle button pressed
- **Hidden**: Not applicable for this topology

### Topology Categories
- **Isolated** (9 topologies): Two-Switch Forward, Single-Switch Forward, Active Clamp Forward, Flyback, Push-Pull, Isolated Buck, Isolated Buck-Boost
- **Non-Isolated** (2 topologies): Buck, Boost
- **Multi-Output** (7 topologies): All isolated + need N outputs spinner
- **Single-Output** (2 topologies): Buck and Boost only

## Common Questions

**Q: Do I need to modify all callbacks?**
A: Only 6 callbacks need updates. Most other code stays the same.

**Q: How long does integration take?**
A: 15-20 minutes for implementation + 10 minutes testing = 25-30 minutes total.

**Q: Can I revert if something goes wrong?**
A: Yes, restore from topology_wizard.m.backup file.

**Q: Do I need to understand all 9 topologies?**
A: No, the metadata system handles all topology-specific logic.

**Q: Can I add more topologies later?**
A: Yes, add metadata struct + update dropdown and topology_keys list.

**Q: Is this backward compatible?**
A: Yes, 100% backward compatible. All changes are additive.

## Support Resources

### If Something Goes Wrong

1. Check QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt "Troubleshooting" section
2. Review STEP_BY_STEP_INTEGRATION.md "Troubleshooting" section
3. Look at BEFORE_AFTER_COMPARISON.md for expected changes
4. Verify you're using code from UPDATED_CALLBACKS_EXAMPLE.m

### If You Need Details

1. Specific function behavior → README_TOPOLOGY_VISIBILITY.md
2. Integration steps → STEP_BY_STEP_INTEGRATION.md
3. Code changes → BEFORE_AFTER_COMPARISON.md
4. Complete API reference → INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md
5. Quick lookup → QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt

## File Sizes

| File | Size | Type | Purpose |
|------|------|------|---------|
| topology_field_visibility_system.m | 19 KB | Code | Core system |
| README_TOPOLOGY_VISIBILITY.md | 12 KB | Doc | Overview |
| STEP_BY_STEP_INTEGRATION.md | 15 KB | Doc | Implementation |
| INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md | 14 KB | Doc | Technical detail |
| UPDATED_CALLBACKS_EXAMPLE.m | 10 KB | Code | Code snippets |
| BEFORE_AFTER_COMPARISON.md | 13 KB | Doc | Code comparison |
| QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt | 8 KB | Doc | Quick reference |
| **Total** | **~91 KB** | - | - |

## Next Steps

1. **Now**: Read README_TOPOLOGY_VISIBILITY.md (5 min)
2. **Then**: Follow STEP_BY_STEP_INTEGRATION.md (20 min)
3. **Test**: Use testing checklist (10 min)
4. **Reference**: Keep QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt open (ongoing)

## Version & Maintenance

**Current Version**: 1.0 (2026-02-27)

### Phase 2 (Future): Dynamic Output Tables
- Will enhance rebuild_output_spec_table()
- Add/remove output rows dynamically
- Estimated 100-150 lines of code

### Phase 3 (Future): Advanced Mode
- Add advanced-only fields
- Extend visibility rules
- Estimated 50-75 lines of code

### Phase 4 (Future): Field Validation
- Topology-aware constraints
- Value validation as user types
- Estimated 100-150 lines of code

### Phase 5 (Future): Contextual Help
- Dynamic tooltips based on topology
- Topology-specific guidance
- Estimated 75-100 lines of code

See INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md for details on future enhancements.

---

**Ready to start?** Begin with README_TOPOLOGY_VISIBILITY.md, then follow STEP_BY_STEP_INTEGRATION.md.

**Questions?** See QUICK_REFERENCE_TOPOLOGY_VISIBILITY.txt troubleshooting section.

**Need details?** Check INTEGRATION_GUIDE_TOPOLOGY_VISIBILITY.md or BEFORE_AFTER_COMPARISON.md.
