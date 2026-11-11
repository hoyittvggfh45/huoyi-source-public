import 'package:flutter/material.dart';

class MoyiPageBackground extends StatelessWidget {
  const MoyiPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: moyiPageGradient),
      child: child,
    );
  }
}

const Color moyiDarkCardFill = Color(0x2EFFFFFF);

const Color moyiDarkCardBorder = Color(0x59FFFFFF);

const Color moyiBodyOnDark = Color(0xB3FFFFFF);

const Color moyiMutedOnDark = Color(0x8CFFFFFF);

const Color moyiSheetFill = Color(0xFF1A0F3C);

const Color moyiSheetCardFill = Color(0x2EFFFFFF);

const LinearGradient moyiPageGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF2E1B62), Color(0xFF1A0F3C), Color(0xFF0E0724)],
  stops: [0.0, 0.55, 1.0],
);

const LinearGradient moyiPrimaryGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
);

const LinearGradient moyiSelectedGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
);

const Color moyiPurple = Color(0xFF8B5CF6);

const Color moyiPurpleDeep = Color(0xFF7C3AED);

const Color moyiPink = Color(0xFFEC4899);

const Color moyiCyan = Color(0xFF22D3EE);

const Color moyiBandTop = Color(0xFF2E1B62);

const Color moyiGold = Color(0xFFF2C14E);

BoxDecoration moyiCardDecoration({double radius = 16, Color? fill}) =>
    BoxDecoration(
      color: fill ?? Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: moyiPurple.withValues(alpha: 0.55), width: 1),
    );

const TextStyle moyiTitleStyle = TextStyle(
  fontSize: 17,
  height: 1.45,
  fontWeight: FontWeight.w700,
  color: Colors.white,
);

const TextStyle moyiGoldLineStyle = TextStyle(
  fontSize: 13,
  height: 1.5,
  fontWeight: FontWeight.w600,
  color: moyiGold,
);

class MoyiDetailBackground extends StatelessWidget {
  const MoyiDetailBackground({
    super.key,
    required this.imageUrl,
    required this.child,
  });

  final String imageUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: imageUrl.isEmpty
              ? const DecoratedBox(
                  decoration: BoxDecoration(gradient: moyiPageGradient),
                )
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const DecoratedBox(
                    decoration: BoxDecoration(gradient: moyiPageGradient),
                  ),
                ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x8C1A0F3C),
                  Color(0x401A0F3C),
                  Color(0xE60E0724),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class MoyiGradientButton extends StatelessWidget {
  const MoyiGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailing,
    this.enabled = true,
    this.height = 44,
    this.borderRadius = 14,
    this.fontSize = 14,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? trailing;
  final bool enabled;
  final double height;
  final double borderRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: active ? onPressed : null,
        child: Ink(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: active ? moyiPrimaryGradient : null,
            color: active ? null : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
