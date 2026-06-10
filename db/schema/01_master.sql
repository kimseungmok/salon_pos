-- ============================================================
-- 01. MASTER — 매장 설정 / 버전 / 시스템
-- ============================================================

-- 앱 버전 이력
CREATE TABLE IF NOT EXISTS app_versions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    version         TEXT NOT NULL UNIQUE,
    description     TEXT,
    features        TEXT,           -- JSON: ["기능A","기능B"]
    good_points     TEXT,           -- 이 버전의 강점
    improve_points  TEXT,           -- 다음에 고칠 것
    applied_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 매장 설정 (단일 레코드 id=1)
CREATE TABLE IF NOT EXISTS salon_settings (
    id                      INTEGER PRIMARY KEY DEFAULT 1,
    -- 기본 정보
    salon_name              TEXT NOT NULL DEFAULT '살롱명',
    salon_name_jp           TEXT,
    salon_name_kana         TEXT,                   -- 후리가나
    invoice_reg_no          TEXT,                   -- 適格請求書番号 T+13자리
    postal_code             TEXT,                   -- 〒XXX-XXXX
    address                 TEXT,
    address_jp              TEXT,
    phone                   TEXT,
    email                   TEXT,
    website                 TEXT,
    logo_path               TEXT,
    -- 재무 설정
    currency                TEXT NOT NULL DEFAULT 'JPY',
    tax_rate_standard       REAL NOT NULL DEFAULT 0.10,  -- 표준세율 10%
    tax_rate_reduced        REAL NOT NULL DEFAULT 0.08,  -- 경감세율 8% (음식료)
    tax_display_type        TEXT NOT NULL DEFAULT 'inclusive',
                            -- 'inclusive'세금포함 / 'exclusive'세금별도
    -- 영업 설정
    timezone                TEXT NOT NULL DEFAULT 'Asia/Tokyo',
    locale                  TEXT NOT NULL DEFAULT 'ja_JP',
    business_hours          TEXT,   -- JSON: {"mon":{"open":"09:00","close":"20:00"},...}
    regular_holiday         TEXT,   -- JSON: [0,1] (0=일,1=월 휴무)
    first_day_of_week       INTEGER NOT NULL DEFAULT 1,  -- 0=일,1=월
    appointment_interval    INTEGER NOT NULL DEFAULT 15, -- 예약 단위(분)
    -- 포인트 설정
    point_enabled           INTEGER NOT NULL DEFAULT 1,
    point_rate              REAL NOT NULL DEFAULT 0.01,  -- 1% 적립
    point_min_use           INTEGER NOT NULL DEFAULT 100, -- 최소 사용 포인트
    point_expiry_months     INTEGER DEFAULT 12,
    -- 영수증 설정
    receipt_header          TEXT,
    receipt_footer          TEXT DEFAULT 'ありがとうございました',
    receipt_show_staff      INTEGER NOT NULL DEFAULT 1,
    receipt_show_point      INTEGER NOT NULL DEFAULT 1,
    -- 알림 설정
    reminder_enabled        INTEGER NOT NULL DEFAULT 1,
    reminder_hours_before   INTEGER NOT NULL DEFAULT 24,
    -- 시재 설정
    drawer_opening_amount   INTEGER NOT NULL DEFAULT 50000, -- 개점 시재 기본액 (엔)
    created_at              TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at              TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 인쇄 설정
CREATE TABLE IF NOT EXISTS printer_settings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL,
    printer_type    TEXT NOT NULL,  -- 'receipt','kitchen','label'
    connection      TEXT NOT NULL,  -- 'bluetooth','wifi','usb'
    address         TEXT,           -- IP 또는 MAC 주소
    paper_width     INTEGER DEFAULT 80, -- mm
    is_default      INTEGER NOT NULL DEFAULT 0,
    is_active       INTEGER NOT NULL DEFAULT 1
);

-- 시스템 로그 (중요 작업 기록)
CREATE TABLE IF NOT EXISTS audit_logs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    staff_id        TEXT,
    action          TEXT NOT NULL,  -- 'sale','refund','delete_customer'...
    entity_type     TEXT,
    entity_id       TEXT,
    detail          TEXT,           -- JSON
    ip_address      TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_action  ON audit_logs(action);
