# Claude Code Observability Stack

Prometheus + Loki + Grafana + OpenTelemetry Collector 기반의 Claude Code 모니터링 스택

## 아키텍처

```
Claude Code
    │
    ▼ OTLP (gRPC :4317 / HTTP :4318)
┌─────────────────────┐
│  OTel Collector     │
│  ─────────────────  │
│  Receivers: OTLP    │
│  Exporters:         │
│   - Prometheus      │
│   - Loki            │
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
┌────────┐  ┌────────┐
│Prometheus│ │  Loki  │
│ :9090   │ │ :3100  │
└────┬────┘ └────┬───┘
     │           │
     └─────┬─────┘
           ▼
     ┌──────────┐
     │ Grafana  │
     │  :3000   │
     └──────────┘
```

## 포트

| Service        | Port | 설명                      |
|----------------|------|---------------------------|
| OTel Collector | 4317 | OTLP gRPC receiver        |
| OTel Collector | 4318 | OTLP HTTP receiver        |
| OTel Collector | 8889 | Prometheus metrics export |
| Prometheus     | 9090 | Prometheus UI & API       |
| Loki           | 3100 | Loki API                  |
| Grafana        | 3000 | Grafana UI                |

## 시작하기

### 1. 스택 시작

```bash
cd otel
docker-compose up -d
```

### 2. 상태 확인

```bash
docker-compose ps
```

### 3. Grafana 접속

- URL: http://localhost:3000
- Username: admin
- Password: admin

### 4. Claude Code 설정

`~/.claude/settings.json`에 다음 환경변수 설정:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
    "OTEL_METRIC_EXPORT_INTERVAL": "10000"
  }
}
```

## 스택 관리

### 로그 확인

```bash
docker-compose logs -f otel-collector
```

### 스택 중지

```bash
docker-compose down
```

### 데이터 삭제 후 재시작

```bash
docker-compose down -v
rm -rf data/*
docker-compose up -d
```

## API 엔드포인트

### Prometheus Query API

```bash
# 모든 메트릭 조회
curl 'http://localhost:9090/api/v1/query?query={__name__=~"claude.*"}'

# 특정 메트릭 조회
curl 'http://localhost:9090/api/v1/query?query=claude_code_input_tokens_total'

# 범위 쿼리
curl 'http://localhost:9090/api/v1/query_range?query=claude_code_input_tokens_total&start=2024-01-01T00:00:00Z&end=2024-01-02T00:00:00Z&step=1h'
```

### Loki Query API

```bash
# 최근 로그 조회
curl 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="claude-code"}' \
  --data-urlencode 'start=1704067200000000000' \
  --data-urlencode 'end=1704153600000000000' \
  --data-urlencode 'limit=100'
```
