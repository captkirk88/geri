# Benchmark Results

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 28.545 ms | 1000000 | 28.545 ns/run | 32.01MiB |
| Add Component | 291.063 ms | 1000000 | 291.063 ns/run | 14.63KiB |
| Add Component Bulk (1000000) | 1.160 s | 1000 | 1.160 ms/run | 63.64MiB |
| Query System (1000000) | 135.024 ms | 1000 | 135.024 us/run | 47.64MiB |
| Systems Runner | 96.800 us | 1000 | 96.800 ns/run | 40.02MiB |
| Scheduler 7 labels, 100 systems, 100k entities | 1.052 s | 100 | 10.518 ms/run | 31.84MiB |
| Serialize/Patch Entity | 13.156 ms | 1000 | 13.156 us/run | 16.41KiB |
| Serialize/Deserialize Resources | 11.691 ms | 1000 | 11.691 us/run | 11.17KiB |
