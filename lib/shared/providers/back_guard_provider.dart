import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 미저장 변경사항이 있을 때 true.
/// 설정 서브화면에서 편집 시 true, 저장 완료 또는 화면 이탈 시 false.
final hasUnsavedChangesProvider = StateProvider<bool>((_) => false);
