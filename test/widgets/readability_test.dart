import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calcetto/models/daily.dart';
import 'package:calcetto/models/league.dart';
import 'package:calcetto/models/powerup_card.dart';
import 'package:calcetto/services/card_images.dart';
import 'package:calcetto/widgets/bet_card.dart';
import 'package:calcetto/widgets/leaderboard_widget.dart';
import 'package:calcetto/widgets/league_table.dart';
import 'package:calcetto/widgets/pixel_card_widget.dart';

TeamStanding _s(String team, int p, int w, int d, int l, int gf, int ga) {
  final g = TeamStanding(team);
  g.p = p;
  g.w = w;
  g.d = d;
  g.l = l;
  g.gf = gf;
  g.ga = ga;
  return g;
}

/// The two global text scales the app pins (see main.dart): 1.6 on desktop,
/// 1.85 on Android. Every dense fixed-column widget must fit at BOTH inside a
/// phone column, so the readability scale-up never breaks tight layouts.
const _scales = [1.6, 1.85];

void main() {
  testWidgets('league table fits at both text scales', (tester) async {
    final rows = [
      _s('Real Madrid', 3, 3, 0, 0, 9, 1),
      _s('Barcelona', 3, 1, 1, 1, 4, 4),
      _s('Athletic Bilbao', 3, 1, 0, 2, 2, 6),
      _s('Rayo Vallecano', 3, 0, 1, 2, 1, 5),
    ];

    for (final scale in _scales) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 430, // full phone column
                  child: LeagueTable(rows: rows),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'table at $scale');
      expect(find.text('Real Madrid'), findsOneWidget);
    }
  });

  testWidgets('power-up card fits (no overflow) at both scales, 3-up width', (
    tester,
  ) async {
    // ~3 cards across a 430px column → ~138px each; test a narrow case too.
    for (final scale in _scales) {
      for (final w in [110.0, 138.0]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cardImagesProvider.overrideWith((ref) async => <String, String>{}),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Center(
                    child: PixelCardWidget(
                      card: PowerupCard.ofType(CardType.francotirador),
                      width: w,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'card overflow at w=$w, scale=$scale',
        );
      }
    }
  });

  testWidgets('bet card fits at both scales in a phone column', (tester) async {
    for (final scale in _scales) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 430,
                  child: BetCard(
                    bet: const Bet(
                      id: 'b1',
                      matchId: 'm1',
                      question: '¿El árbitro saca 5+ amarillas en un partidazo?',
                      options: ['SI', 'NO', 'EMPATE'],
                      answer: null,
                    ),
                    locked: false,
                    optionOdds: const {'SI': 40, 'NO': 35, 'EMPATE': 25},
                    onSelect: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'bet card at $scale');
    }
  });

  testWidgets('tab-strip app bar fits at both scales (no overflow)', (
    tester,
  ) async {
    // Mirrors the MI 11 / PARTIDOS app bar: a 2px divider + a tab strip inside
    // a fixed-height PreferredSize. Regression guard for the overflow caused by
    // sizing it too tightly.
    for (final scale in _scales) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  toolbarHeight: 0,
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(42),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(color: const Color(0xFF000000), height: 2),
                        const TabBar(
                          labelStyle: TextStyle(fontSize: 9),
                          tabs: [
                            Tab(height: 34, text: 'JORNADA'),
                            Tab(height: 34, text: 'PLANTILLA'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                body: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'tab strip at $scale');
    }
  });

  testWidgets('leaderboard row fits at both scales', (tester) async {
    final users = {
      'UnNombreDeUsuarioLargo': {
        'points': {
          'total': 12345.6,
          'breakdown': {'squad': 100, 'bets': 50, 'quiniela': 200},
        },
      },
    };
    for (final scale in _scales) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SizedBox(
                width: 430,
                child: LeaderboardWidget(
                  allUsers: users,
                  currentUser: 'UnNombreDeUsuarioLargo',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'leaderboard at $scale');
    }
  });
}
