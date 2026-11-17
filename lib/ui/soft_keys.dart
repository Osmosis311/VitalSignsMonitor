import 'package:flutter/material.dart';

import 'theme.dart';

class SoftKey {
  const SoftKey(this.label, this.icon, this.onTap, {this.lit = false, this.warn = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Shown pressed-in: the function is currently on.
  final bool lit;

  /// Lit in the alarm colour instead of the neutral one.
  final bool warn;
}

/// The row of on-screen keys along the bottom edge. When there are more
/// keys than fit, the last position becomes a "More" key that pages through
/// them.
class SoftKeyBar extends StatefulWidget {
  const SoftKeyBar({super.key, required this.keys, required this.height});
  final List<SoftKey> keys;
  final double height;

  @override
  State<SoftKeyBar> createState() => _SoftKeyBarState();
}

class _SoftKeyBarState extends State<SoftKeyBar> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final minWidth = widget.height < 52 ? 80.0 : 84.0 * s;
        final fit = (box.maxWidth / minWidth).floor().clamp(4, 99);
        var keys = widget.keys;
        if (keys.length > fit) {
          final per = fit - 1;
          final pages = (keys.length / per).ceil();
          final page = _page % pages;
          final slice = keys.skip(page * per).take(per).toList();
          keys = [
            ...slice,
            SoftKey('More ${page + 1}/$pages', Icons.chevron_right, () => setState(() => _page = page + 1)),
          ];
        }
        return Container(
          height: widget.height,
          padding: EdgeInsets.all(3 * s),
          decoration: const BoxDecoration(
            color: MC.bar,
            border: Border(top: BorderSide(color: MC.barLine)),
          ),
          child: Row(
            children: [
              for (final k in keys)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 1.5 * s),
                    child: _Key(k, widget.height - 6 * s),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Key extends StatefulWidget {
  const _Key(this.k, this.h);
  final SoftKey k;
  final double h;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final k = widget.k;
    final on = k.lit;
    final fg = on ? Colors.black : MC.text;
    final top = on ? (k.warn ? MC.alarmYellow : MC.keyOn) : (_down ? MC.keyLo : MC.keyHi);
    final bottom = on ? (k.warn ? const Color(0xFFD8B800) : const Color(0xFF8FA9BF)) : (_down ? MC.key : MC.keyLo);
    final wide = widget.h < 46;
    final icon = Icon(k.icon, size: widget.h * (wide ? 0.5 : 0.4), color: fg);
    final text = Text(
      k.label,
      maxLines: wide ? 1 : 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.clip,
      softWrap: !wide,
      style: labelStyle((widget.h * 0.2).clamp(9.0, 15.0), fg, weight: 600, width: 82),
    );
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: k.onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
          borderRadius: BorderRadius.circular(4 * s),
          border: Border.all(color: _down ? MC.keyOn : const Color(0xFF6B7F92), width: 1),
        ),
        padding: EdgeInsets.symmetric(horizontal: 2 * s),
        alignment: Alignment.center,
        child: wide
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    SizedBox(width: 4 * s),
                    text,
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  SizedBox(height: 1.5 * s),
                  FittedBox(fit: BoxFit.scaleDown, child: text),
                ],
              ),
      ),
    );
  }
}
