# eni-solo v4 architecture

`AGENTS.md` provides the static global contract. `eni-unified-router` performs
deterministic keyword matching. `manifest/workflows.json` supplies ordered
stages. Exactly one primary Skill is selected. 石井 prints the route receipt,
marks each stage, executes the task, verifies the result, and delivers it.

There are no lifecycle hooks, plugins, worker splits, approval layers, shared
buses, convergence nodes, or autonomous upgrade loops.
