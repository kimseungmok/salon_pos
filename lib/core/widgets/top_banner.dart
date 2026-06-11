import 'package:flutter/material.dart';

// ─── 화면 상단 중앙에서 내려오는 Alert 배너 ─────────────────────────────────
// 사용법:
//   showTopBanner(context, '削除しました', actionLabel: '元に戻す', onAction: ...);

class _TopBannerWidget extends StatefulWidget {
  const _TopBannerWidget({
    required this.message,
    required this.color,
    required this.icon,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fade,
        child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(10),
                    shadowColor: Colors.black26,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _dismiss,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: widget.color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.icon, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                widget.message,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (widget.actionLabel != null) ...[
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  widget.onAction?.call();
                                  _dismiss();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.5)),
                                  ),
                                  child: Text(
                                    widget.actionLabel!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ),
    );
  }
}

OverlayEntry? _currentBannerEntry;


void showTopBanner(
  BuildContext context,
  String message, {
  Color color = const Color(0xFFF59E0B), // warning amber
  IconData icon = Icons.warning_rounded,
  Duration duration = const Duration(seconds: 6),
  String? actionLabel,
  VoidCallback? onAction,
  bool persistent = false, // true = 自動で消えない (手動 dismissTopBanner 必要)
}) {
  // 기존 배너가 있으면 먼저 제거
  _currentBannerEntry?.remove();
  _currentBannerEntry = null;

  final overlay = Navigator.of(context, rootNavigator: true).overlay ?? Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (_) => _TopBannerWidget(
      message: message,
      color: color,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismiss: () {
        if (_currentBannerEntry == entry) _currentBannerEntry = null;
        try { entry.remove(); } catch (_) {}
      },
    ),
  );

  _currentBannerEntry = entry;
  overlay.insert(entry);

  if (!persistent) {
    Future.delayed(duration, () {
      if (_currentBannerEntry == entry) {
        _currentBannerEntry = null;
        try { entry.remove(); } catch (_) {}
      }
    });
  }
}

/// 現在表示中のバナーを強制 dismiss (persistent バナー用)
void dismissTopBanner() {
  try { _currentBannerEntry?.remove(); } catch (_) {}
  _currentBannerEntry = null;
}
