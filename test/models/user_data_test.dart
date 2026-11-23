import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/user_data.dart';

void main() {
  group('UserData.captainFor', () {
    UserData userWith({
      Map<String, String?> picks = const {},
      String? activeCaptain,
    }) {
      return UserData.empty('alice').copyWith(
        captainPicks: picks,
        active: ActiveState(captain: activeCaptain),
      );
    }

    test('prefers the explicit pick for today', () {
      final u = userWith(
        picks: {'2026-06-11': 'pedri', '2026-06-10': 'gavi'},
        activeCaptain: 'mbappe',
      );
      expect(
        u.captainFor(today: '2026-06-11', matchdayDate: '2026-06-10'),
        'pedri',
      );
    });

    test('falls back to the matchday pick when today has none', () {
      final u = userWith(
        picks: {'2026-06-10': 'gavi'},
        activeCaptain: 'mbappe',
      );
      expect(
        u.captainFor(today: '2026-06-11', matchdayDate: '2026-06-10'),
        'gavi',
      );
    });

    test('falls back to the server-mirrored active captain', () {
      final u = userWith(picks: {}, activeCaptain: 'mbappe');
      expect(
        u.captainFor(today: '2026-06-11', matchdayDate: '2026-06-10'),
        'mbappe',
      );
    });

    test('returns null when no captain is set anywhere', () {
      final u = userWith();
      expect(u.captainFor(today: '2026-06-11'), isNull);
    });

    test('ignores matchday date when not provided', () {
      final u = userWith(picks: {'2026-06-10': 'gavi'});
      expect(u.captainFor(today: '2026-06-11'), isNull);
    });
  });

  group('UserData.forceLogout', () {
    test('defaults to false and round-trips through JSON', () {
      final u = UserData.empty('alice');
      expect(u.forceLogout, isFalse);
      expect(u.toJson()['force_logout'], false);

      final kicked = u.copyWith(forceLogout: true);
      expect(kicked.forceLogout, isTrue);

      final reparsed = UserData.fromJson(kicked.toJson());
      expect(reparsed.forceLogout, isTrue);
    });

    test('reads legacy users with no force_logout field as false', () {
      final json = UserData.empty('bob').toJson()..remove('force_logout');
      expect(UserData.fromJson(json).forceLogout, isFalse);
    });
  });
}
