# Benchmark Results

### System Specs
- **CPU**: AMD Ryzen 7 7735HS with Radeon Graphics (8 physical cores, 16 logical cores)
- **GPU**: AMD Radeon(TM) Graphics
- **RAM**: 28.75GiB

![Benchmark Graph](BENCHMARKS.bmp)

| Benchmark | Elapsed | Runs | Average | Bytes |
| :--- | :--- | :--- | :--- | :--- |
| Spawn Entities | 22.532 ms | 1000000 | 22.532 ns/run | 28.00MiB |
| Add Component | 532.622 ms | 1000000 | 532.622 ns/run | 3.42KiB |
| Add Component Bulk (1000000) | 846.898 ms | 1000 | 846.898 us/run | 32.00MiB |
| Query System (1000000) | 130.393 ms | 1000 | 130.393 us/run | 144B |
| Systems Runner | 141.900 us | 1000 | 141.900 ns/run | 16.37KiB |
| Scheduler 7 labels, 100 systems, 100k entities | 831.198 ms | 100 | 8.312 ms/run | 63.97KiB |
| Serialize/Patch Entity | 13.568 ms | 1000 | 13.568 us/run | 281B |
| Serialize/Deserialize Resources | 11.997 ms | 1000 | 11.997 us/run | 265B |
