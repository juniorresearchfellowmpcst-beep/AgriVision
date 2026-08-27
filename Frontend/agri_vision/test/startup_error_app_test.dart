import 'package:agri_vision/startup_error_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup failure is shown on screen, not just in the console', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupErrorApp(
        error: Exception('Unable to load asset: assets/.env'),
        stackTrace: StackTrace.fromString('#0  bootstrap (bootstrap.dart:20)'),
      ),
    );

    expect(find.text('AgriVision could not start'), findsOneWidget);
    expect(find.textContaining('assets/.env'), findsOneWidget);

    // The stack trace stays folded away so the message itself reads first.
    expect(find.textContaining('#0  bootstrap'), findsNothing);

    await tester.ensureVisible(find.text('Technical details'));
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();

    expect(find.textContaining('#0  bootstrap'), findsOneWidget);
  });
}
