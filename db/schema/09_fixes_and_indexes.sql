-- ============================================================
-- 09. FIXES & INDEXES — 시뮬레이션 후 수정/보완/인덱스
-- ============================================================

-- Issue-02 수정: treatment_records.sale_id 외래키 (SQLite에선 ALTER TABLE 제한으로 재생성)
-- → 03_customer.sql 에 이미 반영됨. 이 파일에서는 누락된 부분만 패치

-- Issue-08 추가: 쿠폰 사용 이력 (공용 쿠폰 고객별 추적)
CREATE TABLE IF NOT EXISTS coupon_usage (
    id          TEXT PRIMARY KEY,
    coupon_id   TEXT NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
    customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    sale_id     TEXT REFERENCES sales(id) ON DELETE SET NULL,
    used_at     TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_coupon_usage_customer ON coupon_usage(customer_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usage_coupon   ON coupon_usage(coupon_id);

-- ============================================================
-- 성능 최적화 인덱스 (시뮬레이션 후 추가)
-- ============================================================

-- 판매 조회 (날짜+스태프, 가장 빈번한 쿼리)
CREATE INDEX IF NOT EXISTS idx_sales_date_staff   ON sales(date(created_at), staff_id);

-- 예약 조회 (날짜+스태프, 캘린더 로딩)
CREATE INDEX IF NOT EXISTS idx_apt_date_staff     ON appointments(date(start_at), staff_id);
CREATE INDEX IF NOT EXISTS idx_apt_date_status    ON appointments(date(start_at), status);

-- 카르테 스태프별 조회
CREATE INDEX IF NOT EXISTS idx_treatment_staff    ON treatment_records(staff_id);

-- 재고 이동 날짜별
CREATE INDEX IF NOT EXISTS idx_inv_mov_date       ON inventory_movements(date(created_at));

-- 경비 카테고리+날짜
CREATE INDEX IF NOT EXISTS idx_expense_cat_date   ON expenses(category_id, expense_date);

-- 포인트 이력 날짜
CREATE INDEX IF NOT EXISTS idx_point_created      ON point_history(created_at);

-- 메시지 로그 날짜
CREATE INDEX IF NOT EXISTS idx_msg_sent_at        ON message_logs(sent_at);

-- 회원권 만료일
CREATE INDEX IF NOT EXISTS idx_membership_expiry  ON customer_memberships(end_date, status);

-- 발주서 상태+날짜
CREATE INDEX IF NOT EXISTS idx_po_date            ON purchase_orders(order_date);

-- 시재 세션별
CREATE INDEX IF NOT EXISTS idx_cash_mov_session   ON cash_movements(session_id);

-- ============================================================
-- VIEW — 자주 쓰는 복합 쿼리를 뷰로 정의
-- ============================================================

-- 오늘의 예약 목록 뷰
CREATE VIEW IF NOT EXISTS v_today_appointments AS
SELECT
    a.id,
    a.start_at,
    a.end_at,
    a.status,
    a.color,
    c.name AS customer_name,
    c.name_kana AS customer_kana,
    c.phone AS customer_phone,
    c.total_visits,
    st.name AS staff_name,
    st.color AS staff_color,
    GROUP_CONCAT(am.menu_name, ' + ') AS menu_summary,
    SUM(am.price) AS estimated_price
FROM appointments a
LEFT JOIN customers c ON a.customer_id = c.id
LEFT JOIN staff st ON a.staff_id = st.id
LEFT JOIN appointment_menus am ON am.appointment_id = a.id
WHERE date(a.start_at) = date('now', 'localtime')
GROUP BY a.id
ORDER BY a.start_at;

-- 고객 요약 뷰 (목록 표시용)
CREATE VIEW IF NOT EXISTS v_customer_summary AS
SELECT
    c.id,
    c.customer_no,
    c.name,
    c.name_kana,
    c.phone,
    c.gender,
    c.birth_date,
    c.total_visits,
    c.total_spent,
    c.last_visit_date,
    c.point_balance,
    c.is_vip,
    c.caution_flag,
    st.name AS assigned_staff_name,
    st.color AS assigned_staff_color,
    -- 태그 목록
    GROUP_CONCAT(ct.name, ',') AS tag_names,
    -- 다음 예약
    (SELECT start_at FROM appointments
     WHERE customer_id = c.id AND status IN ('pending','confirmed')
     AND start_at > datetime('now','localtime')
     ORDER BY start_at LIMIT 1) AS next_appointment_at
FROM customers c
LEFT JOIN staff st ON c.assigned_staff_id = st.id
LEFT JOIN customer_tag_links ctl ON ctl.customer_id = c.id
LEFT JOIN customer_tags ct ON ct.id = ctl.tag_id
WHERE c.is_deleted = 0
GROUP BY c.id;

-- 재고 경고 뷰
CREATE VIEW IF NOT EXISTS v_low_stock AS
SELECT
    p.id,
    p.name,
    p.name_jp,
    p.sku,
    p.barcode,
    p.stock_quantity,
    p.min_stock,
    p.reorder_point,
    p.reorder_qty,
    s.name AS supplier_name,
    pc.name AS category_name,
    CASE
        WHEN p.stock_quantity = 0 THEN 'out_of_stock'
        WHEN p.stock_quantity <= p.min_stock THEN 'critical'
        WHEN p.stock_quantity <= p.reorder_point THEN 'low'
        ELSE 'ok'
    END AS stock_status
FROM products p
LEFT JOIN suppliers s ON p.supplier_id = s.id
LEFT JOIN product_categories pc ON p.category_id = pc.id
WHERE p.is_active = 1 AND p.stock_quantity <= p.reorder_point
ORDER BY p.stock_quantity ASC;

-- 스태프별 월 실적 뷰
CREATE VIEW IF NOT EXISTS v_staff_monthly_performance AS
SELECT
    st.id AS staff_id,
    st.name AS staff_name,
    strftime('%Y-%m', s.created_at) AS month,
    COUNT(DISTINCT s.id) AS sale_count,
    SUM(s.total_amount) AS total_sales,
    COUNT(DISTINCT s.customer_id) AS customer_count,
    AVG(s.total_amount) AS avg_sale,
    SUM(CASE WHEN si.item_type = 'menu' THEN si.total_price ELSE 0 END) AS menu_sales,
    SUM(CASE WHEN si.item_type = 'product' THEN si.total_price ELSE 0 END) AS product_sales
FROM staff st
LEFT JOIN sales s ON s.staff_id = st.id AND s.status = 'completed'
LEFT JOIN sale_items si ON si.sale_id = s.id
WHERE st.is_active = 1
GROUP BY st.id, strftime('%Y-%m', s.created_at);

-- 이탈 고객 뷰 (90일 이상 미방문)
CREATE VIEW IF NOT EXISTS v_lost_customers AS
SELECT
    c.id,
    c.customer_no,
    c.name,
    c.name_kana,
    c.phone,
    c.last_visit_date,
    julianday('now') - julianday(c.last_visit_date) AS days_since_visit,
    c.total_visits,
    c.total_spent,
    st.name AS assigned_staff_name
FROM customers c
LEFT JOIN staff st ON c.assigned_staff_id = st.id
WHERE c.is_deleted = 0
AND c.last_visit_date IS NOT NULL
AND julianday('now') - julianday(c.last_visit_date) >= 90
ORDER BY days_since_visit DESC;

-- 오늘 레지스터 세션 요약
CREATE VIEW IF NOT EXISTS v_today_session_summary AS
SELECT
    rs.id AS session_id,
    rs.session_no,
    rs.open_at,
    rs.opening_cash,
    rs.status,
    st.name AS opened_by_name,
    COUNT(DISTINCT s.id) AS sale_count,
    COALESCE(SUM(s.total_amount), 0) AS total_sales,
    COALESCE(SUM(CASE WHEN sp.method = 'cash' THEN sp.amount ELSE 0 END), 0) AS cash_total,
    COALESCE(SUM(CASE WHEN sp.method IN ('credit_card','debit_card') THEN sp.amount ELSE 0 END), 0) AS card_total
FROM register_sessions rs
LEFT JOIN staff st ON rs.opened_by = st.id
LEFT JOIN sales s ON s.session_id = rs.id AND s.status = 'completed'
LEFT JOIN sale_payments sp ON sp.sale_id = s.id
WHERE date(rs.open_at) = date('now', 'localtime')
GROUP BY rs.id;
