# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 24.459 ms | 1000000 | 24.459 ns/run | 32.00MiB |
| Add Component | 534.256 ms | 1000000 | 534.256 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 1.102 s | 1000 | 1.102 ms/run | 32.00MiB |
| Query System (1000000) | 126.287 ms | 1000 | 126.287 us/run | 144B |
| Systems Runner | 133.700 us | 1000 | 133.700 ns/run | 16.37KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 857.869 ms | 100 | 8.579 ms/run | 50.48KiB |
| Serialize/Patch Entity | 13.210 ms | 1000 | 13.210 us/run | 292B |
| Serialize/Deserialize Resources | 11.410 ms | 1000 | 11.410 us/run | 147B |
