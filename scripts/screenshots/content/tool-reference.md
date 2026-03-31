# Tool Reference

## Available Tools

### `swift_analyze_files`

Run static analysis on Swift source files. Returns diagnostics grouped by severity.

```bash
swift-lens analyze Sources/Auth/*.swift --severity warning
```

### `swift_find_symbol_references`

Find all usages of a symbol across the codebase.

```bash
swift-lens references "AuthenticationService" --include-tests
```

### `git_diff_summary`

Summarize changes between branches or commits.

```bash
git diff develop...HEAD --stat
```

### `run_tests`

Execute test suite with optional filter and coverage report.

```bash
swift test --filter "AuthTests" --enable-code-coverage
```
