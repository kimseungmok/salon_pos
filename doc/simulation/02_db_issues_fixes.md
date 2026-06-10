# 시뮬레이션 결과 — DB 이슈 및 수정 사항

> 시뮬레이션 01_workflow_simulation.md 실행 후 발견된 문제 및 수정

---

## 발견된 이슈 & 해결

### Issue-01: sale_items.ref_id → 다중 테이블 참조 문제
**문제**: `sale_items.ref_id`는 menus, products, membership_plans, gift_cards를 가리키지만
SQLite 외래 키는 단일 테이블만 가능 → 타입별로 테이블이 다름

**해결**: `item_type` 컬럼으로 구분 (application-level join). 스냅샷(name, price) 필수 저장
```sql
-- item_type 별 join 방법
-- item_type='menu'    → JOIN menus ON ref_id
-- item_type='product' → JOIN products ON ref_id
-- item_type='membership' → JOIN membership_plans ON ref_id
-- item_type='gift_card'  → JOIN gift_cards ON ref_id
```
✅ 이미 설계에 반영됨. 애플리케이션 레이어에서 처리

---

### Issue-02: treatment_records.sale_id 외래 키 누락
**문제**: 03_customer.sql에서 `treatment_records.sale_id`에 `REFERENCES sales(id)` 미설정

**수정**:
```sql
-- 03_customer.sql 수정
sale_id TEXT REFERENCES sales(id) ON DELETE SET NULL,
```
→ 03_customer.sql 업데이트 필요

---

### Issue-03: 포인트 계산 — 포인트 사용분의 세금 처리
**문제**: ¥300 포인트 사용 시 세별도 환산(273엔)과 세액(27엔)이 분리 필요
실제 결제 금액 = ¥14,000 - ¥300 = ¥13,700 (세포함 기준으로 단순 차감)

**결론**: 일본 세무상 포인트 할인은 "판매가 절감"으로 처리 (세포함 금액에서 직접 차감)
→ taxable_amount 계산 시 포인트 할인을 포함한 합계에서 역산
```
세포함 최종 = ¥13,700
세별도 = 13700 / 1.10 = ¥12,455
소비세 = ¥1,245
```
→ sales 테이블 컬럼 명확히 정의됨 ✅

---

### Issue-04: 일별 집계 자동 갱신 전략
**문제**: `daily_summaries`를 언제 어떻게 갱신할 것인가?

**해결**: "지연 집계" 전략 채택
1. 판매/환불 발생 시 즉시 `daily_summaries` 갱신 (트랜잭션 내)
2. 마감 시 최종 확정 집계로 덮어쓰기
3. 앱 시작 시 오늘 날짜 `daily_summaries` 없으면 자동 생성

---

### Issue-05: 다기기 동기화 시 sale_no 중복
**문제**: iPad A와 iPad B가 오프라인 상태에서 같은 날 같은 일련번호 생성 가능

**해결**: `sale_no` 생성 규칙에 디바이스 ID 포함
```
S{날짜}-{디바이스코드}-{일련번호}
예: S20250113-A-0001 / S20250113-B-0001
```
→ `devices` 테이블의 `device_name` 코드를 prefix로 사용

---

### Issue-06: 시프트 vs 출퇴근 불일치
**문제**: `shifts`(예정)와 `attendance`(실제)가 분리되어 있으나 조인 키가 없음

**해결**: `attendance.work_date` = `shifts.shift_date` + `attendance.staff_id` = `shifts.staff_id`로 조인
```sql
SELECT
    s.start_time as planned_start,
    a.clock_in as actual_start,
    (strftime('%s', a.clock_in) - strftime('%s', s.shift_date||' '||s.start_time)) / 60
    as late_minutes
FROM shifts s
LEFT JOIN attendance a ON a.staff_id = s.staff_id AND a.work_date = s.shift_date
WHERE s.shift_date = '2025-01-13';
```
→ 외래 키 없이 복합 조건 JOIN으로 해결 ✅

---

### Issue-07: 회원권 `remaining_sessions` 계산 필드
**문제**: `remaining_sessions`를 저장하면 중복 데이터 (= total - used로 계산 가능)

**해결**: `remaining_sessions` 컬럼 제거, 애플리케이션에서 계산
```dart
int get remainingSessions => totalSessions - usedSessions;
```
→ DB 정규화 개선. 단, 세션 카운트 정합성은 트랜잭션으로 보장

---

### Issue-08: 쿠폰 — 개인 발행 vs 공용 쿠폰 구분
**문제**: `coupons.issued_to` NULL=공용, customer_id=개인인데 공용 쿠폰 고객별 사용 횟수 추적 불가

**추가 테이블**:
```sql
-- 공용 쿠폰의 고객별 사용 이력
CREATE TABLE IF NOT EXISTS coupon_usage (
    id          TEXT PRIMARY KEY,
    coupon_id   TEXT NOT NULL REFERENCES coupons(id),
    customer_id TEXT NOT NULL REFERENCES customers(id),
    sale_id     TEXT REFERENCES sales(id),
    used_at     TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    UNIQUE(coupon_id, customer_id)  -- 고객당 1회 제한 시
);
```
→ 08_marketing_sync.sql에 추가 필요

---

### Issue-09: 급여 계산 — 커미션 단계별 적용
**문제**: `staff_commission_tiers` 테이블이 있는데 실제 계산 로직이 복잡

**시뮬레이션**:
```sql
-- 예: 박미나 이번달 담당 매출 ¥1,620,000
-- 구간: 0~500K = 20%, 500K~1M = 24%, 1M~ = 28%

WITH tier_calc AS (
    SELECT
        MIN(amount_in_tier, bracket_size) as amount,
        rate
    FROM (
        VALUES
        (MIN(1620000, 500000),           0.20),  -- 0~500K: ¥500,000 × 20%
        (MIN(MAX(1620000-500000,0), 500000), 0.24),  -- 500K~1M: ¥500,000 × 24%
        (MAX(1620000-1000000, 0),        0.28)    -- 1M~: ¥620,000 × 28%
    ) as t(amount, rate)
)
SELECT SUM(amount * rate) as total_commission FROM tier_calc;
-- = 100000 + 120000 + 173600 = ¥393,600
```
→ 앱 코드에서 계산 후 `payroll.commission_pay`에 저장

---

## DB 최종 관계도 (ERD 요약)

```
salon_settings (1)
    │
    ├── staff (N)
    │   ├── staff_menu_commissions (N) → menus
    │   ├── staff_commission_tiers (N)
    │   ├── shifts (N)
    │   ├── attendance (N)
    │   └── payroll (N) → payroll_periods
    │
    ├── customers (N)
    │   ├── customer_tag_links (N) → customer_tags
    │   ├── treatment_records (N) → sales, staff
    │   ├── customer_memberships (N) → membership_plans
    │   ├── membership_usage (N) → sales
    │   ├── point_history (N) → sales
    │   └── gift_cards (N)
    │
    ├── menu_categories (N)
    │   └── menus (N)
    │       ├── menu_staff_prices (N) → staff
    │       ├── menu_option_groups (N)
    │       │   └── menu_options (N)
    │       └── resource_menu_links (N) → resources
    │
    ├── appointments (N) → customers, staff, resources
    │   └── appointment_menus (N) → menus, staff
    │
    ├── register_sessions (N) → staff
    │   └── cash_movements (N) → staff
    │
    └── sales (N) → register_sessions, appointments, customers, staff
        ├── sale_items (N) → staff
        ├── sale_discounts (N) → discounts, coupons
        ├── sale_payments (N) → gift_cards
        └── refunds (N) → staff
            ├── refund_items (N) → sale_items
            └── refund_payments (N)

product_categories
└── products (N) → suppliers, product_categories
    └── inventory_movements (N)

purchase_orders (N) → suppliers
└── purchase_order_items (N) → products

expense_categories
└── expenses (N) → staff

daily_summaries (캐시)
monthly_summaries (캐시)
yearly_summaries (캐시)
kpi_targets → staff

campaigns → message_templates
└── message_logs → customers

sync_queue
draft_sales
draft_appointments
```

---

## 추가 필요 인덱스 (성능 최적화)

```sql
-- 자주 쓰는 쿼리 기반 추가 인덱스
CREATE INDEX IF NOT EXISTS idx_sales_date_staff ON sales(date(created_at), staff_id);
CREATE INDEX IF NOT EXISTS idx_apt_date_staff   ON appointments(date(start_at), staff_id);
CREATE INDEX IF NOT EXISTS idx_apt_date_status  ON appointments(date(start_at), status);
CREATE INDEX IF NOT EXISTS idx_treatment_staff  ON treatment_records(staff_id);
CREATE INDEX IF NOT EXISTS idx_inv_mov_date     ON inventory_movements(date(created_at));
CREATE INDEX IF NOT EXISTS idx_expense_cat_date ON expenses(category_id, expense_date);
CREATE INDEX IF NOT EXISTS idx_point_created    ON point_history(created_at);
```
