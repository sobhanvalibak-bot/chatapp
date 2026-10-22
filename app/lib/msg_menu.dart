import 'dart:ui';

import 'package:flutter/material.dart';

import 'utils.dart';

/// ری‌اکشن‌هایی که میشه روی پیام زد (باید با لیست سرور یکی باشه)
const List<String> kReactions = ['❤️', '💘', '💔', '😂', '😐', '😑', '🗿', '😭', '👾'];

class MsgMenuAction {
  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback onTap;
  const MsgMenuAction(this.label, this.icon, this.onTap, {this.destructive = false});
}

/// منوی پیام: بقیه‌ی صفحه تار میشه، پیام با انیمیشن میاد وسط صفحه،
/// بالاش ری‌اکشن‌ها و زیرش منوی شیشه‌ای (مثل iOS).
Future<void> showMsgMenu(
  BuildContext context, {
  required Rect rect,
  required bool mine,
  required Widget bubble,
  required List<MsgMenuAction> actions,
  required String? myReaction,
  required void Function(String emoji) onReact,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, _) => _MsgMenuPage(
        anim: anim,
        rect: rect,
        mine: mine,
        bubble: bubble,
        actions: actions,
        myReaction: myReaction,
        onReact: onReact,
      ),
    ),
  );
}

class _MsgMenuPage extends StatelessWidget {
  final Animation<double> anim;
  final Rect rect;
  final bool mine;
  final Widget bubble;
  final List<MsgMenuAction> actions;
  final String? myReaction;
  final void Function(String) onReact;

  const _MsgMenuPage({
    required this.anim,
    required this.rect,
    required this.mine,
    required this.bubble,
    required this.actions,
    required this.myReaction,
    required this.onReact,
  });

  static const double _reactH = 54;
  static const double _gap = 10;
  static const double _itemH = 50;
  static const double _sepH = 7;
  static const double _menuW = 250;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sw = mq.size.width;
    final sh = mq.size.height;
    final dark = context.dark;

    final seps = actions.where((a) => a.destructive).length;
    final menuH = actions.length * _itemH + seps * _sepH;
    final availH = sh - mq.padding.top - mq.padding.bottom - 24;
    final bubbleH = rect.height.clamp(40.0, (availH - _reactH - menuH - 2 * _gap).clamp(60.0, 4000.0)).toDouble();
    final total = _reactH + _gap + bubbleH + _gap + menuH;
    final targetTop = mq.padding.top + 12 + ((availH - total) / 2).clamp(0.0, 4000.0).toDouble();
    final targetBubbleTop = targetTop + _reactH + _gap;

    final reactW = (sw - 24).clamp(200.0, 366.0).toDouble();
    double sideLeft(double w) => (mine ? rect.right - w : rect.left).clamp(12.0, sw - 12 - w).toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(anim.value.clamp(0.0, 1.0).toDouble());
          final pop = Curves.easeOutBack.transform(anim.value.clamp(0.0, 1.0).toDouble());
          final bubbleTop = lerpDouble(rect.top, targetBubbleTop, t)!;
          final menuTop = bubbleTop + bubbleH + _gap;
          final reactTop = bubbleTop - _gap - _reactH;
          final sideAlign = mine ? Alignment.topRight : Alignment.topLeft;

          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                // پس‌زمینه‌ی تار
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16 * t, sigmaY: 16 * t),
                    child: Container(color: Colors.black.withOpacity((dark ? 0.45 : 0.28) * t)),
                  ),
                ),
                // خود پیام
                Positioned(
                  left: rect.left,
                  top: bubbleTop,
                  width: rect.width,
                  height: bubbleH,
                  child: IgnorePointer(
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: bubble,
                      ),
                    ),
                  ),
                ),
                // ری‌اکشن‌ها
                Positioned(
                  left: sideLeft(reactW),
                  top: reactTop,
                  width: reactW,
                  height: _reactH,
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * pop.clamp(0.0, 1.2).toDouble(),
                      alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft,
                      child: _glass(
                        context,
                        radius: 27,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < kReactions.length; i++) _emoji(context, kReactions[i], i),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // منوی شیشه‌ای
                Positioned(
                  left: sideLeft(_menuW),
                  top: menuTop,
                  width: _menuW,
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.82 + 0.18 * t,
                      alignment: sideAlign,
                      child: _glass(
                        context,
                        radius: 24,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < actions.length; i++) ..._item(context, i),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emoji(BuildContext context, String e, int i) {
    final on = myReaction != null && myReaction!.replaceAll('\uFE0F', '') == e.replaceAll('\uFE0F', '');
    final s = Curves.easeOutBack.transform(((anim.value * 1.5) - i * 0.07).clamp(0.0, 1.0).toDouble());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        onReact(e);
      },
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? tgBlue.withOpacity(0.35) : Colors.transparent,
        ),
        child: Transform.scale(scale: s, child: Text(e, style: const TextStyle(fontSize: 26))),
      ),
    );
  }

  List<Widget> _item(BuildContext context, int i) {
    final a = actions[i];
    final dark = context.dark;
    final color = a.destructive ? const Color(0xFFFF5A52) : (dark ? Colors.white : Colors.black87);
    return [
      if (a.destructive && i > 0)
        Container(height: _sepH, color: dark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.10))
      else if (i > 0)
        Divider(height: 1, thickness: 0.6, color: dark ? Colors.white12 : Colors.black12),
      InkWell(
        onTap: () {
          Navigator.of(context).pop();
          a.onTap();
        },
        child: SizedBox(
          height: _itemH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: Text(a.label, style: TextStyle(fontSize: 18, color: color))),
                Icon(a.icon, size: 22, color: color),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _glass(BuildContext context, {required double radius, required Widget child}) {
    final dark = context.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xCC3A3550), Color(0xCC2A3A4C), Color(0xCC4A3430)]
                  : const [Color(0xDDEFE4F0), Color(0xDDDDEBF0), Color(0xDDF2E3E0)],
            ),
            border: Border.all(color: dark ? Colors.white10 : Colors.white54, width: 0.8),
          ),
          child: child,
        ),
      ),
    );
  }
}
