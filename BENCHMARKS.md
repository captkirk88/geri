# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 19.803 ms | 1000000 | 19.803 ns/run | 28.00MiB |
| Add Component | 532.916 ms | 1000000 | 532.916 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 847.015 ms | 1000 | 847.015 us/run | 32.00MiB |
| Query System (1000000) | 145.958 ms | 1000 | 145.958 us/run | 144B |
| Systems Runner | 127.000 us | 1000 | 127.000 ns/run | 16.43KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 1.043 s | 100 | 10.434 ms/run | 63.53KiB |
| Serialize/Patch Entity | 12.550 ms | 1000 | 12.550 us/run | 281B |
| Serialize/Deserialize Resources | 10.809 ms | 1000 | 10.809 us/run | 265B |
