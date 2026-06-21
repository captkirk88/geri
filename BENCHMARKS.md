# Benchmark Results

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 24.292 ms | 1000000 | 24.292 ns/run | - |
| Add Component | 281.413 ms | 1000000 | 281.413 ns/run | - |
| Add Component Bulk (1000000) | 1.132 s | 1000 | 1.132 ms/run | - |
| Query System (1000000) | 135.196 ms | 1000 | 135.196 us/run | - |
| Systems Runner | 176.300 us | 1000 | 176.300 ns/run | - |
| Serialize/Patch Entity | 12.300 ms | 1000 | 12.300 us/run | - |
| Serialize/Deserialize Resources | 10.764 ms | 1000 | 10.764 us/run | - |
