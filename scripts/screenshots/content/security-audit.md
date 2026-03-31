# Security Audit — Findings

## HIGH — Refresh tokens in UserDefaults

Tokens persisted via `UserDefaults.standard` — unencrypted on disk.

**Fix:** Migrate to Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

## MEDIUM — No certificate pinning

`URLSession` uses default validation. Susceptible to proxy interception.

## LOW — Debug logging includes PII

`Logger.debug` in `AuthService` prints full JWT payload containing email.

| Severity | Count | Fixed |
|----------|-------|-------|
| High | 1 | In progress |
| Medium | 1 | Not started |
| Low | 1 | Fixed |
