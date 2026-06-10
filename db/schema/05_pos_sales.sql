-- ============================================================
-- 05. POS / SALES — 개점·마감 / 판매 / 결제 / 환불 / 할인
-- ============================================================

-- 레지스터 세션 (개점~마감 1사이클)
CREATE TABLE IF NOT EXISTS register_sessions (
    id                  TEXT PRIMARY KEY,
    session_no          TEXT NOT NULL UNIQUE,       -- RS20250113-001
    opened_by           TEXT NOT NULL REFERENCES staff(id),
    closed_by           TEXT REFERENCES staff(id),
    -- 개점
    open_at             TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    opening_cash        INTEGER NOT NULL DEFAULT 0, -- 개점 시재 (엔)
    -- 마감
    close_at            TEXT,
    -- 마감 집계 (매출)
    total_sales_amount  INTEGER NOT NULL DEFAULT 0,
    total_sales_count   INTEGER NOT NULL DEFAULT 0,
    total_refund_amount INTEGER NOT NULL DEFAULT 0,
    -- 마감 집계 (결제 수단별)
    cash_sales          INTEGER NOT NULL DEFAULT 0,
    card_sales          INTEGER NOT NULL DEFAULT 0,
    qr_sales            INTEGER NOT NULL DEFAULT 0,
    gift_card_sales     INTEGER NOT NULL DEFAULT 0,
    point_discount      INTEGER NOT NULL DEFAULT 0,
    other_sales         INTEGER NOT NULL DEFAULT 0,
    -- 현금 마감
    expected_cash       INTEGER NOT NULL DEFAULT 0, -- 이론상 현금 (개점시재+현금매출-현금지출)
    actual_cash         INTEGER,                    -- 실제 센 현금
    cash_difference     INTEGER,                    -- 차이 (오버/부족)
    -- 상태
    status              TEXT NOT NULL DEFAULT 'open',
                        -- 'open','closed'
    memo                TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_reg_session_open ON register_sessions(open_at);

-- 시재 입출금 (현금 서랍)
CREATE TABLE IF NOT EXISTS cash_movements (
    id                  TEXT PRIMARY KEY,
    session_id          TEXT NOT NULL REFERENCES register_sessions(id),
    staff_id            TEXT REFERENCES staff(id),
    movement_type       TEXT NOT NULL,
                        -- 'opening','closing','cash_in','cash_out','adjustment'
    amount              INTEGER NOT NULL,   -- 양수:입금 음수:출금
    reason              TEXT,
    memo                TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 할인 마스터
CREATE TABLE IF NOT EXISTS discounts (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    name_jp         TEXT,
    discount_type   TEXT NOT NULL,
                    -- 'amount'금액 / 'rate'비율 / 'free'무료
    discount_value  INTEGER NOT NULL,   -- 금액(엔) 또는 비율(0~100%)
    target          TEXT NOT NULL DEFAULT 'total',
                    -- 'total'합계 / 'item'항목별
    min_purchase    INTEGER DEFAULT 0,
    is_stackable    INTEGER NOT NULL DEFAULT 0,  -- 중복 적용 가능
    is_active       INTEGER NOT NULL DEFAULT 1,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 쿠폰
CREATE TABLE IF NOT EXISTS coupons (
    id              TEXT PRIMARY KEY,
    code            TEXT NOT NULL UNIQUE,
    name            TEXT NOT NULL,
    name_jp         TEXT,
    discount_type   TEXT NOT NULL,      -- 'amount','rate'
    discount_value  INTEGER NOT NULL,
    target_menus    TEXT,               -- JSON: 적용 메뉴 ID (NULL=전체)
    min_purchase    INTEGER DEFAULT 0,
    valid_from      TEXT,
    valid_until     TEXT,
    usage_limit     INTEGER,            -- NULL=무제한
    usage_limit_per_customer INTEGER DEFAULT 1,
    usage_count     INTEGER NOT NULL DEFAULT 0,
    issued_to       TEXT,               -- NULL=공용, customer_id=개인
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 판매 (Transaction)
CREATE TABLE IF NOT EXISTS sales (
    id              TEXT PRIMARY KEY,
    sale_no         TEXT NOT NULL UNIQUE,   -- S20250113-0001 (날짜+일련번호)
    session_id      TEXT REFERENCES register_sessions(id),
    appointment_id  TEXT REFERENCES appointments(id),
    customer_id     TEXT REFERENCES customers(id),
    staff_id        TEXT REFERENCES staff(id),      -- 메인 담당 스태프
    cashier_id      TEXT REFERENCES staff(id),      -- 계산 담당
    -- 금액 계산
    subtotal        INTEGER NOT NULL DEFAULT 0,     -- 소계 (세전)
    discount_amount INTEGER NOT NULL DEFAULT 0,     -- 할인 합계
    taxable_amount  INTEGER NOT NULL DEFAULT 0,     -- 과세 대상액
    tax_amount      INTEGER NOT NULL DEFAULT 0,     -- 소비세 합계
    tax_rate_10_base INTEGER NOT NULL DEFAULT 0,    -- 10%세율 과세분
    tax_rate_10_tax INTEGER NOT NULL DEFAULT 0,     -- 10%세율 세액
    tax_rate_8_base INTEGER NOT NULL DEFAULT 0,     -- 8%세율 과세분 (경감세율)
    tax_rate_8_tax  INTEGER NOT NULL DEFAULT 0,
    total_amount    INTEGER NOT NULL DEFAULT 0,     -- 최종 결제액
    tip_amount      INTEGER NOT NULL DEFAULT 0,
    -- 포인트
    points_earned   INTEGER NOT NULL DEFAULT 0,     -- 적립 포인트
    points_used     INTEGER NOT NULL DEFAULT 0,     -- 사용 포인트
    -- 상태
    status          TEXT NOT NULL DEFAULT 'completed',
                    -- 'draft','completed','refunded','partially_refunded','void'
    -- 시스템
    is_offline      INTEGER NOT NULL DEFAULT 0,
    memo            TEXT,
    receipt_printed INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    synced_at       TEXT
);
CREATE INDEX IF NOT EXISTS idx_sales_created    ON sales(created_at);
CREATE INDEX IF NOT EXISTS idx_sales_date       ON sales(date(created_at));
CREATE INDEX IF NOT EXISTS idx_sales_customer   ON sales(customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_staff      ON sales(staff_id);
CREATE INDEX IF NOT EXISTS idx_sales_session    ON sales(session_id);
CREATE INDEX IF NOT EXISTS idx_sales_status     ON sales(status);

-- 판매 항목 상세
CREATE TABLE IF NOT EXISTS sale_items (
    id              TEXT PRIMARY KEY,
    sale_id         TEXT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    item_type       TEXT NOT NULL,      -- 'menu','product','membership','gift_card'
    ref_id          TEXT NOT NULL,      -- 참조 ID
    -- 스냅샷 (원본 변경 대응)
    name            TEXT NOT NULL,
    name_jp         TEXT,
    quantity        INTEGER NOT NULL DEFAULT 1,
    unit_price      INTEGER NOT NULL,   -- 세전 단가
    discount_amount INTEGER NOT NULL DEFAULT 0,
    tax_type        TEXT NOT NULL DEFAULT 'inclusive',
    tax_rate        REAL NOT NULL DEFAULT 0.10,
    tax_amount      INTEGER NOT NULL DEFAULT 0,
    total_price     INTEGER NOT NULL,   -- 최종 항목 금액 (세포함)
    -- 메뉴 전용
    staff_id        TEXT REFERENCES staff(id),  -- 시술 스태프
    selected_options TEXT,              -- JSON
    -- 재고 차감
    inventory_deducted INTEGER NOT NULL DEFAULT 0,
    sort_order      INTEGER NOT NULL DEFAULT 0
);

-- 판매 할인 적용 내역
CREATE TABLE IF NOT EXISTS sale_discounts (
    id              TEXT PRIMARY KEY,
    sale_id         TEXT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    discount_id     TEXT REFERENCES discounts(id),
    coupon_id       TEXT REFERENCES coupons(id),
    name            TEXT NOT NULL,
    discount_type   TEXT NOT NULL,
    discount_amount INTEGER NOT NULL
);

-- 결제 수단 (분할 결제 지원)
CREATE TABLE IF NOT EXISTS sale_payments (
    id              TEXT PRIMARY KEY,
    sale_id         TEXT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    method          TEXT NOT NULL,
                    -- 'cash','credit_card','debit_card','ic_card','qr_code',
                    -- 'paypay','linepay','gift_card','point','stella','other'
    amount          INTEGER NOT NULL,
    -- 카드 정보
    card_brand      TEXT,               -- 'visa','mastercard','jcb'...
    approval_no     TEXT,               -- 카드 승인번호
    -- 기프트카드
    gift_card_id    TEXT REFERENCES gift_cards(id),
    -- 기타
    reference_no    TEXT,
    memo            TEXT,
    paid_at         TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 환불
CREATE TABLE IF NOT EXISTS refunds (
    id              TEXT PRIMARY KEY,
    refund_no       TEXT NOT NULL UNIQUE,   -- RF20250113-0001
    original_sale_id TEXT NOT NULL REFERENCES sales(id),
    processed_by    TEXT NOT NULL REFERENCES staff(id),
    refund_reason   TEXT NOT NULL,
    total_refund    INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'completed',
    memo            TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 환불 항목
CREATE TABLE IF NOT EXISTS refund_items (
    id          TEXT PRIMARY KEY,
    refund_id   TEXT NOT NULL REFERENCES refunds(id) ON DELETE CASCADE,
    sale_item_id TEXT NOT NULL REFERENCES sale_items(id),
    quantity    INTEGER NOT NULL DEFAULT 1,
    refund_amount INTEGER NOT NULL
);

-- 환불 결제 내역
CREATE TABLE IF NOT EXISTS refund_payments (
    id          TEXT PRIMARY KEY,
    refund_id   TEXT NOT NULL REFERENCES refunds(id) ON DELETE CASCADE,
    method      TEXT NOT NULL,          -- 원결제 수단과 동일
    amount      INTEGER NOT NULL,
    reference_no TEXT,
    returned_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- Draft 판매 (작업 중단 복구)
CREATE TABLE IF NOT EXISTS draft_sales (
    id      TEXT PRIMARY KEY DEFAULT 'current',
    data    TEXT NOT NULL,
    saved_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
