import 'package:flutter/material.dart';
import '../models/match.dart';
import '../theme/app_theme.dart';
import '../utils/time_utils.dart';

class ActivityLogWidget extends StatelessWidget {
  final List<ActivityEvent> events;

  const ActivityLogWidget({super.key, required this.events});

  IconData _icon(String type) {
    switch (type) {
      case 'sub':
        return Icons.swap_horiz;
      case 'bet_resolved':
        return Icons.monetization_on;
      case 'steal_success':
        return Icons.style; // red card-ish
      case 'steal_fail':
        return Icons.close;
      case 'round_change':
        return Icons.emoji_events;
      case 'join':
        return Icons.star;
      default:
        return Icons.info_outline;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'steal_success':
        return kAccentRed;
      case 'steal_fail':
        return kTextMuted;
      case 'bet_resolved':
        return kAccentGreen;
      case 'round_change':
        return kAccentYellow;
      case 'join':
        return kAccentGreen;
      default:
        return kAccentBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text(
          'NO ACTIVITY YET',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kTextMuted,
          ),
        ),
      );
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: events.length,
      separatorBuilder: (_, i) => const Divider(height: 1, color: kBorder),
      itemBuilder: (ctx, i) {
        final e = events[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon(e.type), color: _color(e.type), size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.message,
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 11,
                        color: kTextPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatTimestamp(e.timestamp),
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 6,
                        color: kTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
