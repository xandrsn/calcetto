import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Consistent centered loading indicator with an optional label.
class LoadingView extends StatelessWidget {
  final String? label;
  const LoadingView({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kAccentGreen),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(
              label!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 11,
                color: kTextMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Friendly error state with an optional retry action. Avoids dumping raw
/// exception text (which can leak HTTP status / paths) at the user; the detail
/// is shown small and muted for debugging.
class ErrorView extends StatelessWidget {
  final Object? error;
  final String message;
  final VoidCallback? onRetry;

  const ErrorView({
    super.key,
    this.error,
    this.message = 'ALGO SALIÓ MAL',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: kAccentRed, size: 36),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 13,
                color: kTextPrimary,
                height: 1.3,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                _shortError(error!),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 5,
                  color: kTextMuted,
                  height: 1.3,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: kSurface,
                    border: Border.all(color: kAccentGreen, width: 2),
                  ),
                  child: const Text(
                    'REINTENTAR',
                    style: TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 12,
                      color: kAccentGreen,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _shortError(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}

/// Consistent empty-state placeholder.
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyView({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kTextMuted, size: 32),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 12,
                color: kTextMuted,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
