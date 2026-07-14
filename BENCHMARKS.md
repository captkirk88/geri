# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 20.984 ms | 1000000 | 20.984 ns/run | 28.00MiB |
| Add Component | 550.567 ms | 1000000 | 550.567 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 836.432 ms | 1000 | 836.432 us/run | 32.00MiB |
| Query System (1000000) | 135.153 ms | 1000 | 135.153 us/run | 144B |
| Systems Runner | 171.300 us | 1000 | 171.300 ns/run | 16.43KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 869.608 ms | 100 | 8.696 ms/run | 67.44KiB |
| Serialize/Patch Entity | 12.937 ms | 1000 | 12.937 us/run | 292B |
| Serialize/Deserialize Resources | 11.081 ms | 1000 | 11.081 us/run | 265B |
