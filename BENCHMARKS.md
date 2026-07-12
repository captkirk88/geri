# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 21.674 ms | 1000000 | 21.674 ns/run | 28.00MiB |
| Add Component | 531.493 ms | 1000000 | 531.493 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 793.516 ms | 1000 | 793.516 us/run | 32.00MiB |
| Query System (1000000) | 185.556 ms | 1000 | 185.556 us/run | 144B |
| Systems Runner | 140.000 us | 1000 | 140.000 ns/run | 16.43KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 977.778 ms | 100 | 9.778 ms/run | 67.44KiB |
| Serialize/Patch Entity | 12.732 ms | 1000 | 12.732 us/run | 290B |
| Serialize/Deserialize Resources | 10.922 ms | 1000 | 10.922 us/run | 160B |
