# Claude Usage Widget - 구현 계획

## 개요
SwiftUI + MenuBarExtra를 사용하여 Mac 메뉴 바에서 Claude API 사용량을 실시간으로 추적하는 앱

## 기술 스택
- **언어**: Swift 5.9+
- **프레임워크**: SwiftUI, MenuBarExtra
- **최소 지원**: macOS 13 Ventura+
- **API**: Anthropic Usage and Cost API

---

## Anthropic API 정보

### 엔드포인트
1. **사용량 조회**: `GET /v1/organizations/usage_report/messages`
   - 토큰 사용량 (input/output)
   - 모델별, 워크스페이스별 분류

2. **비용 조회**: `GET /v1/organizations/cost_report`
   - USD 기준 비용
   - 토큰, 웹 검색, 코드 실행 비용 포함

### 인증
- **Admin API Key** 필요 (`sk-ant-admin...`)
- 일반 API 키와 다름, Console에서 발급

### 제한사항
- 데이터 갱신: ~5분 지연
- Rate limit: 분당 1회 권장

---

## 구현 단계

### Phase 1: 프로젝트 설정
1. Xcode에서 macOS App 프로젝트 생성
2. SwiftUI App Lifecycle 선택
3. MenuBarExtra 기본 구조 설정

### Phase 2: 데이터 모델 및 API 클라이언트
1. Anthropic API 응답 모델 정의
   - `UsageReport`: 토큰 사용량
   - `CostReport`: 비용 정보
2. API 클라이언트 구현
   - URLSession 기반 네트워크 레이어
   - Admin API Key 인증 헤더
   - 에러 핸들링

### Phase 3: 핵심 기능 구현
1. 사용량 데이터 조회 및 파싱
2. 자동 갱신 (Timer, 5분 간격)
3. 데이터 캐싱 (UserDefaults)

### Phase 4: UI 구현
1. 메뉴 바 아이콘 (SF Symbol 사용)
2. 팝오버 뷰
   - 오늘 사용량 요약
   - 이번 달 사용량/비용
   - 모델별 breakdown
3. 설정 화면
   - Admin API Key 입력
   - 갱신 주기 설정
   - 알림 임계값 설정

### Phase 5: 추가 기능
1. 키체인에 API Key 안전 저장
2. 사용량 알림 (임계값 초과 시)
3. 로그인 시 자동 시작 옵션

---

## 프로젝트 구조

```
ClaudeUsageWidget/
├── ClaudeUsageWidgetApp.swift      # 앱 진입점, MenuBarExtra 정의
├── Models/
│   ├── UsageReport.swift           # 사용량 데이터 모델
│   └── CostReport.swift            # 비용 데이터 모델
├── Services/
│   ├── AnthropicAPIClient.swift    # API 클라이언트
│   └── KeychainService.swift       # 키체인 저장
├── ViewModels/
│   └── UsageViewModel.swift        # 뷰모델 (데이터 로직)
├── Views/
│   ├── MenuBarView.swift           # 메뉴 바 팝오버 메인 뷰
│   ├── UsageSummaryView.swift      # 사용량 요약 카드
│   ├── CostBreakdownView.swift     # 비용 상세 뷰
│   └── SettingsView.swift          # 설정 화면
└── Resources/
    └── Assets.xcassets             # 앱 아이콘
```

---

## UI 와이어프레임

### 메뉴 바 아이콘
- 기본: `chart.bar.fill` (SF Symbol)
- 상태 표시: 아이콘 옆에 간단한 비용 표시 (예: "$2.45")

### 팝오버 레이아웃
```
┌─────────────────────────────┐
│  Claude Usage         ⚙️    │
├─────────────────────────────┤
│  Today                      │
│  ┌───────────────────────┐  │
│  │ Input:  125.3K tokens │  │
│  │ Output:  45.2K tokens │  │
│  │ Cost:        $0.42    │  │
│  └───────────────────────┘  │
├─────────────────────────────┤
│  This Month                 │
│  ┌───────────────────────┐  │
│  │ Total: $12.45 / $50   │  │
│  │ ████████░░░░░  25%    │  │
│  └───────────────────────┘  │
├─────────────────────────────┤
│  Model Breakdown            │
│  • claude-3-opus: $8.20     │
│  • claude-3-sonnet: $4.25   │
├─────────────────────────────┤
│  Last updated: 2 min ago    │
│        [Refresh]  [Quit]    │
└─────────────────────────────┘
```

---

## 예상 작업량
- Phase 1: 프로젝트 설정
- Phase 2: API 클라이언트 구현
- Phase 3: 핵심 로직
- Phase 4: UI 구현
- Phase 5: 추가 기능 (선택)

---

## 필요 사항
- [ ] Xcode 15+ 설치
- [ ] Anthropic Admin API Key 발급
- [ ] Apple Developer 계정 (배포 시)
