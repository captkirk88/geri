# Benchmark Results

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 24.529 ms | 1000000 | 24.529 ns/run | - |
| Add Component | 291.206 ms | 1000000 | 291.206 ns/run | - |
| Add Component Bulk (1000000) | 1.064 s | 1000 | 1.064 ms/run | - |
| Query System (1000000) | 230.727 ms | 1000 | 230.727 us/run | - |
| Systems Runner | 194.100 us | 1000 | 194.100 ns/run | - |
| Serialize/Patch Entity | 12.418 ms | 1000 | 12.418 us/run | - |
| Serialize/Deserialize Resources | 10.570 ms | 1000 | 10.570 us/run | - |
