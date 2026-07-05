# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 22.974 ms | 1000000 | 22.974 ns/run | 28.00MiB |
| Add Component | 556.761 ms | 1000000 | 556.761 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 856.733 ms | 1000 | 856.733 us/run | 32.00MiB |
| Query System (1000000) | 234.968 ms | 1000 | 234.968 us/run | 144B |
| Systems Runner | 142.400 us | 1000 | 142.400 ns/run | 16.37KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 1.080 s | 100 | 10.801 ms/run | 63.97KiB |
| Serialize/Patch Entity | 13.039 ms | 1000 | 13.039 us/run | 290B |
| Serialize/Deserialize Resources | 11.566 ms | 1000 | 11.566 us/run | 160B |
