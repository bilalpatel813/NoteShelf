import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booknotes/main.dart';

Future<void> _launch(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: BookNotesApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('launches into the bookshelf with sample books', (tester) async {
    await _launch(tester);
    expect(find.text('BookNotes'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Astronomy Field Notes'), findsWidgets);
  });

  testWidgets('search filters books and shows empty state', (tester) async {
    await _launch(tester);
    await tester.enterText(find.byType(TextField), 'zzzz-no-match');
    await tester.pumpAndSettle();
    expect(find.text('No books match your search'), findsOneWidget);
  });

  testWidgets('long-press opens context menu and selects a book (Android)', (tester) async {
    await _launch(tester);
    await tester.longPress(find.text('Astronomy Field Notes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('tap opens a book via the integration point (Android)', (tester) async {
    await _launch(tester);
    await tester.tap(find.text('Astronomy Field Notes').first);
    await tester.pump();
    expect(find.textContaining('Reader integration point'), findsOneWidget);
  });
}
