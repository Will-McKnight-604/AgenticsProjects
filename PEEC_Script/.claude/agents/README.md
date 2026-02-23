# PEEC Design Tool Sub-Agents

This directory contains 10 specialized Claude Sub-Agents for the PEEC electromagnetic design tool.

## What Are These?

These are Markdown files with YAML frontmatter that define how Claude should behave when handling specific tasks in your project. Each agent is a specialized assistant with:

- **Custom system prompt** (instructions for Claude)
- **Tool restrictions** (which tools the agent can use)
- **Model selection** (which Claude model to use)
- **Description** (when Claude should invoke the agent)

## The 10 Agents

### 1. **peec-optimizer** (Agent 1)
Optimizes PEEC matrix computations and filament discretization for performance.
- **When used:** Performance optimization, solver bottleneck analysis
- **Tools:** Read, Grep, Glob, Bash
- **Model:** Sonnet

### 2. **winding-validator** (Agent 2)
Validates winding layouts, detects packing failures, and generates DRC reports.
- **When used:** Winding design validation, packing feasibility
- **Tools:** Read, Grep, Glob, Bash, Write
- **Model:** Sonnet

### 3. **json-reconciler** (Agent 3)
Validates JSON configurations, detects orphaned entries, and checks cache coherency.
- **When used:** Config validation, data integrity checks
- **Tools:** Read, Grep, Glob, Bash, Write
- **Model:** Haiku (fast)

### 4. **test-orchestrator** (Agent 4)
Orchestrates testing across MATLAB/Python/Web and detects performance regressions.
- **When used:** Full test execution, regression detection
- **Tools:** Read, Grep, Glob, Bash, Write
- **Model:** Sonnet

### 5. **web-wizard** (Agent 5)
Manages wizard state machines and validates parameter handoffs.
- **When used:** Wizard workflow debugging, state analysis
- **Tools:** Read, Grep, Glob, Bash
- **Model:** Sonnet

### 6. **api-bridge** (Agent 6)
Manages OpenMagnetics API calls with caching and fallback strategies.
- **When used:** API queries, cache management, offline operation
- **Tools:** Read, Bash, Write
- **Model:** Sonnet

### 7. **loss-visualization** (Agent 7)
Validates loss calculations and generates interactive visualizations.
- **When used:** Loss analysis, hotspot identification, optimization
- **Tools:** Read, Bash, Write, Grep
- **Model:** Sonnet

### 8. **thermal-integrator** (Agent 8)
Implements loss-temperature coupling and thermal network modeling.
- **When used:** Temperature estimation, IEC compliance, thermal design
- **Tools:** Read, Bash, Write
- **Model:** Sonnet

### 9. **octave-ci** (Agent 9)
Ensures Octave/MATLAB compatibility and manages CI/CD pipelines.
- **When used:** Compatibility verification, multi-platform testing
- **Tools:** Read, Bash, Grep, Glob
- **Model:** Sonnet

### 10. **cad-export** (Agent 10)
Generates CAD exports, performs DFM validation, and estimates manufacturing costs.
- **When used:** CAD generation, manufacturability assessment
- **Tools:** Read, Bash, Write
- **Model:** Sonnet

## How Claude Uses These

Claude automatically invokes these agents based on task descriptions. For example:

1. **User asks:** "Check if this design will be manufacturable"
2. **Claude recognizes:** This is a DFM/CAD task
3. **Claude spawns:** agent-10-cad-export (the cad-export agent)
4. **Agent analyzes:** Design geometry, manufacturing constraints
5. **Agent returns:** DFM report with cost estimates and feasibility

## Key Features

- **Isolated contexts:** Each agent has its own context window
- **Focused tools:** Only necessary tools are available to each agent
- **Specialized prompts:** Each agent is tuned for its specific domain
- **Efficient models:** Uses Haiku for fast validation tasks, Sonnet for complex analysis

## Using These Agents in Claude Code

### Automatic Invocation
Claude will automatically call agents when it detects matching work:

```
"Validate the winding layout for this design"
→ Claude spawns winding-validator agent
```

### Explicit Invocation
You can explicitly request a specific agent:

```
"Use the json-reconciler agent to validate all JSON files"
→ Claude immediately uses that agent
```

## Agent Dependencies

```
JSON Reconciler (validates all configs)
    ↓
    ├→ PEEC Optimizer (solves with clean config)
    ├→ Winding Validator (validates winding)
    ├→ API Bridge (queries remote data)
    └→ Web Wizard (saves state)
         ↓
    Loss Visualization (analyzes loss)
         ↓
    Thermal Integrator (estimates temperature)
```

## File Structure

```
.claude/agents/
├── README.md (this file)
├── agent-1-peec-optimizer.md
├── agent-2-winding-validator.md
├── agent-3-json-reconciler.md
├── agent-4-test-orchestrator.md
├── agent-5-web-wizard.md
├── agent-6-api-bridge.md
├── agent-7-loss-visualization.md
├── agent-8-thermal-integrator.md
├── agent-9-octave-ci.md
└── agent-10-cad-export.md
```

## Getting Started

1. **Review the agents** - Start with agent-3 (json-reconciler) to understand the format
2. **Notice the descriptions** - Each agent's description is what triggers Claude
3. **Check tool access** - Each agent lists exactly which tools it can use
4. **See the prompts** - The markdown body is what Claude uses as system prompt

## Next Steps

These agents are now available in your Claude Code environment:

- Claude will automatically use them when appropriate
- You can also explicitly invoke them by name
- Each agent is designed to work independently but can pass data through JSON

---

**Created:** 2026-02-22
**Total Agents:** 10
**Total Size:** 92 KB
**Status:** Ready for use
