# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: Unknown GPU
- **RAM**: 14.01GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 57.558 ms | 1000000 | 57.558 ns/run | 32.00MiB |
| Add Component | 263.152 ms | 1000000 | 263.152 ns/run | 3.36KiB |
| Add Component Bulk (1000000) | 1.103 s | 1000 | 1.103 ms/run | 24.00MiB |
| Query System (1000000) | 154.337 ms | 1000 | 154.337 us/run | 144B |
| Systems Runner | 93.945 us | 1000 | 93.945 ns/run | 8.43KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 1.304 s | 100 | 13.042 ms/run | 50.48KiB |
| Serialize/Patch Entity | 11.939 ms | 1000 | 11.939 us/run | 290B |
| Serialize/Deserialize Resources | 10.698 ms | 1000 | 10.698 us/run | 160B |
