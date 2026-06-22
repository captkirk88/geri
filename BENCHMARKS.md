# Benchmark Results

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 27.530 ms | 1000000 | 27.530 ns/run | 32.00MiB |
| Add Component | 290.265 ms | 1000000 | 290.265 ns/run | 3.36KiB |
| Add Component Bulk (1000000) | 1.124 s | 1000 | 1.124 ms/run | 24.00MiB |
| Query System (1000000) | 129.385 ms | 1000 | 129.385 us/run | 144B |
| Systems Runner | 97.000 us | 1000 | 97.000 ns/run | 8.43KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 1.016 s | 100 | 10.165 ms/run | 50.48KiB |
| Serialize/Patch Entity | 12.474 ms | 1000 | 12.474 us/run | 266B |
| Serialize/Deserialize Resources | 11.083 ms | 1000 | 11.083 us/run | 268B |
