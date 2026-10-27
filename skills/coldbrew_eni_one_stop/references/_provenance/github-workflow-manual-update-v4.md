# Manual GitHub workflow refresh

Run only when the user explicitly requests an update:

`python scripts/github_workflow_upgrade.py refresh --package-root . --out-dir <evidence-dir>`

Review the diff and tests before running its explicit install command.
