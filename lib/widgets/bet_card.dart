import 'package:flutter/material.dart';
import '../models/daily.dart';
import '../theme/app_theme.dart';

class BetCard extends StatelessWidget {
  final Bet bet;
  final DailyMatch? match;
  final String? selectedOption;
  final bool locked;
  final Map<String, double> optionOdds;
  final Function(String option) onSelect;

  const BetCard({
    super.key,
    required this.bet,
    this.match,
    this.selectedOption,
    required this.locked,
    required this.optionOdds,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (match != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF0FDF4),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sports_soccer, size: 12, color: kAccentGreen),
                  const SizedBox(width: 6),
                  Text(
                    '${match!.home}  ·  ${match!.away}',
                    style: const TextStyle(
                      fontFamily: kFontUI,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kAccentGreen,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text(
              bet.question,
              style: const TextStyle(
                fontFamily: kFontBody,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kTextPrimary,
                height: 1.4,
              ),
            ),
          ),
          const Divider(height: 1, color: kBorder),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: bet.options.map((opt) {
                final isSelected = selectedOption == opt;
                final isCorrect = bet.answer == opt;
                final isWrong =
                    bet.answer != null && opt != bet.answer && isSelected;
                final pct = optionOdds[opt] ?? 0.0;

                Color borderColor = kBorder;
                Color bgColor = kSurface2;
                if (bet.answer != null) {
                  if (isCorrect) {
                    borderColor = kAccentGreen;
                    bgColor = const Color(0xFFDCFCE7);
                  } else if (isWrong) {
                    borderColor = kAccentRed;
                    bgColor = const Color(0xFFFEE2E2);
                  }
                } else if (isSelected) {
                  borderColor = kAccentGreen;
                  bgColor = const Color(0xFFDCFCE7);
                }

                return GestureDetector(
                  onTap: locked ? null : () => onSelect(opt),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            opt,
                            style: TextStyle(
                              fontFamily: kFontBody,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isWrong
                                  ? kAccentRed
                                  : isCorrect
                                  ? kAccentGreen
                                  : kTextPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontFamily: kFontBody,
                            fontSize: 12,
                            color: kTextMuted,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Icon(
                            isWrong ? Icons.close : Icons.check,
                            color: isWrong ? kAccentRed : kAccentGreen,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (bet.answer != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: kAccentGreen, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'RESPUESTA: ${bet.answer}',
                    style: const TextStyle(
                      fontFamily: kFontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kAccentGreen,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
