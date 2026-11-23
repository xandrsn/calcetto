import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config.dart';
import 'providers/github_provider.dart';
import 'providers/local_store.dart';
import 'providers/user_provider.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/notifications.dart';
import 'theme/app_theme.dart';
import 'utils/app_clock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initAppClock(); // resolve Europe/Madrid so all phase logic uses Spanish time
  NotificationService.init(); // Android-only daily phase reminders; fire & forget
  // No token and not the demo build: run fully on-device (see README).
  final local = (kDemoMode || kGithubToken.isNotEmpty)
      ? null
      : await LocalStore.open();
  runApp(
    ProviderScope(
      overrides: [
        if (local != null) githubServiceProvider.overrideWithValue(local),
      ],
      child: const CalcettoApp(),
    ),
  );
}

/// Global text scale per platform (tune here). Android renders denser than a
/// display-scaled desktop window, so it gets a larger value to read the same.
const double _kDesktopTextScale = 1.6;
const double _kAndroidTextScale = 1.85;

class CalcettoApp extends ConsumerWidget {
  const CalcettoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Calcetto',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) {
        // Boost legibility of the small pixel font, and pin the scale so a
        // device's large-font accessibility setting can't break the fixed
        // pixel layouts.
        //
        // Desktop is usually viewed with OS display scaling (125–150%), so 1.6
        // reads well there; a phone renders at its native density and the same
        // sizes feel small, so Android gets a larger scale.
        final mq = MediaQuery.of(context);
        final scale = defaultTargetPlatform == TargetPlatform.android
            ? _kAndroidTextScale
            : _kDesktopTextScale;
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: _PhoneFrame(child: child),
        );
      },
      home: const _Root(),
    );
  }
}

/// Keeps the mobile-first UI at a phone-width portrait column on every
/// platform. On wide windows (desktop maximized) the extra space becomes a
/// neutral letterbox with a subtle device frame, so the app reads as an
/// intentional portrait client instead of a stretched mobile layout.
class _PhoneFrame extends StatelessWidget {
  static const double _maxContentWidth = 430;
  static const Color _gutter = Color(0xFF0d0d1a);

  final Widget? child;
  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final content = child ?? const SizedBox.shrink();
    return ColoredBox(
      color: _gutter,
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasGutter = constraints.maxWidth > _maxContentWidth + 1;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kBackground,
                  border: hasGutter
                      ? const Border(
                          left: BorderSide(color: kSurface, width: 1),
                          right: BorderSide(color: kSurface, width: 1),
                        )
                      : null,
                ),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);
    return userAsync.when(
      loading: () => const _LoadingScreen(),
      error: (e, st) => const SplashScreen(),
      data: (user) => user != null ? const HomeScreen() : const SplashScreen(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBackground,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
