# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 27.477 ms | 1000000 | 27.477 ns/run | 32.00MiB |
| Add Component | 544.472 ms | 1000000 | 544.472 ns/run | 3.36KiB |
| Add Component Bulk (1000000) | 1.119 s | 1000 | 1.119 ms/run | 24.00MiB |
| Query System (1000000) | 127.762 ms | 1000 | 127.762 us/run | 144B |
| Systems Runner | 107.200 us | 1000 | 107.200 ns/run | 8.43KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 987.257 ms | 100 | 9.873 ms/run | 50.48KiB |
| Serialize/Patch Entity | 14.014 ms | 1000 | 14.014 us/run | 266B |
| Serialize/Deserialize Resources | 12.035 ms | 1000 | 12.035 us/run | 147B |
