# CHANGELOG

살롱 POS — 버전 이력

버전 형식: MAJOR.MINOR.PATCH

---

## [Unreleased] — 개발 중

### 목표
- Phase 1: 예약 + 고객 + 기본 POS

---

## [0.0.1] — 2025-01-13

### Added
- 프로젝트 초기 구조 셋업
- 벤치마킹 리서치 문서 (SalonBoard, Fresha, TossPlace, 기타)
- DB 스키마 v0.1.0 (SQLite)
- UI/UX 가이드 (토스플레이스 기반)
- 기능 명세서 v0.1.0
- 일본 현지화 명세

### Architecture Decision
- Framework: Flutter 3.x
- DB: SQLite (sqflite + drift)
- State: Riverpod
- Offline-first 전략 채택
- Draft 자동 저장으로 작업 복구 지원

---

<!-- 버전 기록 양식
## [X.Y.Z] — YYYY-MM-DD

### Added
- 새로 추가된 기능

### Changed  
- 기존 기능 변경 (개선)

### Fixed
- 버그 수정

### Removed
- 제거된 기능

### Good (이 버전의 강점)
- 이 버전에서 잘 된 것들

### Improve (다음 버전에서 개선할 것)
- 아쉬운 점, 다음에 고칠 것들
-->
