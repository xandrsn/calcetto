import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/widgets/async_states.dart';

void main() {
  group('ErrorView', () {
    testWidgets('shows the message and fires retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              error: Exception('GET users/x.json failed: 403'),
              message: 'NO HAY CONEXIÓN',
              onRetry: () => retried++,
            ),
          ),
        ),
      );

      expect(find.text('NO HAY CONEXIÓN'), findsOneWidget);
      expect(find.text('REINTENTAR'), findsOneWidget);

      await tester.tap(find.text('REINTENTAR'));
      expect(retried, 1);
    });

    testWidgets('hides retry when no callback given', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ErrorView())),
      );
      expect(find.text('REINTENTAR'), findsNothing);
    });
  });

  group('EmptyView', () {
    testWidgets('renders its message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyView(icon: Icons.inbox, message: 'SIN DATOS'),
          ),
        ),
      );
      expect(find.text('SIN DATOS'), findsOneWidget);
    });
  });
}
