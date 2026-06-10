# 시스템 아키텍처 설계

---

## 기술 스택

### 프레임워크
- **Flutter 3.x** (Dart)
  - iOS (iPad Air 2세대 = iOS 12+ 지원 ✅)
  - macOS (웹 대신 macOS 앱으로도 배포 가능)
  - Flutter Web (향후 PC 브라우저 지원)

### 상태 관리
- **Riverpod** (Provider의 개선판, 코드 생성 없이 사용)
  - 완전 무료, 오픈소스

### 로컬 데이터베이스
- **SQLite** via `sqflite` (Flutter 공식 지원, 무료)
- **drift** (타입세이프 SQLite ORM, 무료 오픈소스)
  - 마이그레이션 자동 관리
  - 쿼리 컴파일 타임 검증

### 오프라인 동기화
- `connectivity_plus` — 네트워크 상태 감지
- 커스텀 SyncQueue — SQLite 기반 오프라인 작업 큐

### 일본어 현지화
- `flutter_localizations` (Flutter 공식)
- `intl` (날짜·숫자 포맷)
- Noto Sans JP (구글 폰트, 무료)

### 유틸리티 (전부 무료 오픈소스)
- `uuid` — ID 생성
- `path_provider` — 파일 경로
- `shared_preferences` — 간단한 설정값 저장
- `go_router` — 라우팅
- `freezed` — 불변 데이터 모델
- `printing` — 영수증 프린터 출력

---

## 레이어 아키텍처

```
┌─────────────────────────────────────────┐
│              Presentation Layer          │
│  (Flutter Widgets, Screens, Components) │
├─────────────────────────────────────────┤
│              ViewModel Layer             │
│        (Riverpod Notifiers/Providers)   │
├─────────────────────────────────────────┤
│              Domain Layer               │
│      (Use Cases, Business Logic)        │
├─────────────────────────────────────────┤
│            Repository Layer             │
│  (Abstract interfaces + Implementations)│
├──────────────────┬──────────────────────┤
│   Local DB Layer │  Sync/Network Layer  │
│   (drift/SQLite) │  (HTTP + SyncQueue)  │
└──────────────────┴──────────────────────┘
```

---

## 오프라인/온라인 전략

### 오프라인 우선 (Offline-First)
```
모든 쓰기 작업:
  1. SQLite에 즉시 저장 (로컬 커밋)
  2. sync_queue 테이블에 작업 추가 (pending 상태)
  3. UI에 즉시 반영 (낙관적 업데이트)

네트워크 연결 시:
  1. sync_queue에서 pending 항목 순차 처리
  2. 서버 응답 성공 → 상태를 synced로 변경
  3. 충돌 시 → conflict 상태로 표시, 수동 해결 UI 제공

네트워크 끊김 시:
  1. 모든 기능 정상 동작 (로컬 SQLite 기반)
  2. 상태바에 오프라인 뱃지 표시
  3. 재연결 시 자동 동기화 시작
```

### 작업 중단 후 이어하기
```
모든 폼/입력 상태:
  1. 입력 시마다 draft_* 테이블에 자동 저장 (debounce 500ms)
  2. 앱 재시작 → draft 감지 → "이어서 하시겠습니까?" 다이얼로그
  3. 예약·결제·고객 등록 모두 동일 적용
  4. 완료 또는 명시적 취소 시 draft 삭제
```

---

## 폴더 구조 (Flutter 프로젝트)

```
lib/
├── main.dart
├── app/
│   ├── app.dart                # MaterialApp 설정
│   ├── router.dart             # go_router 라우팅
│   └── theme.dart              # 토스 스타일 테마
├── core/
│   ├── database/
│   │   ├── app_database.dart   # drift DB 정의
│   │   └── migrations/
│   ├── sync/
│   │   ├── sync_queue.dart     # 오프라인 큐
│   │   └── sync_manager.dart   # 동기화 오케스트레이터
│   ├── error/
│   │   └── app_exception.dart
│   └── utils/
├── features/
│   ├── booking/                # 예약
│   ├── customer/               # 고객 관리
│   ├── pos/                    # POS 결제
│   ├── menu/                   # 메뉴 관리
│   ├── staff/                  # 스태프
│   ├── inventory/              # 재고
│   ├── reports/                # 리포트
│   └── settings/               # 설정
└── shared/
    ├── widgets/                # 공통 위젯
    ├── models/                 # 공통 모델
    └── providers/              # 공통 Provider
```

---

## 버전 관리 전략

```
버전 형식: MAJOR.MINOR.PATCH
예) v0.1.0, v0.2.0 ... v1.0.0

CHANGELOG.md: 각 버전의 추가·수정·제거 기록
app_versions 테이블: 런타임에서 버전 이력 조회 가능

버전 업 기준:
  PATCH: 버그 수정
  MINOR: 새 기능 추가
  MAJOR: 대규모 리팩토링 / 호환성 변경
```
