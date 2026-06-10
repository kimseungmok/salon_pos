-- ============================================================
-- Salon POS — Database Init
-- 실행 순서: 00 → 01 → 02 → 03 → 04 → 05 → 06 → 07
-- ============================================================
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA cache_size = -64000;   -- 64MB
PRAGMA temp_store = MEMORY;
PRAGMA synchronous = NORMAL;  -- WAL 모드에서 안전 + 성능 균형
