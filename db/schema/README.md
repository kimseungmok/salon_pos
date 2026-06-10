# DB 스키마 실행 순서

```
00_init.sql          — PRAGMA 설정
01_master.sql        — 매장 설정, 버전, 감사로그
02_staff.sql         — 스태프, 시프트, 출퇴근, 급여
03_customer.sql      — 고객, 카르테, 회원권, 포인트, 기프트카드
04_menu_booking.sql  — 메뉴, 리소스, 예약, 대기명단
05_pos_sales.sql     — 개점/마감, 할인, 쿠폰, 판매, 결제, 환불
06_inventory.sql     — 상품, 재고이동, 발주, 공급업체, 실사
07_finance.sql       — 경비, 일/월/연 집계, 세무, KPI목표
08_marketing_sync.sql — 메시지템플릿, 캠페인, 자동화, 동기화큐
09_fixes_and_indexes.sql — 패치, 추가인덱스, VIEW 정의
```

## 테이블 수
총 **49개** 테이블 + **6개** VIEW

## 핵심 관계
- `sales` ← 모든 매출의 중심 (appointments, customers, staff, register_sessions 참조)
- `customers` ← CRM의 중심 (모든 방문·결제·포인트·카르테 연결)
- `appointments` ← 예약의 중심 (고객·스태프·메뉴·리소스 연결)
- `daily_summaries` / `monthly_summaries` ← 빠른 리포트용 캐시
