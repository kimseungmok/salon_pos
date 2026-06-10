-- ============================================================
-- 03. CUSTOMER — 고객 / 회원권 / 포인트 / 카르테
-- ============================================================

-- 고객 태그 마스터
CREATE TABLE IF NOT EXISTS customer_tags (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    name_jp         TEXT,
    color           TEXT,
    sort_order      INTEGER NOT NULL DEFAULT 0
);

-- 고객
CREATE TABLE IF NOT EXISTS customers (
    id              TEXT PRIMARY KEY,
    customer_no     TEXT UNIQUE,            -- C00001 자동 발행
    -- 기본 정보
    name            TEXT NOT NULL,
    name_kana       TEXT,                   -- 후리가나
    nickname        TEXT,
    gender          TEXT DEFAULT 'unspecified',
                    -- 'male','female','other','unspecified'
    birth_date      TEXT,                   -- YYYY-MM-DD
    -- 연락처
    phone           TEXT,
    phone2          TEXT,                   -- 보조 번호
    email           TEXT,
    line_id         TEXT,
    instagram       TEXT,
    -- 주소
    postal_code     TEXT,
    prefecture      TEXT,
    city            TEXT,
    address_detail  TEXT,
    -- 내점 정보
    first_visit_date TEXT,
    last_visit_date  TEXT,
    total_visits    INTEGER NOT NULL DEFAULT 0,
    total_spent     INTEGER NOT NULL DEFAULT 0,  -- 누적 결제액
    referral_source TEXT,                   -- '소개','SNS','HPB','지나가다'...
    referral_staff_id TEXT REFERENCES staff(id), -- 소개한 스태프
    referral_customer_id TEXT REFERENCES customers(id), -- 소개한 고객
    -- 살롱 관련
    assigned_staff_id TEXT REFERENCES staff(id), -- 담당 스태프
    visit_cycle_days INTEGER,               -- 평균 내점 주기 (자동 계산)
    -- 신체/시술 정보
    allergies       TEXT,           -- JSON: ["파마약","염색약"]
    patch_test_date TEXT,
    patch_test_result TEXT,         -- '異常なし','反応あり'
    skin_type       TEXT,           -- '건성','지성','복합'...
    scalp_type      TEXT,
    hair_texture    TEXT,
    -- 기타
    memo            TEXT,           -- 일반 메모 (고객에게 보임)
    staff_memo      TEXT,           -- 스태프 내부 메모 (고객 비공개)
    caution_flag    INTEGER NOT NULL DEFAULT 0, -- 주의 고객 플래그
    caution_reason  TEXT,
    is_member       INTEGER NOT NULL DEFAULT 0,
    is_vip          INTEGER NOT NULL DEFAULT 0,
    -- 포인트
    point_balance   INTEGER NOT NULL DEFAULT 0,
    point_expiry_date TEXT,
    -- 상태
    is_deleted      INTEGER NOT NULL DEFAULT 0,
    opt_out_sms     INTEGER NOT NULL DEFAULT 0,  -- SMS 수신 거부
    opt_out_email   INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    synced_at       TEXT
);
CREATE INDEX IF NOT EXISTS idx_customers_name    ON customers(name);
CREATE INDEX IF NOT EXISTS idx_customers_kana    ON customers(name_kana);
CREATE INDEX IF NOT EXISTS idx_customers_phone   ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_no      ON customers(customer_no);
CREATE INDEX IF NOT EXISTS idx_customers_deleted ON customers(is_deleted);

-- 고객 ↔ 태그 연결
CREATE TABLE IF NOT EXISTS customer_tag_links (
    customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    tag_id      TEXT NOT NULL REFERENCES customer_tags(id) ON DELETE CASCADE,
    PRIMARY KEY (customer_id, tag_id)
);

-- 시술 기록 (카르테)
CREATE TABLE IF NOT EXISTS treatment_records (
    id              TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL REFERENCES customers(id),
    sale_id         TEXT,               -- 연결된 판매 (나중에 FK)
    staff_id        TEXT REFERENCES staff(id),
    visit_date      TEXT NOT NULL,
    -- 시술 내용
    menu_summary    TEXT,               -- '컷트+컬러' 요약 텍스트
    hair_length     TEXT,               -- 'short','medium','long','very_long'
    hair_condition  TEXT,               -- 모발 상태
    -- 색상 레시피
    color_brand     TEXT,               -- 약제 브랜드
    color_formula   TEXT,               -- 배합 레시피 상세
    color_level     TEXT,               -- 명도 레벨
    color_tone      TEXT,               -- 색조
    -- 파마
    perm_type       TEXT,               -- '콜드','디지털','에어'...
    perm_rod_size   TEXT,               -- 롯드 사이즈
    perm_solution   TEXT,               -- 약제 정보
    -- 처치 내용
    treatment_detail TEXT,
    scalp_condition TEXT,
    -- 다음 방문 관련
    next_visit_recommendation TEXT,     -- 다음 방문 권장 기간
    next_visit_menu TEXT,               -- 다음에 할 시술
    next_visit_caution TEXT,            -- 다음 방문 주의사항
    -- 사진
    photo_before_path TEXT,
    photo_after_path  TEXT,
    photos_json     TEXT,               -- JSON: 추가 사진 경로 배열
    -- 만족도
    satisfaction    INTEGER,            -- 1~5
    memo            TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_treatment_customer   ON treatment_records(customer_id);
CREATE INDEX IF NOT EXISTS idx_treatment_visit_date ON treatment_records(visit_date);

-- 회원권 플랜 (월정액/회수권/기간권)
CREATE TABLE IF NOT EXISTS membership_plans (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    name_jp         TEXT,
    plan_type       TEXT NOT NULL,
                    -- 'monthly'월정액 / 'session'회수권 / 'period'기간권
    price           INTEGER NOT NULL,
    duration_months INTEGER,            -- 기간권: 유효 개월 수
    session_count   INTEGER,            -- 회수권: 총 회수
    included_menus  TEXT,               -- JSON: 포함 메뉴 ID 배열
    discount_rate   REAL DEFAULT 0.0,   -- 전 메뉴 할인율
    description     TEXT,
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 고객 회원권 (구매 이력)
CREATE TABLE IF NOT EXISTS customer_memberships (
    id              TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL REFERENCES customers(id),
    plan_id         TEXT NOT NULL REFERENCES membership_plans(id),
    sale_id         TEXT,
    -- 기간
    start_date      TEXT NOT NULL,
    end_date        TEXT,               -- NULL = 자동 갱신
    -- 회수권
    total_sessions  INTEGER,
    used_sessions   INTEGER NOT NULL DEFAULT 0,
    remaining_sessions INTEGER,         -- 계산값
    -- 상태
    status          TEXT NOT NULL DEFAULT 'active',
                    -- 'active','expired','cancelled','suspended'
    auto_renew      INTEGER NOT NULL DEFAULT 0,
    -- 결제
    price_paid      INTEGER NOT NULL DEFAULT 0,
    next_billing_date TEXT,
    memo            TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_membership_customer ON customer_memberships(customer_id);
CREATE INDEX IF NOT EXISTS idx_membership_status   ON customer_memberships(status);

-- 회원권 사용 이력
CREATE TABLE IF NOT EXISTS membership_usage (
    id              TEXT PRIMARY KEY,
    membership_id   TEXT NOT NULL REFERENCES customer_memberships(id),
    sale_id         TEXT,
    used_at         TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    memo            TEXT
);

-- 포인트 이력
CREATE TABLE IF NOT EXISTS point_history (
    id              TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL REFERENCES customers(id),
    sale_id         TEXT,
    change_amount   INTEGER NOT NULL,   -- 양수:적립 음수:사용
    balance_after   INTEGER NOT NULL,
    expiry_date     TEXT,
    reason          TEXT NOT NULL,
                    -- '구매적립','생일보너스','이벤트','수동조정','만료','사용'
    staff_id        TEXT REFERENCES staff(id),
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_point_customer ON point_history(customer_id);

-- 기프트카드
CREATE TABLE IF NOT EXISTS gift_cards (
    id              TEXT PRIMARY KEY,
    code            TEXT NOT NULL UNIQUE,  -- GC-XXXXXX
    name            TEXT,
    initial_amount  INTEGER NOT NULL,
    balance         INTEGER NOT NULL,
    issue_date      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    expiry_date     TEXT,
    issued_by_sale_id TEXT,
    issued_to_customer_id TEXT REFERENCES customers(id),
    status          TEXT NOT NULL DEFAULT 'active',
                    -- 'active','used','expired','void'
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 기프트카드 사용 이력
CREATE TABLE IF NOT EXISTS gift_card_transactions (
    id              TEXT PRIMARY KEY,
    gift_card_id    TEXT NOT NULL REFERENCES gift_cards(id),
    sale_id         TEXT,
    amount          INTEGER NOT NULL,       -- 음수:사용 양수:환불
    balance_after   INTEGER NOT NULL,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
