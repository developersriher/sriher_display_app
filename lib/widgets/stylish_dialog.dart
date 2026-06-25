import 'package:flutter/material.dart';

class StylishDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextStyle? subtitleStyle;
  final IconData icon;
  final Widget child;
  final List<Widget>? actions;
  final double width;

  const StylishDialog({
    super.key,
    required this.title,
    this.subtitle = '',
    this.subtitleStyle,
    required this.icon,
    required this.child,
    this.actions,
    this.width = 500,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String subtitle = '',
    TextStyle? subtitleStyle,
    IconData icon = Icons.info_outline_rounded,
    Widget? child,
    Widget Function(BuildContext, StateSetter)? builder,
    List<Widget>? actions,
    double? width,
    double? maxWidth,
  }) {
    final effectiveWidth = maxWidth ?? width ?? 500.0;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, childWidget) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: StatefulBuilder(
              builder: (context, setState) {
                return StylishDialog(
                  title: title,
                  subtitle: subtitle,
                  subtitleStyle: subtitleStyle,
                  icon: icon,
                  width: effectiveWidth,
                  actions: actions,
                  child: builder != null ? builder(context, setState) : (child ?? const SizedBox()),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final padding = screenHeight < 600 ? 24.0 : 32.0;

    return AlertDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      contentPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.all(16),
      content: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 50,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding * 0.6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: subtitleStyle ??
                                const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    child,
                    if (actions != null) ...[
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
