import 'package:flutter/material.dart';

// ─── 토스플레이스 기반 컬러 시스템 ───────────────────────────────────────
class AppColors {
  AppColors._();

  // Primary
  static const primary = Color(0xFF0064FF);
  static const primaryLight = Color(0xFFE8F1FF);
  static const primaryDark = Color(0xFF0050CC);

  // Status
  static const success = Color(0xFF00B746);
  static const successLight = Color(0xFFE6F9EE);
  static const warning = Color(0xFFF5A623);
  static const warningLight = Color(0xFFFFF8ED);
  static const error = Color(0xFFF04452);
  static const errorLight = Color(0xFFFFECEE);

  // Neutral
  static const background = Color(0xFFF5F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E8ED);
  static const divider = Color(0xFFF2F4F6);

  // Text
  static const textPrimary = Color(0xFF191F28);
  static const textSecondary = Color(0xFF8B95A1);
  static const textDisabled = Color(0xFFC4CAD4);
  static const textOnPrimary = Color(0xFFFFFFFF);

  // 예약 상태 컬러
  static const statusPending    = Color(0xFFF59E0B); // 未確認 — 황색
  static const statusConfirmed  = Color(0xFF0064FF); // 確認済 — 파랑
  static const statusInProgress = Color(0xFF00B746); // 施術中 — 초록
  static const statusProcessing = Color(0xFF86EFAC); // 発色中 — 연초록
  static const statusCompleted  = Color(0xFF8B95A1); // 完了   — 회색
  static const statusNoShow     = Color(0xFFF04452); // 無断   — 빨강
  static const statusCancelled  = Color(0xFFE5E8ED); // キャンセル — 연회색

  // 로열티 티어 컬러
  static const tierBronze   = Color(0xFFCD7F32);
  static const tierSilver   = Color(0xFF9EA5AD);
  static const tierGold     = Color(0xFFF59E0B);
  static const tierPlatinum = Color(0xFF6366F1);

  // 스태프 알림 컬러
  static const alertInfo    = Color(0xFF0064FF);
  static const alertWarning = Color(0xFFF59E0B);
  static const alertDanger  = Color(0xFFF04452);

  // Category colors (캘린더/스태프 색상)
  static const staffColors = [
    Color(0xFF0064FF), // 파랑
    Color(0xFF00B746), // 초록
    Color(0xFFFF6B35), // 주황
    Color(0xFF9B5CDB), // 보라
    Color(0xFFFF4E8C), // 핑크
    Color(0xFF00BFAE), // 청록
    Color(0xFFFFB300), // 노랑
    Color(0xFF8D6E63), // 브라운
  ];
}

// ─── 텍스트 스타일 ────────────────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  static const _base = TextStyle(
    fontFamily: 'NotoSansJP',
    color: AppColors.textPrimary,
    letterSpacing: 0,
  );

  static final h1 = _base.copyWith(fontSize: 26, fontWeight: FontWeight.w700);
  static final h2 = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w700);
  static final h3 = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600);
  static final h4 = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

  static final body1 = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400);
  static final body2 = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400);
  static final caption = _base.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textSecondary);

  // 금액 전용 (크고 굵게)
  static final price = _base.copyWith(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    fontFeatures: [const FontFeature.tabularFigures()],
  );
  static final priceMedium = _base.copyWith(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    fontFeatures: [const FontFeature.tabularFigures()],
  );
  static final priceSmall = _base.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontFeatures: [const FontFeature.tabularFigures()],
  );

  static final button = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600);
  static final label = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500);
}

// ─── 앱 테마 ──────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSansJP',
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: AppColors.textOnPrimary,
          secondary: AppColors.primary,
          surface: AppColors.surface,
          error: AppColors.error,
          outline: AppColors.border,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: AppColors.border,
          titleTextStyle: TextStyle(
            fontFamily: 'NotoSansJP',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: AppTextStyles.button,
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 44),
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: AppTextStyles.button,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: AppTextStyles.button,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          hintStyle: AppTextStyles.body1.copyWith(color: AppColors.textDisabled),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
          space: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.background,
          labelStyle: AppTextStyles.label,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
        ),
      );
}

// ─── 공통 상수 ────────────────────────────────────────────────────────────
class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class AppRadius {
  AppRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 999.0;
}
