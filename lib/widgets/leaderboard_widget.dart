import 'package:flutter/material.dart';
import '../models/user_data.dart';
import '../theme/app_theme.dart';
import '../utils/time_utils.dart';
import 'pixel_button.dart';

class LeaderboardWidget extends StatefulWidget {
  final Map<String, dynamic> allUsers;
  final String? currentUser;
  final void Function(String username)? onViewTeam;
  final Map<String, String>? playerNames;

  const LeaderboardWidget({
    super.key,
    required this.allUsers,
    this.currentUser,
    this.onViewTeam,
    this.playerNames,
  });

  @override
  State<LeaderboardWidget> createState() => _LeaderboardWidgetState();
}

class _LeaderboardWidgetState extends State<LeaderboardWidget> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final today = todayString();
    final entries = widget.allUsers.entries.map((e) {
      final data = e.value as Map<String, dynamic>;
      final pts = UserPoints.fromJson(
        data['points'] as Map<String, dynamic>? ?? {},
      );
      final cpRaw = data['captain_picks'] as Map<String, dynamic>? ?? {};
      final captainId = cpRaw[today] as String?;
      final captainName = captainId != null
          ? (widget.playerNames?[captainId] ?? captainId)
          : null;
      return (key: e.key, pts: pts, captainName: captainName);
    }).toList()..sort((a, b) => b.pts.total.compareTo(a.pts.total));

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final username = entries[i].key;
        final pts = entries[i].pts;
        final captainName = entries[i].captainName;
        final isMe = username == widget.currentUser;
        final expanded = _expanded.contains(username);

        return Column(
          children: [
            GestureDetector(
              onTap: () => setState(() {
                if (expanded) {
                  _expanded.remove(username);
                } else {
                  _expanded.add(username);
                }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isMe
                      ? kAccentYellow.withValues(alpha: 0.15)
                      : kSurface,
                  border: Border(
                    bottom: const BorderSide(color: kBorder, width: 1),
                    left: BorderSide(
                      color: isMe ? kAccentYellow : kBorder,
                      width: isMe ? 3 : 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '#${i + 1}',
                        style: TextStyle(
                          fontFamily: 'ChakraPetch',
                          fontSize: 12,
                          color: i == 0
                              ? kAccentYellow
                              : i == 1
                              ? kTextPrimary
                              : kTextMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        username.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'ChakraPetch',
                          fontSize: 12,
                          color: isMe ? kAccentYellow : kTextPrimary,
                        ),
                      ),
                    ),
                    Text(
                      pts.total.toStringAsFixed(1),
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 14,
                        color: kAccentGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: kTextMuted,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Container(
                color: kSurface2,
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (captainName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Text(
                              '★ CAPITAN',
                              style: TextStyle(
                                fontFamily: 'ChakraPetch',
                                fontSize: 11,
                                color: kAccentYellow,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                captainName,
                                style: const TextStyle(
                                  fontFamily: 'ChakraPetch',
                                  fontSize: 11,
                                  color: kTextPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    _row('EQUIPO', pts.squad),
                    _row('APUESTAS', pts.bets),
                    _row('QUINIELA', pts.quiniela),
                    _row('PICHICHI', pts.goldenBoot),
                    _row('CARTAS', pts.cards),
                    if (widget.onViewTeam != null) ...[
                      const SizedBox(height: 8),
                      PixelButton(
                        label: 'VER EQUIPO',
                        onTap: () => widget.onViewTeam!(username),
                        color: kAccentGreen,
                        fontSize: 11,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _row(String label, double val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 11,
              color: kTextMuted,
            ),
          ),
        ),
        Text(
          val.toStringAsFixed(1),
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kTextPrimary,
          ),
        ),
      ],
    ),
  );
}
