# Skill: Security Review

## When to Use

Before merging PRs that touch authentication, storage, or network code.

## Checklist

- [ ] No secrets in source code or logs
- [ ] Tokens stored in Keychain, not UserDefaults
- [ ] Certificate pinning on sensitive endpoints
- [ ] PII redacted from log output
- [ ] Input validation on all external data

## Tools

- `grep` for hardcoded secrets patterns
- `swift_analyze_files` for unsafe API usage
- `git log` to check if `.env` files were ever committed
