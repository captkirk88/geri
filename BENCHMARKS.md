# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 25.925 ms | 1000000 | 25.925 ns/run | 32.00MiB |
| Add Component | 615.139 ms | 1000000 | 615.139 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 1.228 s | 1000 | 1.228 ms/run | 32.00MiB |
| Query System (1000000) | 140.407 ms | 1000 | 140.407 us/run | 144B |
| Systems Runner | 162.400 us | 1000 | 162.400 ns/run | 16.37KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 909.843 ms | 100 | 9.098 ms/run | 50.48KiB |
| Serialize/Patch Entity | 13.739 ms | 1000 | 13.739 us/run | 292B |
| Serialize/Deserialize Resources | 11.953 ms | 1000 | 11.953 us/run | 163B |
