# 기능별 워크플로 시뮬레이션

> 각 시나리오를 SQL로 추적하여 DB 설계 검증

---

## 시뮬레이션 1: 하루 영업 전체 플로우

### 1-A. 개점 처리

**화면**: 개점 버튼 탭 → 시재 입력 → 개점 확인

```sql
-- 1) 레지스터 세션 개점
INSERT INTO register_sessions (id, session_no, opened_by, opening_cash, status)
VALUES ('sess_001', 'RS20250113-001', 'staff_mina', 50000, 'open');

-- 2) 개점 시재 기록
INSERT INTO cash_movements (id, session_id, staff_id, movement_type, amount, reason)
VALUES ('cm_001', 'sess_001', 'staff_mina', 'opening', 50000, '개점 시재');
```
✅ 검증: register_sessions + cash_movements 연동 정상

---

### 1-B. 고객 예약 → 체크인 → POS 결제 전체 흐름

**시나리오**: 김지수 고객, 박미나 스태프, 컷트+컬러 예약 → 완료 → 결제

```sql
-- Step 1: 예약 확인 (기존 예약)
SELECT a.*, c.name, c.phone, c.point_balance,
       am.menu_name, am.price
FROM appointments a
JOIN customers c ON a.customer_id = c.id
JOIN appointment_menus am ON am.appointment_id = a.id
WHERE a.id = 'apt_001' AND a.status = 'confirmed';
-- → 김지수, 14:00~16:30, 컷트¥5000 + 컬러¥9000 = ¥14,000

-- Step 2: 체크인 (시작 처리)
UPDATE appointments
SET status = 'in_progress', actual_start_at = datetime('now','localtime')
WHERE id = 'apt_001';

-- Step 3: POS 화면 — 예약에서 판매 시작 (주문서 자동 로드)
-- appointment_menus → sale_items 변환
-- 고객 포인트 조회
SELECT point_balance FROM customers WHERE id = 'cust_jisu'; -- → 320P

-- Step 4: 포인트 300P 사용 + 카드 결제
-- 합계: ¥14,000 - ¥300(포인트) = ¥13,700 카드 결제

INSERT INTO sales (
    id, sale_no, session_id, appointment_id, customer_id,
    staff_id, cashier_id,
    subtotal, discount_amount, taxable_amount,
    tax_rate_10_base, tax_rate_10_tax, tax_amount,
    total_amount, points_used, points_earned, status
) VALUES (
    'sale_001', 'S20250113-0001', 'sess_001', 'apt_001', 'cust_jisu',
    'staff_mina', 'staff_mina',
    12728,       -- 세별도 소계 (14000 / 1.1)
    273,         -- 포인트 할인 세별도 (300 / 1.1)
    12455,       -- 과세 대상액
    12455, 1246, 1246,  -- 10% 세율
    13700,       -- 세포함 최종
    300,         -- 포인트 사용
    137,         -- 적립 (13700 * 0.01)
    'completed'
);

-- Step 5: 판매 항목
INSERT INTO sale_items (id, sale_id, item_type, ref_id, name, quantity,
    unit_price, tax_rate, tax_amount, total_price, staff_id)
VALUES
('si_001', 'sale_001', 'menu', 'menu_cut',   'カット(ミディアム)', 1, 4545, 0.10, 455, 5000, 'staff_mina'),
('si_002', 'sale_001', 'menu', 'menu_color', 'カラー フル',        1, 8182, 0.10, 818, 9000, 'staff_mina');

-- Step 6: 포인트 사용 결제 + 카드 결제
INSERT INTO sale_payments (id, sale_id, method, amount)
VALUES
('sp_001', 'sale_001', 'point',       300),
('sp_002', 'sale_001', 'credit_card', 13700);

-- Step 7: 포인트 차감 + 적립
UPDATE customers SET point_balance = point_balance - 300 + 137
WHERE id = 'cust_jisu';
-- 320 - 300 + 137 = 157P

INSERT INTO point_history (id, customer_id, sale_id, change_amount, balance_after, reason)
VALUES ('ph_001', 'cust_jisu', 'sale_001', -300, 20,  '포인트 사용');
INSERT INTO point_history (id, customer_id, sale_id, change_amount, balance_after, reason)
VALUES ('ph_002', 'cust_jisu', 'sale_001', +137, 157, '구매 적립');

-- Step 8: 예약 완료 처리
UPDATE appointments
SET status = 'completed', actual_end_at = datetime('now','localtime')
WHERE id = 'apt_001';

-- Step 9: 고객 통계 업데이트
UPDATE customers SET
    last_visit_date = date('now','localtime'),
    total_visits = total_visits + 1,
    total_spent = total_spent + 13700
WHERE id = 'cust_jisu';
```
✅ 검증: sale → sale_items → sale_payments → point_history → customers 모두 연동

---

### 1-C. 카르테 작성

```sql
INSERT INTO treatment_records (
    id, customer_id, sale_id, staff_id, visit_date,
    menu_summary, hair_length,
    color_brand, color_formula, color_level, color_tone,
    next_visit_recommendation, photo_before_path, photo_after_path
) VALUES (
    'tr_001', 'cust_jisu', 'sale_001', 'staff_mina', '2025-01-13',
    'カット(ミディアム) + カラー フル',
    'medium',
    'Milbon', 'OXI 6% + アッシュグレー 1:1 + クリア 0.5', '9', '애쉬',
    '2개월 후 리터치',
    '/photos/jisu_before_20250113.jpg',
    '/photos/jisu_after_20250113.jpg'
);
```
✅ 검증: treatment_records.sale_id → sales 연동

---

### 1-D. 마감 처리

```sql
-- 1) 오늘 매출 집계
SELECT
    SUM(total_amount) as total_sales,
    COUNT(*) as total_count,
    SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed_count
FROM sales
WHERE session_id = 'sess_001' AND status = 'completed';

-- 2) 결제 수단별 집계
SELECT method, SUM(amount) as total
FROM sale_payments sp
JOIN sales s ON sp.sale_id = s.id
WHERE s.session_id = 'sess_001'
GROUP BY method;

-- 3) 현금 마감 계산
-- 이론 현금 = 개점시재 + 현금매출 - 현금지출
SELECT
    50000 + IFNULL(cash_in, 0) - IFNULL(cash_out, 0) as expected_cash
FROM (
    SELECT
        SUM(CASE WHEN movement_type IN ('opening','cash_in') THEN amount ELSE 0 END) as cash_in,
        SUM(CASE WHEN movement_type = 'cash_out' THEN ABS(amount) ELSE 0 END) as cash_out
    FROM cash_movements WHERE session_id = 'sess_001'
);

-- 4) 마감 확정
UPDATE register_sessions SET
    close_at = datetime('now','localtime'),
    closed_by = 'staff_mina',
    total_sales_amount = 156000,
    total_sales_count = 18,
    cash_sales = 48000,
    card_sales = 102000,
    qr_sales = 6000,
    expected_cash = 98000,
    actual_cash = 98000,
    cash_difference = 0,
    status = 'closed'
WHERE id = 'sess_001';

-- 5) 일별 집계 테이블 업데이트
INSERT OR REPLACE INTO daily_summaries (
    id, summary_date, total_sales, total_transactions,
    cash_amount, card_amount, qr_amount
) VALUES (
    'ds_20250113', '2025-01-13', 156000, 18,
    48000, 102000, 6000
);
```
✅ 검증: register_sessions.close → daily_summaries 캐시 갱신

---

## 시뮬레이션 2: 환불 처리

**시나리오**: 전날 판매한 트리트먼트 ¥3,000 환불

```sql
-- 1) 원 판매 조회
SELECT si.id, si.name, si.total_price, si.quantity
FROM sale_items si
JOIN sales s ON si.sale_id = s.id
WHERE s.id = 'sale_001' AND si.item_type = 'menu';

-- 2) 환불 생성
INSERT INTO refunds (id, refund_no, original_sale_id, processed_by, refund_reason, total_refund)
VALUES ('ref_001', 'RF20250114-0001', 'sale_001', 'staff_mina', '고객 불만 — 효과 없음', 3000);

-- 3) 환불 항목
INSERT INTO refund_items (id, refund_id, sale_item_id, quantity, refund_amount)
VALUES ('ri_001', 'ref_001', 'si_treatment', 1, 3000);

-- 4) 원 판매 상태 변경
UPDATE sales SET status = 'partially_refunded' WHERE id = 'sale_001';

-- 5) 환불 결제
INSERT INTO refund_payments (id, refund_id, method, amount)
VALUES ('rp_001', 'ref_001', 'credit_card', 3000);

-- 6) 포인트 취소 (구매 적립분 회수)
-- 환불 금액 비율에 따른 포인트 회수: 3000/13700 * 137 = 약 30P
UPDATE customers SET point_balance = point_balance - 30 WHERE id = 'cust_jisu';
```
✅ 검증: refunds → refund_items → refund_payments 연동

---

## 시뮬레이션 3: 재고 — 판매 시 자동 차감

**시나리오**: トリートメント 판매 → 재고 자동 차감

```sql
-- 판매 항목 저장 시 재고 차감 트리거 (코드에서 처리)
-- sale_items.item_type = 'product' 인 경우

UPDATE products
SET stock_quantity = stock_quantity - 1,
    updated_at = datetime('now','localtime')
WHERE id = 'prod_treatment_bb';

-- 재고 이동 이력 기록
INSERT INTO inventory_movements (
    id, product_id, movement_type, quantity,
    stock_before, stock_after, reference_type, reference_id, staff_id
) VALUES (
    'im_001', 'prod_treatment_bb', 'sale_out', -1,
    12, 11, 'sale', 'sale_001', 'staff_mina'
);

-- 재고 경고 체크 (stock_quantity <= reorder_point)
SELECT id, name, stock_quantity, reorder_point
FROM products
WHERE stock_quantity <= reorder_point AND is_active = 1;
```
✅ 검증: sale → inventory_movements → products.stock_quantity

---

## 시뮬레이션 4: 회원권 구매 → 사용

```sql
-- 1) 회원권 플랜
INSERT INTO membership_plans (id, name, plan_type, price, session_count)
VALUES ('mp_10cut', '컷트 10회권', 'session', 40000, 10);
-- (정가 ¥5,000×10=50,000, 20% 할인)

-- 2) 고객이 회원권 구매 (POS에서 판매)
INSERT INTO customer_memberships (
    id, customer_id, plan_id, sale_id,
    start_date, total_sessions, used_sessions, status, price_paid
) VALUES (
    'cm_001', 'cust_jisu', 'mp_10cut', 'sale_002',
    '2025-01-13', 10, 0, 'active', 40000
);

-- 3) 다음 방문 시 회원권 사용
-- 컷트 시술 → 회원권 1회 차감
UPDATE customer_memberships
SET used_sessions = used_sessions + 1,
    remaining_sessions = total_sessions - (used_sessions + 1)
WHERE id = 'cm_001';

INSERT INTO membership_usage (id, membership_id, sale_id)
VALUES ('mu_001', 'cm_001', 'sale_003');

-- 결제 시 이 컷트는 ¥0 (회원권 적용)
INSERT INTO sale_items (id, sale_id, item_type, ref_id, name,
    unit_price, discount_amount, total_price)
VALUES ('si_cut', 'sale_003', 'menu', 'menu_cut', 'カット(会員券)',
    5000, 5000, 0);  -- discount_amount = 전액 할인

-- 회원권 사용 내역 → sale_discounts에도 기록
INSERT INTO sale_discounts (id, sale_id, name, discount_type, discount_amount)
VALUES ('sd_001', 'sale_003', '컷트10회권 사용', 'membership', 5000);
```
✅ 검증: membership_plans → customer_memberships → membership_usage 연동

---

## 시뮬레이션 5: 월 마감 / 손익 계산

```sql
-- 1) 월 매출 집계
SELECT
    SUM(total_amount) as gross_sales,
    SUM(total_amount - tax_amount) as net_sales_excl_tax,
    SUM(tax_amount) as total_tax,
    COUNT(*) as transaction_count
FROM sales
WHERE strftime('%Y-%m', created_at) = '2025-01'
AND status IN ('completed', 'partially_refunded');

-- 2) 환불 합계
SELECT SUM(total_refund) FROM refunds
WHERE strftime('%Y-%m', created_at) = '2025-01';

-- 3) 경비 집계
SELECT ec.name, SUM(e.total_amount) as total
FROM expenses e
JOIN expense_categories ec ON e.category_id = ec.id
WHERE strftime('%Y-%m', e.expense_date) = '2025-01'
GROUP BY ec.id;

-- 4) 급여 합계
SELECT SUM(gross_pay) FROM payroll
WHERE period_id = (SELECT id FROM payroll_periods WHERE period_year=2025 AND period_month=1);

-- 5) 재료비 (상품 원가 합계)
SELECT SUM(si.quantity * p.cost_price) as cogs
FROM sale_items si
JOIN products p ON si.ref_id = p.id
WHERE si.item_type = 'product'
AND si.sale_id IN (
    SELECT id FROM sales WHERE strftime('%Y-%m', created_at) = '2025-01'
    AND status = 'completed'
);

-- 6) 월별 집계 저장
INSERT OR REPLACE INTO monthly_summaries (
    id, year, month,
    total_sales, net_sales, total_refund, total_tax,
    total_expense, total_payroll, gross_profit, operating_income
) VALUES (
    'ms_202501', 2025, 1,
    3240000, 2945455, 15000, 294545,
    480000, 1200000,
    2945455 - 486000,     -- 매출총이익 (순매출 - 재료비)
    2459455 - 480000 - 1200000  -- 영업이익
);
```
✅ 검증: daily_summaries → monthly_summaries → yearly_summaries 3단계 집계

---

## 시뮬레이션 6: 오프라인 → 온라인 동기화

```sql
-- 1) 오프라인 판매 생성 (is_offline = 1)
INSERT INTO sales (..., is_offline, synced_at)
VALUES (..., 1, NULL);

-- 2) sync_queue에 추가
INSERT INTO sync_queue (entity_type, entity_id, operation, payload, priority)
VALUES ('sale', 'sale_001', 'create',
    json_object('id','sale_001','total_amount',13700,...),
    3);

-- 3) 네트워크 복구 시 처리
UPDATE sync_queue SET status = 'processing' WHERE id = 1;

-- API 요청 성공 후:
UPDATE sync_queue SET status = 'synced', processed_at = datetime('now') WHERE id = 1;
UPDATE sales SET synced_at = datetime('now') WHERE id = 'sale_001';

-- 4) 충돌 발생 시:
UPDATE sync_queue SET
    status = 'conflict',
    conflict_data = '{"server_version": {...}}'
WHERE id = 1;
-- UI에 충돌 해결 다이얼로그 표시
```
✅ 검증: sync_queue.status 흐름 → pending → processing → synced/conflict

---

## 시뮬레이션 7: Draft 복구 (중단 후 이어하기)

```sql
-- 1) 결제 화면 입력 중 앱 종료 → 입력값 자동 저장
INSERT OR REPLACE INTO draft_sales (id, data, saved_at)
VALUES ('current',
    json_object(
        'customer_id', 'cust_jisu',
        'staff_id', 'staff_mina',
        'items', json_array(
            json_object('menu_id','menu_cut','price',5000),
            json_object('menu_id','menu_color','price',9000)
        ),
        'step', 'payment_method_selection'
    ),
    datetime('now','localtime')
);

-- 2) 앱 재시작 시 Draft 감지
SELECT * FROM draft_sales WHERE id = 'current';
-- → 데이터 있으면 "이어서 하시겠습니까?" 다이얼로그

-- 3) 이어하기 → Draft 로드
-- 4) 완료 또는 취소 → Draft 삭제
DELETE FROM draft_sales WHERE id = 'current';
```
✅ 검증: draft_sales 단일 레코드 패턴 (id='current')
