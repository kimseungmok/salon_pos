-- ============================================================
-- 04. MENU & BOOKING — 메뉴 / 리소스 / 예약
-- ============================================================

-- 메뉴 카테고리
CREATE TABLE IF NOT EXISTS menu_categories (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    name_jp     TEXT,
    description TEXT,
    color       TEXT,
    icon        TEXT,       -- 아이콘 코드 또는 이모지
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 메뉴 (서비스)
CREATE TABLE IF NOT EXISTS menus (
    id              TEXT PRIMARY KEY,
    category_id     TEXT REFERENCES menu_categories(id),
    name            TEXT NOT NULL,
    name_jp         TEXT,
    description     TEXT,
    description_jp  TEXT,
    -- 가격
    price           INTEGER NOT NULL DEFAULT 0,
    price_max       INTEGER,            -- 가격 범위 (¥3000~¥5000)
    is_price_range  INTEGER NOT NULL DEFAULT 0,
    tax_type        TEXT NOT NULL DEFAULT 'inclusive',
                    -- 'inclusive'세금포함 / 'exclusive'세금별도 / 'exempt'비과세
    tax_rate        REAL,               -- NULL이면 salon_settings 따름
    -- 시간
    duration_min    INTEGER NOT NULL DEFAULT 60,
    buffer_min      INTEGER NOT NULL DEFAULT 0,  -- 준비/정리 버퍼 시간
    -- 표시
    color           TEXT,
    thumbnail_path  TEXT,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    is_active       INTEGER NOT NULL DEFAULT 1,
    is_favorite     INTEGER NOT NULL DEFAULT 0,
    is_online_bookable INTEGER NOT NULL DEFAULT 1, -- 온라인 예약 가능
    -- 재고 연동
    linked_product_id TEXT,             -- 사용하는 재고 상품 (예: 염색약)
    -- 메타
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_menus_category ON menus(category_id);
CREATE INDEX IF NOT EXISTS idx_menus_active   ON menus(is_active);

-- 스태프별 가격 (숙련도/지명료)
CREATE TABLE IF NOT EXISTS menu_staff_prices (
    id          TEXT PRIMARY KEY,
    menu_id     TEXT NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
    staff_id    TEXT NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    price       INTEGER NOT NULL,
    duration_min INTEGER,               -- NULL이면 메뉴 기본값
    UNIQUE(menu_id, staff_id)
);

-- 메뉴 옵션 그룹
CREATE TABLE IF NOT EXISTS menu_option_groups (
    id          TEXT PRIMARY KEY,
    menu_id     TEXT NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    name_jp     TEXT,
    is_required INTEGER NOT NULL DEFAULT 0,
    min_select  INTEGER NOT NULL DEFAULT 0,
    max_select  INTEGER NOT NULL DEFAULT 1,
    sort_order  INTEGER NOT NULL DEFAULT 0
);

-- 메뉴 옵션 항목
CREATE TABLE IF NOT EXISTS menu_options (
    id          TEXT PRIMARY KEY,
    group_id    TEXT NOT NULL REFERENCES menu_option_groups(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    name_jp     TEXT,
    price_delta INTEGER NOT NULL DEFAULT 0,  -- 추가금액 (음수가능)
    time_delta  INTEGER NOT NULL DEFAULT 0,  -- 추가시간 (분)
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_active   INTEGER NOT NULL DEFAULT 1
);

-- 리소스 (의자·룸·장비)
CREATE TABLE IF NOT EXISTS resources (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    name_jp     TEXT,
    resource_type TEXT NOT NULL DEFAULT 'chair',
                -- 'chair','room','equipment','staff'
    capacity    INTEGER NOT NULL DEFAULT 1,
    color       TEXT,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_active   INTEGER NOT NULL DEFAULT 1
);

-- 리소스 ↔ 메뉴 연결 (이 리소스가 필요한 메뉴)
CREATE TABLE IF NOT EXISTS resource_menu_links (
    resource_id TEXT NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
    menu_id     TEXT NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
    PRIMARY KEY(resource_id, menu_id)
);

-- 예약
CREATE TABLE IF NOT EXISTS appointments (
    id              TEXT PRIMARY KEY,
    -- 연관
    customer_id     TEXT REFERENCES customers(id),
    staff_id        TEXT REFERENCES staff(id),
    resource_id     TEXT REFERENCES resources(id),
    -- 시간
    start_at        TEXT NOT NULL,      -- ISO8601 datetime
    end_at          TEXT NOT NULL,
    actual_start_at TEXT,               -- 실제 시작 시간
    actual_end_at   TEXT,
    -- 상태
    status          TEXT NOT NULL DEFAULT 'confirmed',
                    -- 'pending','confirmed','in_progress','completed',
                    -- 'cancelled','no_show'
    -- 예약 출처
    source          TEXT NOT NULL DEFAULT 'pos',
                    -- 'pos','online','phone','walk_in','line'
    -- 색상 (캘린더 표시)
    color           TEXT,
    -- 금액 정보 (예약 시점 스냅샷)
    estimated_price INTEGER NOT NULL DEFAULT 0,
    -- 취소 정보
    cancel_reason   TEXT,
    cancelled_at    TEXT,
    cancelled_by    TEXT REFERENCES staff(id),
    no_show_fee     INTEGER NOT NULL DEFAULT 0,
    -- 알림
    reminder_sent   INTEGER NOT NULL DEFAULT 0,
    reminder_sent_at TEXT,
    -- 메모
    customer_memo   TEXT,               -- 고객이 입력한 요청
    staff_memo      TEXT,               -- 스태프 메모
    -- 시스템
    is_offline      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    synced_at       TEXT
);
CREATE INDEX IF NOT EXISTS idx_apt_start    ON appointments(start_at);
CREATE INDEX IF NOT EXISTS idx_apt_staff    ON appointments(staff_id);
CREATE INDEX IF NOT EXISTS idx_apt_customer ON appointments(customer_id);
CREATE INDEX IF NOT EXISTS idx_apt_status   ON appointments(status);
CREATE INDEX IF NOT EXISTS idx_apt_date     ON appointments(date(start_at));

-- 예약 메뉴 상세
CREATE TABLE IF NOT EXISTS appointment_menus (
    id              TEXT PRIMARY KEY,
    appointment_id  TEXT NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
    menu_id         TEXT NOT NULL REFERENCES menus(id),
    -- 스냅샷 (메뉴 변경 대응)
    menu_name       TEXT NOT NULL,
    menu_name_jp    TEXT,
    price           INTEGER NOT NULL,
    duration_min    INTEGER NOT NULL,
    selected_options TEXT,              -- JSON: [{name,price_delta},...]
    staff_id        TEXT REFERENCES staff(id),  -- 이 메뉴 담당 스태프
    sort_order      INTEGER NOT NULL DEFAULT 0
);

-- 대기 명단
CREATE TABLE IF NOT EXISTS waitlist (
    id              TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL REFERENCES customers(id),
    staff_id        TEXT REFERENCES staff(id),  -- 희망 스태프
    menu_id         TEXT REFERENCES menus(id),
    requested_date  TEXT NOT NULL,              -- 희망 날짜
    time_preference TEXT,                       -- '오전','오후','저녁'
    memo            TEXT,
    status          TEXT NOT NULL DEFAULT 'waiting',
                    -- 'waiting','notified','booked','cancelled'
    notified_at     TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- Draft 예약 (작업 중단 복구)
CREATE TABLE IF NOT EXISTS draft_appointments (
    id      TEXT PRIMARY KEY DEFAULT 'current',
    data    TEXT NOT NULL,
    saved_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
