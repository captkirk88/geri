# Benchmark Results

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 26.733 ms | 1000000 | 26.733 ns/run | 32.00MiB |
| Add Component | 287.723 ms | 1000000 | 287.723 ns/run | 3.36KiB |
| Add Component Bulk (1000000) | 1.133 s | 1000 | 1.133 ms/run | 24.00MiB |
| Query System (1000000) | 129.771 ms | 1000 | 129.771 us/run | 144B |
| Systems Runner | 97.500 us | 1000 | 97.500 ns/run | 8.43KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 997.145 ms | 100 | 9.971 ms/run | 50.48KiB |
| Serialize/Patch Entity | 12.713 ms | 1000 | 12.713 us/run | 288B |
| Serialize/Deserialize Resources | 11.199 ms | 1000 | 11.199 us/run | 265B |
