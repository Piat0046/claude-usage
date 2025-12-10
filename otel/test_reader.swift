#!/usr/bin/env swift

import Foundation

// MARK: - OTel Metric Models (from MetricsFileReader.swift)
struct OTelMetricRecord: Codable {
    let resourceMetrics: [ResourceMetric]?
}

struct ResourceMetric: Codable {
    let resource: Resource?
    let scopeMetrics: [ScopeMetric]?
}

struct Resource: Codable {
    let attributes: [Attribute]?
}

struct Attribute: Codable {
    let key: String
    let value: AttributeValue
}

struct AttributeValue: Codable {
    let stringValue: String?
    let intValue: String?
    let doubleValue: Double?
}

struct ScopeMetric: Codable {
    let scope: Scope?
    let metrics: [Metric]?
}

struct Scope: Codable {
    let name: String?
    let version: String?
}

struct Metric: Codable {
    let name: String
    let description: String?
    let unit: String?
    let sum: MetricSum?
    let gauge: MetricGauge?
}

struct MetricSum: Codable {
    let dataPoints: [DataPoint]?
    let aggregationTemporality: Int?
    let isMonotonic: Bool?
}

struct MetricGauge: Codable {
    let dataPoints: [DataPoint]?
}

struct DataPoint: Codable {
    let attributes: [Attribute]?
    let startTimeUnixNano: String?
    let timeUnixNano: String?
    let asInt: String?
    let asDouble: Double?
}

// MARK: - Test

print("==========================================")
print("MetricsFileReader 테스트")
print("==========================================")

let metricsPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude-usage/data/metrics.json")

print("\n[1] 파일 존재 확인: \(metricsPath.path)")
guard FileManager.default.fileExists(atPath: metricsPath.path) else {
    print("❌ 파일 없음")
    exit(1)
}
print("✅ 파일 존재")

print("\n[2] JSON 파싱 테스트")
do {
    let data = try Data(contentsOf: metricsPath)
    let record = try JSONDecoder().decode(OTelMetricRecord.self, from: data)
    print("✅ JSON 파싱 성공")

    print("\n[3] 메트릭 처리")
    var totalCost = 0.0
    var inputTokens = 0
    var sessionCount = 0

    guard let resourceMetrics = record.resourceMetrics else {
        print("❌ resourceMetrics 없음")
        exit(1)
    }

    for resourceMetric in resourceMetrics {
        guard let scopeMetrics = resourceMetric.scopeMetrics else { continue }

        for scopeMetric in scopeMetrics {
            guard let metrics = scopeMetric.metrics else { continue }

            for metric in metrics {
                print("   - 메트릭: \(metric.name)")

                let dataPoints = metric.sum?.dataPoints ?? metric.gauge?.dataPoints ?? []

                for dataPoint in dataPoints {
                    let value = dataPoint.asDouble ?? (dataPoint.asInt.flatMap { Double($0) } ?? 0)

                    switch metric.name {
                    case "claude_code.cost.usage":
                        totalCost += value
                        print("     cost: \(value)")
                    case "claude_code.token.usage":
                        inputTokens += Int(value)
                        print("     tokens: \(Int(value))")
                    case "claude_code.session.count":
                        sessionCount += Int(value)
                        print("     sessions: \(Int(value))")
                    default:
                        break
                    }
                }
            }
        }
    }

    print("\n[4] 집계 결과")
    print("   Total Cost: $\(totalCost)")
    print("   Input Tokens: \(inputTokens)")
    print("   Sessions: \(sessionCount)")

    print("\n==========================================")
    print("✅ 테스트 통과!")
    print("==========================================")

} catch {
    print("❌ 에러: \(error)")
    exit(1)
}
