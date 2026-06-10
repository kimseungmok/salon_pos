import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── 앱 전체 설정 상태 ──────────────────────────────────────────────────────
class AppSettings {
  const AppSettings({
    this.textScale = 1.0,
    this.calendarStartHour = 9,
    this.calendarEndHour = 21,
  });

  final double textScale;       // 0.80 ~ 1.20
  final int calendarStartHour;  // 0 ~ 23
  final int calendarEndHour;    // 1 ~ 24

  AppSettings copyWith({
    double? textScale,
    int? calendarStartHour,
    int? calendarEndHour,
  }) =>
      AppSettings(
        textScale: textScale ?? this.textScale,
        calendarStartHour: calendarStartHour ?? this.calendarStartHour,
        calendarEndHour: calendarEndHour ?? this.calendarEndHour,
      );
}

// ─── Notifier ────────────────────────────────────────────────────────────────
class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _keyTextScale = 'app_text_scale';
  static const _keyCalendarStart = 'calendar_start_hour';
  static const _keyCalendarEnd = 'calendar_end_hour';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble(_keyTextScale) ?? 1.0;
    final startHour = prefs.getInt(_keyCalendarStart) ?? 9;
    final endHour = prefs.getInt(_keyCalendarEnd) ?? 21;
    return AppSettings(
      textScale: scale.clamp(0.80, 1.20),
      calendarStartHour: startHour.clamp(0, 23),
      calendarEndHour: endHour.clamp(1, 24),
    );
  }

  Future<void> setTextScale(double scale) async {
    final clamped = scale.clamp(0.80, 1.20);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTextScale, clamped);
    state = AsyncData((state.valueOrNull ?? const AppSettings())
        .copyWith(textScale: clamped));
  }

  Future<void> setCalendarHours(int startHour, int endHour) async {
    final s = startHour.clamp(0, 22);
    final e = endHour.clamp(s + 1, 24);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCalendarStart, s);
    await prefs.setInt(_keyCalendarEnd, e);
    state = AsyncData((state.valueOrNull ?? const AppSettings())
        .copyWith(calendarStartHour: s, calendarEndHour: e));
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
        AppSettingsNotifier.new);
