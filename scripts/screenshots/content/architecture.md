# System Architecture

## Layer Overview

| Layer | Responsibility | Key Types |
|-------|---------------|-----------|
| **Auth** | OAuth 2.0, tokens | `AuthService`, `Keychain` |
| **Network** | HTTP, WebSocket | `NetworkClient`, `WSManager` |
| **Storage** | Core Data, cache | `CacheManager`, `Journal` |
| **Agents** | AI orchestration | `AgentRunner`, `ToolRegistry` |

## Design Principles

1. **Isolation** — each service runs in its own `actor`
2. **Composability** — agents chain tools via `Pipeline`
3. **Observability** — OpenTelemetry span at every boundary

## Data Flow

> Requests flow through the auth interceptor, which injects the Bearer
> token and handles 401 retry transparently. All network calls are
> `async throws` and support structured concurrency cancellation.
