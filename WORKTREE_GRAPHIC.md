# AgenticsProjects Worktree Map

```mermaid
flowchart TB
  subgraph GH["GitHub Remote"]
    R["PEEC_Solver\nAgenticsProjects.git"]
    RM["remote branch: main"]
    RC["remote branch: codex-cli"]
    RCL["remote branch: claude-cli"]
  end

  subgraph LOCAL["Local shared Git metadata (single repo database)"]
    G["common git dir\nC:/Users/Will/proximity_loss/Claude/.git"]
    LM["local ref: main"]
    LC["local ref: codex-cli"]
    LCW["local ref: codex-cli-wip"]
    LCL["local ref: claude-cli"]
  end

  subgraph WTS["Local worktrees (separate folders)"]
    WMain["C:/Users/Will/proximity_loss/codex-cli-feature-work\nchecked out: main"]
    WCodex["C:/Users/Will/proximity_loss/codex-cli\nchecked out: codex-cli"]
    WCodexWip["C:/Users/Will/proximity_loss/Claude\nchecked out: codex-cli-wip"]
    WClaude["C:/Users/Will/proximity_loss/claude-cli\nchecked out: claude-cli"]
  end

  R --> G
  G --> LM
  G --> LC
  G --> LCW
  G --> LCL

  LM --> WMain
  LC --> WCodex
  LCW --> WCodexWip
  LCL --> WClaude

  LM -. tracks .-> RM
  LC -. tracks .-> RC
  LCL -. tracks .-> RCL
```

## How changes flow from this worktree

1. You edit files in `C:/Users/Will/proximity_loss/codex-cli-feature-work`.
2. You commit on `main` in this worktree.
3. The shared local `main` ref in `C:/Users/Will/proximity_loss/Claude/.git` moves to the new commit.
4. When pushed, `PEEC_Solver/main` on `AgenticsProjects.git` moves to that commit.

## What happens on merge

1. If you merge another branch into `main` from this worktree, local `main` advances.
2. Pushing updates `PEEC_Solver/main` on GitHub.
3. Other worktrees see the new commit after fetch/pull or when checked out to it.
