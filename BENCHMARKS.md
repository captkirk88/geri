# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 24.530 ms | 1000000 | 24.530 ns/run | 32.00MiB |
| Add Component | 537.266 ms | 1000000 | 537.266 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 1.124 s | 1000 | 1.124 ms/run | 32.00MiB |
| Query System (1000000) | 147.321 ms | 1000 | 147.321 us/run | 144B |
| Systems Runner | 148.100 us | 1000 | 148.100 ns/run | 16.37KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 851.314 ms | 100 | 8.513 ms/run | 50.48KiB |
| Serialize/Patch Entity | 13.157 ms | 1000 | 13.157 us/run | 281B |
| Serialize/Deserialize Resources | 11.427 ms | 1000 | 11.427 us/run | 268B |
