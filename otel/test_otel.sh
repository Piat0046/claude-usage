#!/bin/bash
# OpenTelemetry Collector 테스트 스크립트
# 이 스크립트는 OTel Collector가 메트릭을 제대로 수집하는지 테스트합니다.

set -e

echo "=========================================="
echo "OpenTelemetry Collector 테스트"
echo "=========================================="

# 1. Docker 상태 확인
echo ""
echo "[1/5] Docker 상태 확인..."
if docker ps | grep -q claude-otel-collector; then
    echo "✅ OTel Collector 컨테이너 실행 중"
else
    echo "❌ OTel Collector 컨테이너가 실행되지 않음"
    echo "   실행: cd ~/.claude-usage && docker-compose up -d"
    exit 1
fi

# 2. 포트 확인
echo ""
echo "[2/5] 포트 확인..."
if nc -z localhost 4317 2>/dev/null; then
    echo "✅ gRPC 포트 (4317) 열림"
else
    echo "⚠️  gRPC 포트 (4317) 닫힘"
fi

if nc -z localhost 4318 2>/dev/null; then
    echo "✅ HTTP 포트 (4318) 열림"
else
    echo "⚠️  HTTP 포트 (4318) 닫힘"
fi

# 3. 테스트 메트릭 전송 (HTTP/JSON)
echo ""
echo "[3/5] 테스트 메트릭 전송..."
TIMESTAMP_NS=$(($(date +%s) * 1000000000))

# OTLP JSON 형식의 테스트 메트릭
TEST_METRIC=$(cat <<EOF
{
  "resourceMetrics": [{
    "resource": {
      "attributes": [{
        "key": "service.name",
        "value": {"stringValue": "claude-code-test"}
      }]
    },
    "scopeMetrics": [{
      "scope": {
        "name": "com.anthropic.claude_code.test"
      },
      "metrics": [{
        "name": "claude_code.cost.usage",
        "description": "Test cost metric",
        "sum": {
          "dataPoints": [{
            "asDouble": 0.0001,
            "timeUnixNano": "$TIMESTAMP_NS",
            "attributes": [{
              "key": "test",
              "value": {"stringValue": "true"}
            }]
          }],
          "aggregationTemporality": 2,
          "isMonotonic": true
        }
      }, {
        "name": "claude_code.token.usage",
        "description": "Test token metric",
        "sum": {
          "dataPoints": [{
            "asInt": "100",
            "timeUnixNano": "$TIMESTAMP_NS",
            "attributes": [{
              "key": "token_type",
              "value": {"stringValue": "input"}
            }]
          }],
          "aggregationTemporality": 2,
          "isMonotonic": true
        }
      }, {
        "name": "claude_code.session.count",
        "description": "Test session count",
        "sum": {
          "dataPoints": [{
            "asInt": "1",
            "timeUnixNano": "$TIMESTAMP_NS"
          }],
          "aggregationTemporality": 2,
          "isMonotonic": true
        }
      }]
    }]
  }]
}
EOF
)

# HTTP/Protobuf 대신 HTTP/JSON 사용
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:4318/v1/metrics \
  -H "Content-Type: application/json" \
  -d "$TEST_METRIC" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ 테스트 메트릭 전송 성공 (HTTP $HTTP_CODE)"
else
    echo "❌ 테스트 메트릭 전송 실패 (HTTP $HTTP_CODE)"
    echo "   응답: $BODY"
fi

# 4. 메트릭 파일 확인
echo ""
echo "[4/5] 메트릭 파일 확인..."
sleep 2  # 배치 처리 대기

METRICS_FILE="$HOME/.claude-usage/data/metrics.json"
if [ -f "$METRICS_FILE" ]; then
    FILE_SIZE=$(stat -f%z "$METRICS_FILE" 2>/dev/null || stat --printf="%s" "$METRICS_FILE" 2>/dev/null)
    LINE_COUNT=$(wc -l < "$METRICS_FILE" | tr -d ' ')
    echo "✅ 메트릭 파일 존재: $METRICS_FILE"
    echo "   파일 크기: ${FILE_SIZE} bytes"
    echo "   라인 수: $LINE_COUNT"

    # 마지막 몇 줄 출력
    if [ "$LINE_COUNT" -gt 0 ]; then
        echo ""
        echo "   마지막 메트릭 (최근 1줄):"
        tail -1 "$METRICS_FILE" | python3 -m json.tool 2>/dev/null | head -30 || tail -1 "$METRICS_FILE" | head -c 500
    fi
else
    echo "⚠️  메트릭 파일 없음: $METRICS_FILE"
    echo "   (Claude Code에서 텔레메트리 활성화 후 실행하면 생성됩니다)"
fi

# 5. Claude 설정 확인
echo ""
echo "[5/5] Claude 설정 확인..."
CLAUDE_CONFIG="$HOME/.claude/settings.json"
if [ -f "$CLAUDE_CONFIG" ]; then
    if grep -q "CLAUDE_CODE_ENABLE_TELEMETRY" "$CLAUDE_CONFIG"; then
        echo "✅ Claude 텔레메트리 설정 존재"
        echo "   설정 파일: $CLAUDE_CONFIG"
        echo ""
        echo "   env 설정:"
        python3 -c "import json; c=json.load(open('$CLAUDE_CONFIG')); print(json.dumps(c.get('env', {}), indent=2))" 2>/dev/null || \
        grep -A 10 '"env"' "$CLAUDE_CONFIG"
    else
        echo "⚠️  Claude 텔레메트리 설정 없음"
        echo "   앱의 Settings > Setup 탭에서 텔레메트리를 활성화하세요"
    fi
else
    echo "⚠️  Claude 설정 파일 없음: $CLAUDE_CONFIG"
fi

echo ""
echo "=========================================="
echo "테스트 완료"
echo "=========================================="
echo ""
echo "다음 단계:"
echo "1. Claude Code 재시작 (텔레메트리 설정 적용)"
echo "2. Claude Code 사용 (메트릭 생성)"
echo "3. 앱에서 메트릭 확인"
