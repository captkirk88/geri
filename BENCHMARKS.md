# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 20.205 ms | 1000000 | 20.205 ns/run | 28.00MiB |
| Add Component | 530.885 ms | 1000000 | 530.885 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 775.958 ms | 1000 | 775.958 us/run | 32.00MiB |
| Query System (1000000) | 256.842 ms | 1000 | 256.842 us/run | 144B |
| Systems Runner | 125.900 us | 1000 | 125.900 ns/run | 16.43KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 995.351 ms | 100 | 9.954 ms/run | 63.53KiB |
| Serialize/Patch Entity | 12.829 ms | 1000 | 12.829 us/run | 290B |
| Serialize/Deserialize Resources | 11.250 ms | 1000 | 11.250 us/run | 268B |
