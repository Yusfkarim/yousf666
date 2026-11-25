import 'package:flutter/material.dart';

class ClayColors {
  static const canvas = Color(0xFFF7F2E8);
  static const ivory = Color(0xFFFBF8F3);
  static const peach = Color(0xFFFCEEE1);
  static const inset = Color(0xFFF2EAE0);
  static const orange = Color(0xFFF97316);
  static const orangeDeep = Color(0xFFEA580C);
  static const espresso = Color(0xFF2D221B);
  static const taupe = Color(0xFF7A6A5E);
  static const green = Color(0xFF16A34A);
  static const mint = Color(0xFF4ADE80);
  static const lavender = Color(0xFFA78BFA);
  static const coral = Color(0xFFEF4444);
  static const line = Color(0xFFE9DCCF);
}

extension ClayContextColors on BuildContext {
  bool get isClayDark => Theme.of(this).brightness == Brightness.dark;
  Color get clayText => isClayDark ? const Color(0xFFFFF4E7) : ClayColors.espresso;
  Color get clayMuted => isClayDark ? const Color(0xFFB7A393) : ClayColors.taupe;
  Color get clayAccent => isClayDark ? const Color(0xFFFFA15C) : ClayColors.orangeDeep;
  Color get claySoftSurface => isClayDark ? const Color(0xFF392A20) : ClayColors.peach;
  Color get clayPageSurface => isClayDark ? const Color(0xFF211A15) : ClayColors.canvas;
  Color get clayPositive => isClayDark ? const Color(0xFF4ADE80) : ClayColors.green;
  Color get clayNegative => isClayDark ? const Color(0xFFFCA5A5) : ClayColors.coral;
  Color get clayPositiveSurface => isClayDark ? const Color(0xFF20372A) : const Color(0xFFE5F8EA);
  Color get clayNegativeSurface => isClayDark ? const Color(0xFF3A2522) : const Color(0xFFFCE2DF);
}

enum ClayTone { orange, green, mint, lavender, coral, neutral }

class ClayCard extends StatelessWidget {
  const ClayCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = 24,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? const [Color(0xFF3A2B22), Color(0xFF2B211B)] : const [Colors.white, ClayColors.ivory],
        ),
        border: Border.all(color: dark ? const Color(0xFF594638) : Colors.white.withOpacity(.9), width: 1.2),
        boxShadow: dark ? const [
          BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 9)),
          BoxShadow(color: Color(0x335C4634), blurRadius: 4, offset: Offset(-2, -2)),
        ] : const [
          BoxShadow(color: Color(0x1F8C6D4F), blurRadius: 18, offset: Offset(0, 9)),
          BoxShadow(color: Color(0x99FFFFFF), blurRadius: 4, offset: Offset(-2, -2)),
          BoxShadow(color: Color(0x0D6C442B), blurRadius: 2, offset: Offset(1, 2)),
        ],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

class ClayInsetContainer extends StatelessWidget {
  const ClayInsetContainer({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    this.radius = 18,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF34271F), Color(0xFF2A201A)]
              : [color ?? ClayColors.peach, ClayColors.inset.withOpacity(.72)],
        ),
        border: Border.all(color: dark ? const Color(0xFF4B392C) : Colors.white.withOpacity(.82), width: 1.2),
        boxShadow: dark ? const [
          BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3)),
          BoxShadow(color: Color(0x223D3027), blurRadius: 4, offset: Offset(-1, -1)),
        ] : const [
          BoxShadow(color: Color(0x148C6D4F), blurRadius: 6, offset: Offset(0, 3)),
          BoxShadow(color: Color(0x80FFFFFF), blurRadius: 4, offset: Offset(-1, -1)),
        ],
      ),
      child: child,
    );
  }
}

class ClayPillButton extends StatefulWidget {
  const ClayPillButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.tone = ClayTone.orange,
    this.compact = false,
    this.expand = false,
    this.textStyle,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ClayTone tone;
  final bool compact;
  final bool expand;
  final TextStyle? textStyle;

  @override
  State<ClayPillButton> createState() => _ClayPillButtonState();
}

class _ClayPillButtonState extends State<ClayPillButton> {
  bool _pressed = false;

  List<Color> get _colors => switch (widget.tone) {
        ClayTone.orange => const [Color(0xFFFF9A58), Color(0xFFF97316), Color(0xFFEA580C)],
        ClayTone.green => const [Color(0xFF4ADE80), Color(0xFF22C55E), Color(0xFF16A34A)],
        ClayTone.mint => const [Color(0xFF86EFAC), Color(0xFF4ADE80)],
        ClayTone.lavender => const [Color(0xFFDDD6FE), Color(0xFFA78BFA), Color(0xFF8B5CF6)],
        ClayTone.coral => const [Color(0xFFFCA5A5), Color(0xFFF87171), Color(0xFFEF4444)],
        ClayTone.neutral => const [Colors.white, ClayColors.ivory],
      };

  Color get _glow => switch (widget.tone) {
        ClayTone.orange => const Color(0x55F97316),
        ClayTone.green || ClayTone.mint => const Color(0x4422C55E),
        ClayTone.lavender => const Color(0x448B5CF6),
        ClayTone.coral => const Color(0x44EF4444),
        ClayTone.neutral => const Color(0x1F8C6D4F),
      };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = widget.tone == ClayTone.neutral
        ? (dark ? const Color(0xFFFFF4E7) : ClayColors.espresso)
        : Colors.white;
    final buttonColors = widget.tone == ClayTone.neutral && dark
        ? const [Color(0xFF4A392D), Color(0xFF35271E)]
        : _colors;
    final child = Container(
      width: widget.expand ? double.infinity : null,
      constraints: BoxConstraints(minHeight: widget.compact ? 40 : 48),
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 20, vertical: widget.compact ? 8 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: buttonColors,
          stops: buttonColors.length == 3 ? const [0, .48, 1] : null,
        ),
        border: Border.all(color: Colors.white.withOpacity(.88), width: 1.3),
        boxShadow: [
          BoxShadow(color: _glow, blurRadius: 13, offset: const Offset(0, 6)),
          const BoxShadow(color: Color(0xAAFFFFFF), blurRadius: 3, offset: Offset(-1, -2)),
          const BoxShadow(color: Color(0x176A3917), blurRadius: 2, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, color: foreground, size: widget.compact ? 17 : 19),
            const SizedBox(width: 7),
          ],
          Text(
            widget.label,
            style: widget.textStyle ?? TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: widget.compact ? 13 : 14,
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      onTapDown: widget.onPressed == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: widget.onPressed == null
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            },
      child: AnimatedScale(
        scale: _pressed ? .95 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutBack,
        child: Opacity(opacity: widget.onPressed == null ? .55 : 1, child: child),
      ),
    );
  }
}

class ClayIconBadge extends StatelessWidget {
  const ClayIconBadge({
    required this.icon,
    super.key,
    this.size = 46,
    this.radius,
    this.tone = ClayTone.orange,
    this.iconSize,
  });

  final IconData icon;
  final double size;
  final double? radius;
  final ClayTone tone;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = switch (tone) {
      ClayTone.orange => const [Color(0xFFFFAA70), Color(0xFFF97316)],
      ClayTone.green => const [Color(0xFF86EFAC), Color(0xFF22C55E)],
      ClayTone.mint => const [Color(0xFFD1FAE5), Color(0xFF86EFAC)],
      ClayTone.lavender => const [Color(0xFFEDE9FE), Color(0xFFC4B5FD)],
      ClayTone.coral => const [Color(0xFFFEE2E2), Color(0xFFFCA5A5)],
      ClayTone.neutral => isDark ? const [Color(0xFF4A392D), Color(0xFF35271E)] : const [Colors.white, ClayColors.peach],
    };
    final darkTone = tone == ClayTone.orange || tone == ClayTone.green;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? size * .34),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: Border.all(color: isDark ? const Color(0xFF604A39) : Colors.white.withOpacity(.9), width: 1.3),
        boxShadow: isDark ? const [
          BoxShadow(color: Color(0x66000000), blurRadius: 9, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x225C4634), blurRadius: 3, offset: Offset(-1, -2)),
        ] : const [
          BoxShadow(color: Color(0x1F8C6D4F), blurRadius: 9, offset: Offset(0, 4)),
          BoxShadow(color: Color(0xAAFFFFFF), blurRadius: 3, offset: Offset(-1, -2)),
        ],
      ),
      child: Icon(
        icon,
        size: iconSize ?? size * .47,
        color: darkTone ? Colors.white : (isDark && tone == ClayTone.neutral ? const Color(0xFFFFF4E7) : ClayColors.orangeDeep),
      ),
    );
  }
}

class ClayNavItem {
  const ClayNavItem({required this.label, required this.icon, required this.path});
  final String label;
  final IconData icon;
  final String path;
}

class FloatingClayNavBar extends StatelessWidget {
  const FloatingClayNavBar({
    required this.items,
    required this.currentPath,
    required this.onSelect,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    super.key,
  });

  final List<ClayNavItem> items;
  final String currentPath;
  final ValueChanged<String> onSelect;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: ClayCard(
          radius: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _NavButton(
                    item: item,
                    active: currentPath == item.path || currentPath.startsWith('${item.path}/'),
                    onTap: () => onSelect(item.path),
                  ),
                ),
              const SizedBox(width: 7),
              ClayPillButton(
                label: actionLabel,
                icon: actionIcon,
                compact: true,
                onPressed: onAction,
              ),
            ],
          ),
        ),
      );
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onTap});
  final ClayNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClayIconBadge(
                icon: item.icon,
                size: 34,
                radius: 13,
                tone: active ? ClayTone.mint : ClayTone.neutral,
                iconSize: 18,
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? context.clayAccent : context.clayMuted,
                ),
              ),
            ],
          ),
        ),
      );
}
