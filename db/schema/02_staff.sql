-- ============================================================
-- 02. STAFF — 스태프 / 시프트 / 출퇴근 / 급여
-- ============================================================

-- 스태프
CREATE TABLE IF NOT EXISTS staff (
    id              TEXT PRIMARY KEY,
    staff_no        TEXT UNIQUE,            -- 표시용 번호 ST001
    name            TEXT NOT NULL,
    name_kana       TEXT,
    role            TEXT NOT NULL DEFAULT 'stylist',
                    -- 'owner','manager','stylist','assistant','receptionist','part_time'
    pin             TEXT,                   -- 4자리 PIN SHA256 해시
    color           TEXT NOT NULL DEFAULT '#0064FF', -- 캘린더 색상
    phone           TEXT,
    email           TEXT,
    address         TEXT,
    birth_date      TEXT,
    hire_date       TEXT,
    resign_date     TEXT,
    employment_type TEXT NOT NULL DEFAULT 'full_time',
                    -- 'full_time','part_time','contract','owner'
    -- 급여 설정
    pay_type        TEXT NOT NULL DEFAULT 'monthly',
                    -- 'monthly'월급 / 'hourly'시급 / 'commission'완전 커미션
    base_salary     INTEGER DEFAULT 0,      -- 월급 또는 시급 (엔)
    -- 커미션 기본 설정
    commission_type TEXT NOT NULL DEFAULT 'rate',
                    -- 'rate'비율 / 'tiered'단계별 / 'none'없음
    commission_rate REAL DEFAULT 0.0,       -- 기본 커미션율 (0.0~1.0)
    -- 접근 권한 JSON
    permissions     TEXT NOT NULL DEFAULT '{}',
                    -- {"view_sales":true,"manage_staff":false,...}
    -- 소셜/기타
    memo            TEXT,
    photo_path      TEXT,
    is_active       INTEGER NOT NULL DEFAULT 1,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 스태프별 메뉴 커미션 (메뉴마다 다른 커미션율)
CREATE TABLE IF NOT EXISTS staff_menu_commissions (
    id              TEXT PRIMARY KEY,
    staff_id        TEXT NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    menu_id         TEXT NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
    commission_rate REAL NOT NULL,
    UNIQUE(staff_id, menu_id)
);

-- 단계별 커미션 설정 (월 매출 구간별)
CREATE TABLE IF NOT EXISTS staff_commission_tiers (
    id              TEXT PRIMARY KEY,
    staff_id        TEXT NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    tier_order      INTEGER NOT NULL,
    min_amount      INTEGER NOT NULL,       -- 이 구간 시작 매출 (엔)
    max_amount      INTEGER,                -- NULL = 상한 없음
    rate            REAL NOT NULL,
    UNIQUE(staff_id, tier_order)
);

-- 시프트 패턴 (반복 일정용 템플릿)
CREATE TABLE IF NOT EXISTS shift_patterns (
    id              TEXT PRIMARY KEY,
    staff_id        TEXT NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    day_of_week     INTEGER NOT NULL,       -- 0=일,1=월...6=토
    start_time      TEXT NOT NULL,          -- HH:MM
    end_time        TEXT NOT NULL,
    break_minutes   INTEGER NOT NULL DEFAULT 60,
    is_holiday      INTEGER NOT NULL DEFAULT 0
);

-- 실제 시프트 (날짜별 확정 스케줄)
CREATE TABLE IF NOT EXISTS shifts (
    id              TEXT PRIMARY KEY,
    staff_id        TEXT NOT NULL REFERENCES staff(id),
    shift_date      TEXT NOT NULL,          -- YYYY-MM-DD
    start_time      TEXT,                   -- HH:MM (휴일이면 NULL)
    end_time        TEXT,
    break_minutes   INTEGER NOT NULL DEFAULT 60,
    shift_type      TEXT NOT NULL DEFAULT 'work',
                    -- 'work','day_off','holiday','sick','paid_leave','training'
    memo            TEXT,
    is_confirmed    INTEGER NOT NULL DEFAULT 0,  -- 확정 여부
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_unique ON shifts(staff_id, shift_date);
CREATE INDEX IF NOT EXISTS idx_shifts_date ON shifts(shift_date);

-- 출퇴근 기록 (실제 근무 시간)
CREATE TABLE IF NOT EXISTS attendance (
    id              TEXT PRIMARY KEY,
    staff_id        TEXT NOT NULL REFERENCES staff(id),
    work_date       TEXT NOT NULL,          -- YYYY-MM-DD
    clock_in        TEXT,                   -- datetime
    clock_out       TEXT,
    break_start     TEXT,
    break_end       TEXT,
    actual_minutes  INTEGER,                -- 실 근무 분 (자동 계산)
    overtime_minutes INTEGER NOT NULL DEFAULT 0,
    memo            TEXT,
    is_approved     INTEGER NOT NULL DEFAULT 0,  -- 관리자 승인
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_attendance_date  ON attendance(work_date);
CREATE INDEX IF NOT EXISTS idx_attendance_staff ON attendance(staff_id);

-- 급여 기간 (월급 정산 단위)
CREATE TABLE IF NOT EXISTS payroll_periods (
    id              TEXT PRIMARY KEY,
    period_year     INTEGER NOT NULL,
    period_month    INTEGER NOT NULL,
    start_date      TEXT NOT NULL,
    end_date        TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open',
                    -- 'open','calculating','confirmed','paid'
    confirmed_at    TEXT,
    paid_at         TEXT,
    UNIQUE(period_year, period_month)
);

-- 급여 명세 (스태프별)
CREATE TABLE IF NOT EXISTS payroll (
    id              TEXT PRIMARY KEY,
    period_id       TEXT NOT NULL REFERENCES payroll_periods(id),
    staff_id        TEXT NOT NULL REFERENCES staff(id),
    -- 지급 항목
    base_pay        INTEGER NOT NULL DEFAULT 0,  -- 기본급
    overtime_pay    INTEGER NOT NULL DEFAULT 0,  -- 잔업 수당
    commission_pay  INTEGER NOT NULL DEFAULT 0,  -- 커미션
    bonus           INTEGER NOT NULL DEFAULT 0,  -- 보너스
    allowances      INTEGER NOT NULL DEFAULT 0,  -- 각종 수당
    gross_pay       INTEGER NOT NULL DEFAULT 0,  -- 총지급액
    -- 공제 항목
    income_tax      INTEGER NOT NULL DEFAULT 0,  -- 소득세
    resident_tax    INTEGER NOT NULL DEFAULT 0,  -- 주민세
    health_insurance INTEGER NOT NULL DEFAULT 0, -- 건강보험
    pension         INTEGER NOT NULL DEFAULT 0,  -- 후생연금
    employment_insurance INTEGER NOT NULL DEFAULT 0, -- 고용보험
    other_deductions INTEGER NOT NULL DEFAULT 0,
    total_deductions INTEGER NOT NULL DEFAULT 0,
    net_pay         INTEGER NOT NULL DEFAULT 0,  -- 실지급액
    -- 집계 정보
    total_work_days INTEGER NOT NULL DEFAULT 0,
    total_work_hours REAL NOT NULL DEFAULT 0.0,
    total_sales     INTEGER NOT NULL DEFAULT 0,  -- 담당 매출 합계
    memo            TEXT,
    UNIQUE(period_id, staff_id)
);
