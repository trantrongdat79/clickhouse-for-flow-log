# Phần 1: Mở đầu và bối cảnh
## 1. Vấn đề thực tiễn: Tại sao NetFlow? Tại sao high-cardinality lại là thách thức?
## 2. Mục tiêu đề tài: đánh giá pipeline phân tích dữ liệu netflow và khả năng ứng dụng vào hệ thống production
## 3. Phạm vi nghiên cứu: So sánh mức độ phù hợp kiểu dữ liệu netflow và clickhouse db, các tính năng biên để đưa clickhouse vào ứng dụng trong production (security, replication, backup & restore)

# Phần 2: Thiết kế hệ thống
## 1. Kiến trúc tổng thể: Router -> Kafka -> Clickhouse -> Grafana
- Khi nói, lưu ý audience rằng bài thuyết trình sẽ tập trung vào clickhouse - công cụ lưu trữ và truy vấn chính trong toàn bộ pipeline

## 2. Lý do chọn Clickhouse
- Một vài slide
- Đề cập về các lý thuyết về Clickhouse architecture
- Nhắc sơ về các slide sau sẽ so sánh clickhouse với một TSDB tiêu biểu là influxdb

## 3. Các tính năng đã triển khai
- Trong quá trình Schema design: CODEC(DoubleDelta, LZ4), Materialized view
- Các tính năng DB khác: security, replication, backup & restore

# Phần 3: Thực nghiệm và đánh giá
## 1. Video demo Grafana dashboard

## 2. Benchmark ClickHouse vs InfluxDB
- Phân tích phương pháp benchmark: Ingest pipeline,
- Kết quả Ingest
- Phân tích phương pháp benchmark: Query pipeline
- Kết quả Query

- Partition key / index granularity ảnh hưởng thế nào đến query?
- Compression ratio thay đổi ra sao giữa các trường low vs high cardinality?

## 3. Video demo security, replication, backup & restore
- ClickHouse playground

# Phần 4: Kết luận & Hướng phát triển
- Tổng hợp các phát hiện chính (3–4 bullet points)
- Những hạn chế của clickhouse
- Hướng mở rộng: streaming ingest thời gian thực, anomaly detection, scale lên cluster lớn hơn với sharding


Một số câu hỏi phổ biến:
- "Tại sao không dùng TimescaleDB / Elasticsearch?", 
- "High-cardinality ảnh hưởng thế nào đến memory?", 
- "Kết quả có reproducible không?"