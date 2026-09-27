import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:club_jeronimo_zarlenga/screens/club_app.dart';

void main() {
  testWidgets('shows the club access screen', (tester) async {
    await tester.pumpWidget(const ClubApp());

    expect(find.text('INICIAR SESIÓN'), findsOneWidget);
    expect(find.text('Explorar sedes como invitado'), findsOneWidget);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context), const Locale('es', 'AR'));
    expect(
      MaterialLocalizations.of(context).formatCompactDate(DateTime(2026, 9, 7)),
      '7/9/2026',
    );
  });

  testWidgets('does not expose a client-controlled admin role', (tester) async {
    await tester.pumpWidget(const ClubApp());

    expect(find.text('Administrador'), findsNothing);
    expect(
      find.textContaining('Firebase todavía no está configurado'),
      findsOneWidget,
    );
  });

  testWidgets('allows typing into login fields before Firebase is configured', (
    tester,
  ) async {
    await tester.pumpWidget(const ClubApp());

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'jugador@example.com');
    await tester.enterText(fields.at(1), 'password123');

    expect(find.text('jugador@example.com'), findsOneWidget);
  });

  testWidgets('opens an editable registration form before Firebase setup', (
    tester,
  ) async {
    await tester.pumpWidget(const ClubApp());
    final openRegister = find.byKey(const ValueKey('open-register'));
    await tester.ensureVisible(openRegister);
    await tester.tap(openRegister);
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(5));
    await tester.enterText(fields.at(0), 'Ana');
    await tester.enterText(fields.at(1), 'Deportista');
    await tester.enterText(fields.at(2), 'ana@example.com');

    expect(find.text('ana@example.com'), findsOneWidget);
  });
}
