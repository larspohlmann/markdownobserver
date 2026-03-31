# Agent: Test Writer

## Role

Generates unit tests for new or modified code, following existing test patterns in the project.

## Configuration

```yaml
test_framework: XCTest
mock_style: protocol-based
coverage_target: 85%
test_location: Tests/{module}Tests/
naming: test{MethodName}_{scenario}_{expected}
```

## Workflow

1. Analyze changed files via `git diff`
2. Identify untested code paths
3. Generate test stubs matching project conventions
4. Run tests to verify they compile and pass

## Examples

See `skills/write-tests.md` for prompt templates.
