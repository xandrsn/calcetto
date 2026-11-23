import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CountdownTimerWidget extends StatefulWidget {
  final DateTime target;
  final String label;

  const CountdownTimerWidget({
    super.key,
    required this.target,
    required this.label,
  });

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    final r = widget.target.difference(DateTime.now());
    if (mounted) setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kTextMuted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$h:$m:$s',
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 20,
            color: kAccentGreen,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}
