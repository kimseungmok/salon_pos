import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/router/app_router.dart';
import 'features/settings/providers/app_settings_provider.dart';
import 'shared/providers/database_provider.dart';
import 'shared/theme/app_theme.dart';

// ProviderContainer를 전역 보유 → 앱 종료 전 명시적 dispose
late final ProviderContainer _container;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // iPad 가로/세로 모두 허용
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  // 상태바 스타일
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  // ProviderContainer를 직접 생성해 수명 관리
  _container = ProviderContainer();

  // macOS 앱 종료 이벤트에서 DB를 GC보다 먼저 명시적으로 닫음
  // → sqlite3 FFI 콜백이 살아있을 때 close되므로 SIGABRT 방지
  WidgetsBinding.instance.addObserver(_AppExitObserver());

  runApp(
    UncontrolledProviderScope(
      container: _container,
      child: const SalonPosApp(),
    ),
  );
}

/// 앱 종료 직전 ProviderContainer를 dispose해 DB를 안전하게 닫는 옵저버
class _AppExitObserver extends WidgetsBindingObserver {
  bool _disposed = false;

  // ★ 핵심: db.close()는 Future<void>이므로 반드시 await해야 함
  // await 없이 호출하면 NativeDatabase.createInBackground 의 백그라운드
  // isolate가 정리되기 전에 Dart VM이 FFI 인프라를 해제 → SIGABRT
  Future<void> _closeDb() async {
    if (_disposed) return;
    _disposed = true;
    try {
      // await로 백그라운드 isolate의 sqlite3_close_v2 완료를 기다림
      await _container.read(databaseProvider).close();
    } catch (_) {}
    try {
      _container.dispose();
    } catch (_) {}
  }

  @override
  Future<ui.AppExitResponse> didRequestAppExit() async {
    // await → DB close 완료 후 exit 승인 → VM shutdown 진입
    await _closeDb();
    return ui.AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 데스크탑에서는 didRequestAppExit() 이후 detached가 오므로
    // 이미 _disposed == true이면 _closeDb()는 즉시 반환.
    // 예외 경로(강제 종료 등) 대비: microtask로 await 시도
    if (state == AppLifecycleState.detached) {
      Future.microtask(() async => await _closeDb());
    }
  }
}

class SalonPosApp extends ConsumerWidget {
  const SalonPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final textScale = settingsAsync.valueOrNull?.textScale ?? 1.0;

    return MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp.router(
        title: 'Salon POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: appRouter,

        // 일본어 로컬라이제이션
        locale: const Locale('ja', 'JP'),
        supportedLocales: const [
          Locale('ja', 'JP'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
