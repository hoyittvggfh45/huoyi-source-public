import 'package:flutter/material.dart';

import 'kotv_page.dart';

abstract final class KotvTokens {
  static const Color primary = Color(0xFFE75480);
  static const Color background = Color(0xFFFDF3F6);
  static const Color cardColor = Colors.white;
  static const Color unselectedColor = Color(0xFF8A8A93);
  static const Color pastelBlue = Color(0xFF8EA8FF);
  static const double cardRadius = 20;
  static const double capsuleRadius = 999;
}

class KotvPastelBackground extends StatelessWidget {
  const KotvPastelBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KotvTokens.background,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KotvTokens.primary.withValues(alpha: 0.14),
              ),
            ),
          ),
          Positioned(
            left: -80,
            bottom: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KotvTokens.pastelBlue.withValues(alpha: 0.14),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class KotvGroupCard extends StatelessWidget {
  const KotvGroupCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: KotvTokens.cardColor,
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class KotvSettingsRow extends StatelessWidget {
  const KotvSettingsRow({
    super.key,
    required this.title,
    this.value,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (trailing != null)
                trailing!
              else if (value != null)
                Flexible(
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: KotvTokens.unselectedColor,
                    ),
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: KotvTokens.unselectedColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showKotvOptionDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T current,
  required String Function(T) label,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final option in options)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(dialogContext).pop(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label(option),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          if (option == current)
                            const Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: KotvTokens.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

class KotvBottomBar extends StatelessWidget {
  const KotvBottomBar({
    super.key,
    required this.pages,
    required this.current,
    required this.onSelect,
  });

  final List<KotvPage> pages;
  final KotvPage current;
  final ValueChanged<KotvPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFFE8E8EC), width: 0.5),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68, maxHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  for (final page in pages)
                    Expanded(
                      child: InkWell(
                        onTap: () => onSelect(page),
                        borderRadius: BorderRadius.circular(
                          KotvTokens.capsuleRadius,
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: page == current
                                ? KotvTokens.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              KotvTokens.capsuleRadius,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                page == current
                                    ? page.selectedIcon
                                    : page.icon,
                                size: 22,
                                color: page == current
                                    ? Colors.white
                                    : KotvTokens.unselectedColor,
                              ),
                              if (pages.length <= 6) ...[
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    page.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: page == current
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: page == current
                                          ? Colors.white
                                          : KotvTokens.unselectedColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
