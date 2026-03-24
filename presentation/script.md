# Phần 1: Mở đầu và bối cảnh (5')
## 1. Vấn đề thực tiễn: 
- Slide 1: Tại sao NetFlow? 
- Slide 2: Ảnh minh họa về các đồ thị mà netflow hỗ trợ
- Slide 3: High cardinality là gì? (visualize) Tại sao high-cardinality lại là thách thức?
## 2. Mục tiêu đề tài: đánh giá pipeline phân tích dữ liệu netflow và khả năng ứng dụng vào hệ thống production
- Slide 1: 
    - Đánh giá hiệu năng clickhouse khi sử dụng cho kiểu dữ liệu netflow
    - So sánh với Influx DB
    - Thử nghiệm các tính năng khác như security, replication, backup & restore để đảm bảo tính sẵn sàng cho hệ thống production

## 3. Phạm vi nghiên cứu: So sánh mức độ phù hợp kiểu dữ liệu netflow và clickhouse db, các tính năng biên để đưa clickhouse vào ứng dụng trong production (security, replication, backup & restore)
 - Slide 1:
    - Nghiên cứu kiến trúc thiết kế của Clickhouse, các kỹ thuật tối ưu lưu trữ, xử lý của Clickhouse khi sử dụng cho kiểu dữ liệu netflow
    - Đánh giá và so sánh hiệu năng Ingestion, Storage, Query Performance với InfluxDB (quan sát và so sánh kết quả, không đi sâu vào cấu trúc thiết kế, optimize hoặc fine tuning InfluxDB)
    - Triển khai các tính năng security, replication, backup & restore, không đi sâu vào chi tiết đánh giá hiệu năng

# Phần 2: Thiết kế hệ thống (10')
## 1. Kiến trúc tổng thể: Router -> Kafka -> Clickhouse -> Grafana
- Slide 1:
    - Đề cập sơ về kiến trúc triển khai trong thực tế
    - Lí do đề cập đến slide là để trong phần 3 sẽ có một video Demo, được xây dựng trên hệ thống này
    - Khi nói, lưu ý audience rằng bài thuyết trình sẽ tập trung vào clickhouse - công cụ lưu trữ và truy vấn chính trong toàn bộ pipeline

## 2. Lý do chọn Clickhouse
- Slide 1, 2:  Đề cập về các lý thuyết về Clickhouse architecture

## 3. Các tính năng đã triển khai
- Slide 1, 2, 3:
    - Các tính năng được sử dụng để tăng khả năng lưu trữ, xử lý cho netflow data: CODEC(DoubleDelta, LZ4), Materialized view

- Slide 4: Các tính năng DB khác: security
- Slide 5: replication
- Slide 6: Backup & restore

# Phần 3: Thực nghiệm và đánh giá
## 1. Video demo Grafana dashboard (5')

## 2. Benchmark ClickHouse vs InfluxDB (15')
- Phân tích phương pháp benchmark: Ingest pipeline,
- Kết quả Ingest: Ingestion Time, After Ingest Size, CPU Usage, Memory Usage, Memory Cache

- Phân tích phương pháp benchmark: Query pipeline
- Kết quả Query: Total, CPU Usage, Memory Usage, Memory Cache,

- Partition key / index granularity ảnh hưởng thế nào đến query?
- Compression ratio thay đổi ra sao giữa các trường low vs high cardinality?

## 3. Video demo security, replication, backup & restore (5')
- ClickHouse playground

# Phần 4: Kết luận & Hướng phát triển (5')
- Tổng hợp các phát hiện chính (3–4 bullet points)
- Những hạn chế của clickhouse
- Hướng mở rộng: streaming ingest thời gian thực, anomaly detection, scale lên cluster lớn hơn với sharding


Một số câu hỏi phổ biến:
- "Tại sao không dùng TimescaleDB", 
- "High-cardinality ảnh hưởng thế nào đến memory?", 
- "Kết quả có reproducible không?"

# References:
https://altinity.com/blog/clickhouse-for-time-series
https://blog.elest.io/clickhouse-vs-timescaledb-vs-influxdb-picking-the-right-analytics-database-for-your-self-hosted-stack/
https://sanj.dev/post/clickhouse-timescaledb-influxdb-time-series-comparison
