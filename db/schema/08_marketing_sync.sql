-- ============================================================
-- 08. MARKETING / SYNC — 마케팅 / 동기화 / 시스템
-- ============================================================

-- 메시지 템플릿
CREATE TABLE IF NOT EXISTS message_templates (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    template_type TEXT NOT NULL,
                -- 'reminder','birthday','thanks','campaign','recall'
    channel     TEXT NOT NULL DEFAULT 'sms',
                -- 'sms','line','email','push'
    subject     TEXT,                   -- 이메일 제목
    body        TEXT NOT NULL,          -- 본문 (변수: {{고객명}},{{날짜}},{{메뉴}})
    body_jp     TEXT,                   -- 일본어 본문
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 마케팅 캠페인
CREATE TABLE IF NOT EXISTS campaigns (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    campaign_type   TEXT NOT NULL,
                    -- 'blast'일제배신 / 'recall'이탈고객 / 'birthday'생일 / 'auto'자동
    target_segment  TEXT NOT NULL DEFAULT 'all',
                    -- 'all','new','repeat','lost','vip','birthday'
    target_filter   TEXT,               -- JSON 추가 필터 조건
    template_id     TEXT REFERENCES message_templates(id),
    -- 스케줄
    scheduled_at    TEXT,
    sent_at         TEXT,
    -- 통계
    target_count    INTEGER NOT NULL DEFAULT 0,
    sent_count      INTEGER NOT NULL DEFAULT 0,
    opened_count    INTEGER NOT NULL DEFAULT 0,
    click_count     INTEGER NOT NULL DEFAULT 0,
    -- 상태
    status          TEXT NOT NULL DEFAULT 'draft',
                    -- 'draft','scheduled','sending','sent','cancelled'
    memo            TEXT,
    created_by      TEXT REFERENCES staff(id),
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 메시지 발송 이력
CREATE TABLE IF NOT EXISTS message_logs (
    id              TEXT PRIMARY KEY,
    campaign_id     TEXT REFERENCES campaigns(id),
    customer_id     TEXT NOT NULL REFERENCES customers(id),
    template_id     TEXT REFERENCES message_templates(id),
    channel         TEXT NOT NULL,
    subject         TEXT,
    body            TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending',
                    -- 'pending','sent','delivered','failed','opted_out'
    sent_at         TEXT,
    delivered_at    TEXT,
    error_message   TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_msg_customer ON message_logs(customer_id);
CREATE INDEX IF NOT EXISTS idx_msg_created  ON message_logs(created_at);

-- 자동화 규칙 (리마인더·생일 등)
CREATE TABLE IF NOT EXISTS automation_rules (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    trigger_type    TEXT NOT NULL,
                    -- 'before_appointment'예약전 / 'after_sale'판매후 /
                    -- 'birthday' / 'no_visit'미방문 / 'membership_expiry'
    trigger_offset_hours INTEGER,       -- 예: 예약 24시간 전
    trigger_days_count INTEGER,         -- 예: 90일 미방문
    template_id     TEXT REFERENCES message_templates(id),
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- ============================================================
-- 동기화
-- ============================================================

-- 동기화 큐 (오프라인 → 온라인)
CREATE TABLE IF NOT EXISTS sync_queue (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type     TEXT NOT NULL,      -- 'customer','appointment','sale'...
    entity_id       TEXT NOT NULL,
    operation       TEXT NOT NULL,      -- 'create','update','delete'
    payload         TEXT NOT NULL,      -- JSON
    priority        INTEGER NOT NULL DEFAULT 5, -- 1=최고,9=최저
    status          TEXT NOT NULL DEFAULT 'pending',
                    -- 'pending','processing','synced','conflict','failed'
    retry_count     INTEGER NOT NULL DEFAULT 0,
    max_retries     INTEGER NOT NULL DEFAULT 3,
    error_message   TEXT,
    conflict_data   TEXT,               -- 충돌 시 서버 데이터
    created_at      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    processed_at    TEXT
);
CREATE INDEX IF NOT EXISTS idx_sync_status   ON sync_queue(status);
CREATE INDEX IF NOT EXISTS idx_sync_priority ON sync_queue(priority);
CREATE INDEX IF NOT EXISTS idx_sync_entity   ON sync_queue(entity_type, entity_id);

-- 디바이스 정보
CREATE TABLE IF NOT EXISTS devices (
    id          TEXT PRIMARY KEY,
    device_name TEXT NOT NULL,
    device_type TEXT NOT NULL,      -- 'ipad','iphone','mac','windows'
    last_sync   TEXT,
    is_primary  INTEGER NOT NULL DEFAULT 0,
    registered_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- ============================================================
-- 초기 마스터 데이터
-- ============================================================
INSERT OR IGNORE INTO app_versions(version, description) VALUES
    ('0.1.0', '초기 스키마 완성 — 전체 도메인 테이블 정의');

INSERT OR IGNORE INTO salon_settings(id) VALUES (1);

INSERT OR IGNORE INTO menu_categories(id,name,name_jp,sort_order) VALUES
    ('cat_cut',         '컷트',       'カット',             1),
    ('cat_color',       '컬러',       'カラー',             2),
    ('cat_perm',        '퍼머',       'パーマ',             3),
    ('cat_treatment',   '트리트먼트', 'トリートメント',       4),
    ('cat_scalp',       '두피케어',   'スカルプケア',         5),
    ('cat_extension',   '헤어익스텐션','ヘアエクステ',        6),
    ('cat_nail',        '네일',       'ネイル',             7),
    ('cat_etc',         '기타',       'その他',             8);

INSERT OR IGNORE INTO customer_tags(id,name,name_jp,color) VALUES
    ('tag_vip',         'VIP',        'VIP',                '#FFD700'),
    ('tag_caution',     '주의',       '注意',               '#FF4444'),
    ('tag_allergy',     '알레르기',   'アレルギー',           '#FF8800'),
    ('tag_pregnant',    '임산부',     '妊婦',               '#FFB6C1'),
    ('tag_new',         '신규',       '新規',               '#00B746'),
    ('tag_regular',     '단골',       '常連',               '#0064FF');

INSERT OR IGNORE INTO expense_categories(id,name,name_jp,account_code) VALUES
    ('exp_supplies',    '소모품',     '消耗品費',           '610'),
    ('exp_rent',        '임대료',     '賃借料',             '612'),
    ('exp_utilities',   '광열비',     '光熱費',             '620'),
    ('exp_advertising', '광고선전비', '広告宣伝費',          '613'),
    ('exp_equipment',   '설비',       '器具備品',           '700'),
    ('exp_training',    '교육비',     '研修費',             '621'),
    ('exp_travel',      '교통비',     '旅費交通費',          '615'),
    ('exp_misc',        '잡비',       '雑費',               '650');

INSERT OR IGNORE INTO discounts(id,name,name_jp,discount_type,discount_value) VALUES
    ('disc_staff',  '직원 할인',      'スタッフ割引',   'rate',  30),
    ('disc_intro',  '소개 할인',      '紹介割引',       'amount', 1000),
    ('disc_bday',   '생일 할인',      '誕生日割引',     'rate',  10);

INSERT OR IGNORE INTO message_templates(id,name,template_type,channel,body,body_jp) VALUES
    ('tmpl_reminder',
     '예약 리마인더',
     'reminder','sms',
     '{{고객명}}님, 내일 {{시간}} 예약이 있습니다. ☎{{전화번호}}',
     '{{お客様名}}様、明日{{時間}}にご予約がございます。☎{{電話番号}}'),
    ('tmpl_thanks',
     '감사 메시지',
     'thanks','sms',
     '{{고객명}}님, 오늘도 방문해 주셔서 감사합니다!',
     '{{お客様名}}様、本日もご来店いただきありがとうございました！'),
    ('tmpl_birthday',
     '생일 축하',
     'birthday','sms',
     '{{고객명}}님, 생일 축하드려요! 🎂 이번달 10% 할인 쿠폰을 보내드립니다.',
     '{{お客様名}}様、お誕生日おめでとうございます！🎂 今月10%割引クーポンをお送りします。');
