-- ============================================================
-- 07. FINANCE — 경비 / 매출집계 / 손익 / 세무
-- ============================================================

-- 경비 카테고리
CREATE TABLE IF NOT EXISTS expense_categories (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    name_jp     TEXT,
    -- 경리용 계정과목
    account_code TEXT,          -- 勘定科目코드 (예: '交通費','消耗品費')
    account_name TEXT,          -- 勘定科目명
    is_tax_deductible INTEGER NOT NULL DEFAULT 1,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    parent_id   TEXT REFERENCES expense_categories(id)
);

-- 경비 기록
CREATE TABLE IF NOT EXISTS expenses (
    id              TEXT PRIMARY KEY,
    category_id     TEXT NOT NULL REFERENCES expense_categories(id),
    staff_id        TEXT REFERENCES staff(id),  -- 지출자
    -- 금액
    amount          INTEGER NOT NULL,           -- 세별도 금액
    tax_type        TEXT NOT NULL DEFAULT 'inclusive',
    tax_rate        REAL NOT NULL DEFAULT 0.10,
    tax_amount      INTEGER NOT NULL DEFAULT 0,
    total_amount    INTEGER NOT NULL,           -- 최종 금액
    -- 정보
    expense_date    TEXT NOT NULL,
    description     TEXT NOT NULL,
    vendor          TEXT,                       -- 거래처
    receipt_no      TEXT,                       -- 영수증 번호
    receipt_path    TEXT,                       -- 영수증 사진 경로
    payment_method  TEXT DEFAULT 'cash',
                    -- 'cash','bank_transfer','card','petty_cash'
    -- 세무
    is_deductible   INTEGER NOT NULL DEFAULT 1,
    memo            TEXT,
    approved_by     TEXT REFERENCES staff(id),
    is_approved     INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_expense_date ON expenses(expense_date);
CREATE INDEX IF NOT EXISTS idx_expense_cat  ON expenses(category_id);

-- 일별 집계 (빠른 리포트용 캐시 테이블)
CREATE TABLE IF NOT EXISTS daily_summaries (
    id              TEXT PRIMARY KEY,
    summary_date    TEXT NOT NULL UNIQUE,   -- YYYY-MM-DD
    -- 매출
    total_sales     INTEGER NOT NULL DEFAULT 0,     -- 총매출 (세포함)
    total_sales_excl_tax INTEGER NOT NULL DEFAULT 0,-- 총매출 (세별도)
    tax_10_base     INTEGER NOT NULL DEFAULT 0,
    tax_10_amount   INTEGER NOT NULL DEFAULT 0,
    tax_8_base      INTEGER NOT NULL DEFAULT 0,
    tax_8_amount    INTEGER NOT NULL DEFAULT 0,
    total_tax       INTEGER NOT NULL DEFAULT 0,
    -- 거래 건수
    total_transactions INTEGER NOT NULL DEFAULT 0,
    new_customers   INTEGER NOT NULL DEFAULT 0,
    repeat_customers INTEGER NOT NULL DEFAULT 0,
    -- 결제 수단별
    cash_amount     INTEGER NOT NULL DEFAULT 0,
    card_amount     INTEGER NOT NULL DEFAULT 0,
    qr_amount       INTEGER NOT NULL DEFAULT 0,
    gift_card_amount INTEGER NOT NULL DEFAULT 0,
    point_discount  INTEGER NOT NULL DEFAULT 0,
    other_amount    INTEGER NOT NULL DEFAULT 0,
    -- 할인
    total_discount  INTEGER NOT NULL DEFAULT 0,
    -- 환불
    total_refund    INTEGER NOT NULL DEFAULT 0,
    refund_count    INTEGER NOT NULL DEFAULT 0,
    -- 순매출
    net_sales       INTEGER NOT NULL DEFAULT 0,     -- total_sales - total_refund
    -- 경비 (당일)
    total_expense   INTEGER NOT NULL DEFAULT 0,
    -- 시술별 통계 JSON
    menu_breakdown  TEXT,   -- JSON: [{menu_id,name,count,amount},...]
    staff_breakdown TEXT,   -- JSON: [{staff_id,name,count,amount},...]
    -- 메타
    calculated_at   TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 월별 집계
CREATE TABLE IF NOT EXISTS monthly_summaries (
    id              TEXT PRIMARY KEY,
    year            INTEGER NOT NULL,
    month           INTEGER NOT NULL,
    -- 매출
    total_sales     INTEGER NOT NULL DEFAULT 0,
    net_sales       INTEGER NOT NULL DEFAULT 0,
    total_refund    INTEGER NOT NULL DEFAULT 0,
    total_tax       INTEGER NOT NULL DEFAULT 0,
    -- 경비
    total_expense   INTEGER NOT NULL DEFAULT 0,
    -- 급여
    total_payroll   INTEGER NOT NULL DEFAULT 0,
    -- 손익
    gross_profit    INTEGER NOT NULL DEFAULT 0,  -- net_sales - cost_of_goods
    operating_income INTEGER NOT NULL DEFAULT 0, -- gross_profit - expense - payroll
    -- 고객
    total_customers    INTEGER NOT NULL DEFAULT 0,
    new_customers      INTEGER NOT NULL DEFAULT 0,
    repeat_customers   INTEGER NOT NULL DEFAULT 0,
    lost_customers     INTEGER NOT NULL DEFAULT 0,  -- 이탈 고객
    avg_customer_spend INTEGER NOT NULL DEFAULT 0,
    -- 예약
    total_appointments INTEGER NOT NULL DEFAULT 0,
    completed_appointments INTEGER NOT NULL DEFAULT 0,
    cancelled_appointments INTEGER NOT NULL DEFAULT 0,
    no_show_appointments   INTEGER NOT NULL DEFAULT 0,
    -- 스태프 JSON
    staff_breakdown TEXT,
    -- 메타
    calculated_at   TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    UNIQUE(year, month)
);

-- 연간 집계
CREATE TABLE IF NOT EXISTS yearly_summaries (
    id              TEXT PRIMARY KEY,
    year            INTEGER NOT NULL UNIQUE,
    total_sales     INTEGER NOT NULL DEFAULT 0,
    net_sales       INTEGER NOT NULL DEFAULT 0,
    total_expense   INTEGER NOT NULL DEFAULT 0,
    total_payroll   INTEGER NOT NULL DEFAULT 0,
    operating_income INTEGER NOT NULL DEFAULT 0,
    total_customers INTEGER NOT NULL DEFAULT 0,
    calculated_at   TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 세금 신고 기간 (消費税申告)
CREATE TABLE IF NOT EXISTS tax_periods (
    id              TEXT PRIMARY KEY,
    period_name     TEXT NOT NULL,          -- '2025年1月~3月'
    start_date      TEXT NOT NULL,
    end_date        TEXT NOT NULL,
    filing_type     TEXT NOT NULL DEFAULT 'quarterly',
                    -- 'monthly','quarterly','annual'
    -- 10% 과세
    taxable_10      INTEGER NOT NULL DEFAULT 0,
    tax_10          INTEGER NOT NULL DEFAULT 0,
    -- 8% 경감세율
    taxable_8       INTEGER NOT NULL DEFAULT 0,
    tax_8           INTEGER NOT NULL DEFAULT 0,
    -- 비과세
    exempt_amount   INTEGER NOT NULL DEFAULT 0,
    -- 합계
    total_tax       INTEGER NOT NULL DEFAULT 0,
    -- 신고 상태
    status          TEXT NOT NULL DEFAULT 'open',
                    -- 'open','filed','paid'
    filed_at        TEXT,
    paid_at         TEXT,
    memo            TEXT
);

-- KPI 목표 (스태프별/기간별)
CREATE TABLE IF NOT EXISTS kpi_targets (
    id              TEXT PRIMARY KEY,
    target_type     TEXT NOT NULL,      -- 'salon','staff'
    staff_id        TEXT REFERENCES staff(id),  -- NULL이면 매장 전체
    year            INTEGER NOT NULL,
    month           INTEGER NOT NULL,
    -- 목표값
    sales_target    INTEGER,            -- 매출 목표
    customer_target INTEGER,            -- 고객 수 목표
    new_customer_target INTEGER,        -- 신규 고객 목표
    repeat_rate_target REAL,            -- 재방문율 목표 (0.0~1.0)
    avg_spend_target INTEGER,           -- 객단가 목표
    memo            TEXT,
    UNIQUE(target_type, staff_id, year, month)
);
