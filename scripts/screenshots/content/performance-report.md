# Performance Analysis — Agent Pipeline

## Benchmark

- Machine: M4 Pro, 48 GB RAM
- Workload: 1M tool invocations across 4 agent types

## Results

| Concurrency | Throughput | p50 | p99 | Memory |
|------------|-----------|-----|-----|--------|
| 1 task | 12,400/s | 0.08ms | 0.4ms | 45 MB |
| 4 tasks | 48,200/s | 0.09ms | 0.6ms | 82 MB |
| 16 tasks | 156,000/s | 0.12ms | 1.2ms | 210 MB |

## Bottleneck

At 16 tasks, `ToolRegistry.resolve()` becomes contention point due to actor reentrancy. Consider sharding the registry by tool category.
