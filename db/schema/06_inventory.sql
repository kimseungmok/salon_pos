-- ============================================================
-- 06. INVENTORY — 재고 / 상품 / 발주 / 공급업체
-- ============================================================

-- 상품 카테고리
CREATE TABLE IF NOT EXISTS product_categories (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    name_jp     TEXT,
    parent_id   TEXT REFERENCES product_categories(id),  -- 2단계 분류
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_active   INTEGER NOT NULL DEFAULT 1
);

-- 공급업체 (발주처)
CREATE TABLE IF NOT EXISTS suppliers (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    name_jp         TEXT,
    contact_person  TEXT,
    phone           TEXT,
    email           TEXT,
    fax             TEXT,
    address         TEXT,
    website         TEXT,
    payment_terms   TEXT,               -- '월말締め翌月払い' 등
    memo            TEXT,
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 상품 (재고 관리 대상)
CREATE TABLE IF NOT EXISTS products (
    id              TEXT PRIMARY KEY,
    category_id     TEXT REFERENCES product_categories(id),
    supplier_id     TEXT REFERENCES suppliers(id),
    -- 기본 정보
    name            TEXT NOT NULL,
    name_jp         TEXT,
    sku             TEXT UNIQUE,        -- 자체 관리 코드
    barcode         TEXT UNIQUE,        -- JAN 바코드
    brand           TEXT,
    -- 가격
    cost_price      INTEGER NOT NULL DEFAULT 0,    -- 원가 (세별도)
    sell_price      INTEGER NOT NULL DEFAULT 0,    -- 판매가
    tax_type        TEXT NOT NULL DEFAULT 'inclusive',
    tax_rate        REAL DEFAULT 0.10,
    -- 재고
    stock_quantity  INTEGER NOT NULL DEFAULT 0,    -- 현재 재고
    stock_unit      TEXT NOT NULL DEFAULT '個',    -- 단위 (個,本,ml...)
    min_stock       INTEGER NOT NULL DEFAULT 0,    -- 최소 재고 (경고 기준)
    reorder_point   INTEGER NOT NULL DEFAULT 5,    -- 발주 트리거 기준
    reorder_qty     INTEGER NOT NULL DEFAULT 10,   -- 기본 발주 수량
    max_stock       INTEGER,                       -- 최대 재고
    -- 보관
    storage_location TEXT,             -- 보관 위치 (진열대A-1 등)
    expiry_date     TEXT,              -- 유통기한 (해당 시)
    -- 분류
    product_type    TEXT NOT NULL DEFAULT 'retail',
                    -- 'retail'소매판매 / 'supply'시술재료 / 'both'겸용
    is_for_sale     INTEGER NOT NULL DEFAULT 1,    -- POS에서 판매
    is_active       INTEGER NOT NULL DEFAULT 1,
    memo            TEXT,
    -- 이미지
    image_path      TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_products_barcode   ON products(barcode);
CREATE INDEX IF NOT EXISTS idx_products_category  ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_active    ON products(is_active);

-- 재고 이동 이력 (모든 입출고)
CREATE TABLE IF NOT EXISTS inventory_movements (
    id              TEXT PRIMARY KEY,
    product_id      TEXT NOT NULL REFERENCES products(id),
    -- 이동 종류
    movement_type   TEXT NOT NULL,
                    -- 'purchase_in'구매입고 / 'sale_out'판매출고 /
                    -- 'return_in'반품입고 / 'waste_out'폐기출고 /
                    -- 'adjust_in'조정입고 / 'adjust_out'조정출고 /
                    -- 'transfer_in'이동입고 / 'transfer_out'이동출고 /
                    -- 'count_adjust'실사조정
    quantity        INTEGER NOT NULL,           -- 양수:입고 음수:출고
    stock_before    INTEGER NOT NULL,
    stock_after     INTEGER NOT NULL,
    -- 연관
    reference_type  TEXT,               -- 'sale','purchase_order','adjustment'...
    reference_id    TEXT,
    -- 단가 기록
    unit_cost       INTEGER DEFAULT 0,
    -- 기타
    batch_no        TEXT,               -- 로트 번호
    expiry_date     TEXT,
    staff_id        TEXT REFERENCES staff(id),
    memo            TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_inv_product   ON inventory_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_inv_type      ON inventory_movements(movement_type);
CREATE INDEX IF NOT EXISTS idx_inv_created   ON inventory_movements(created_at);

-- 발주서 (Purchase Order)
CREATE TABLE IF NOT EXISTS purchase_orders (
    id              TEXT PRIMARY KEY,
    po_no           TEXT NOT NULL UNIQUE,       -- PO20250113-001
    supplier_id     TEXT NOT NULL REFERENCES suppliers(id),
    ordered_by      TEXT REFERENCES staff(id),
    -- 날짜
    order_date      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    expected_date   TEXT,                       -- 납품 예정일
    received_date   TEXT,                       -- 실제 납품일
    -- 금액
    subtotal        INTEGER NOT NULL DEFAULT 0,
    tax_amount      INTEGER NOT NULL DEFAULT 0,
    total_amount    INTEGER NOT NULL DEFAULT 0,
    -- 상태
    status          TEXT NOT NULL DEFAULT 'draft',
                    -- 'draft','ordered','partial','received','cancelled'
    -- 결제
    payment_method  TEXT,
    payment_due_date TEXT,
    is_paid         INTEGER NOT NULL DEFAULT 0,
    paid_at         TEXT,
    memo            TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_po_status ON purchase_orders(status);

-- 발주 항목
CREATE TABLE IF NOT EXISTS purchase_order_items (
    id              TEXT PRIMARY KEY,
    po_id           TEXT NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    product_id      TEXT NOT NULL REFERENCES products(id),
    -- 스냅샷
    product_name    TEXT NOT NULL,
    -- 수량
    ordered_qty     INTEGER NOT NULL,
    received_qty    INTEGER NOT NULL DEFAULT 0,
    -- 가격
    unit_cost       INTEGER NOT NULL,
    tax_rate        REAL NOT NULL DEFAULT 0.10,
    total_cost      INTEGER NOT NULL,
    -- 상태
    status          TEXT NOT NULL DEFAULT 'pending',
                    -- 'pending','partial','received','cancelled'
    memo            TEXT
);

-- 재고 실사 (Stocktake)
CREATE TABLE IF NOT EXISTS stock_counts (
    id              TEXT PRIMARY KEY,
    count_no        TEXT NOT NULL UNIQUE,   -- SC20250113-001
    conducted_by    TEXT REFERENCES staff(id),
    count_date      TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'draft',
                    -- 'draft','in_progress','completed','cancelled'
    total_items     INTEGER NOT NULL DEFAULT 0,
    adjusted_items  INTEGER NOT NULL DEFAULT 0,
    memo            TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    completed_at    TEXT
);

-- 재고 실사 항목
CREATE TABLE IF NOT EXISTS stock_count_items (
    id              TEXT PRIMARY KEY,
    count_id        TEXT NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
    product_id      TEXT NOT NULL REFERENCES products(id),
    system_qty      INTEGER NOT NULL,   -- 시스템상 재고
    counted_qty     INTEGER,            -- 실제 센 수량 (NULL=미실사)
    difference      INTEGER,            -- counted - system
    unit_cost       INTEGER,
    is_adjusted     INTEGER NOT NULL DEFAULT 0  -- 조정 완료
);
