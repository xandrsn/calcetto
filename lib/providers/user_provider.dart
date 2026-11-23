import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_data.dart';
import 'game_state_provider.dart';

final usernameProvider = StateProvider<String?>((ref) => null);

class UserNotifier extends AsyncNotifier<UserData?> {
  @override
  Future<UserData?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('username');
    if (name == null) return null;
    ref.read(usernameProvider.notifier).state = name;
    return _loadOrLogout(name);
  }

  Future<UserData?> _loadUser(String name) async {
    final gh = ref.read(githubServiceProvider);
    final file = await gh.getJson('users/$name.json');
    if (file == null) return null;
    return UserData.fromJson(file.data as Map<String, dynamic>);
  }

  /// Loads the user, but if the admin has set the `force_logout` flag on them,
  /// clears the local session and returns null (→ splash). This is the only
  /// logout mechanism in the app; regular users have no logout button.
  Future<UserData?> _loadOrLogout(String name) async {
    final user = await _loadUser(name);
    if (user != null && user.forceLogout) {
      await _clearSession();
      return null;
    }
    return user;
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    ref.read(usernameProvider.notifier).state = null;
  }

  Future<void> setUsername(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', name);
    ref.read(usernameProvider.notifier).state = name;
    state = const AsyncLoading();
    final gh = ref.read(githubServiceProvider);
    final file = await gh.getFreshJson('users/$name.json');
    if (file == null) {
      final empty = UserData.empty(name).toJson();
      await gh.createJson('users/$name.json', empty, 'app: new user $name');
      state = AsyncData(UserData.empty(name));
    } else {
      final user = UserData.fromJson(file.data as Map<String, dynamic>);
      state = AsyncData(user);
      // Logging back in clears any admin force-logout flag (merge-safe).
      if (user.forceLogout) {
        await save((cur) => cur.copyWith(forceLogout: false), 'app: re-login');
      }
    }
  }

  /// Admin self-logout: clears this device's local session and returns to the
  /// splash/name screen. (Regular users have no logout; only the admin panel
  /// exposes this and the per-user remote logout.)
  Future<void> logout() async {
    await _clearSession();
    state = const AsyncData(null);
  }

  /// Saves a change to the current user, **merge-safely**: [edit] is applied to
  /// the freshest server copy of the user (not the possibly-stale in-memory
  /// one), so fields the user didn't touch — e.g. `points` / `cards_received`
  /// written by the resolution engine — are preserved. Retries on write
  /// conflicts (see [GithubService.mutateJson]).
  Future<void> save(
    UserData Function(UserData current) edit,
    String message,
  ) async {
    final name = ref.read(usernameProvider);
    if (name == null) return;
    final gh = ref.read(githubServiceProvider);
    UserData? written;
    await gh.mutateJson(
      'users/$name.json',
      message: message,
      transform: (current) {
        final server = current == null
            ? UserData.empty(name)
            : UserData.fromJson(current as Map<String, dynamic>);
        final updated = edit(server);
        written = updated;
        return updated.toJson();
      },
    );
    if (written != null) state = AsyncData(written);
    // Squad/bench changes alter ownership %s for everyone — refresh the shared
    // snapshot so this device's percentages update immediately (other devices
    // pick it up via the HomeScreen poller).
    ref.invalidate(allUsersProvider);
  }

  Future<void> refresh() async {
    final name = ref.read(usernameProvider);
    if (name == null) return;
    state = const AsyncLoading();
    // Picks up an admin force-logout on resume / pull-to-refresh.
    state = AsyncData(await _loadOrLogout(name));
  }
}

final userProvider = AsyncNotifierProvider<UserNotifier, UserData?>(
  UserNotifier.new,
);
