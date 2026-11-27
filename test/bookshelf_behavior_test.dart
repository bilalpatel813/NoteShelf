import 'package:booknotes/core/contracts/contracts.dart';
import 'package:booknotes/core/models/book.dart';
import 'package:booknotes/core/models/book_design.dart';
import 'package:booknotes/features/bookshelf/book_card.dart';
import 'package:booknotes/features/bookshelf/bookshelf_providers.dart';
import 'package:booknotes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'support/demo_bookshelf_actions.dart';
import 'support/in_memory_book_repository.dart';

Book _book(
  String id,
  String title,
  String subject,
  int pages,
  DateTime? opened,
) =>
    Book(
      id: id,
      title: title,
      subject: subject,
      pageCount: pages,
      lastOpenedAt: opened,
      folderRef: 'memory://$id',
    );

List<Book> _books() => [
      _book('a', 'Alpha', 'Science', 10, DateTime.utc(2024, 1, 1)),
      _book('b', 'Beta', 'Art', 30, DateTime.utc(2024, 2, 1)),
      _book('c', 'Gamma', 'Science', 20, null),
    ];

Future<void> _launch(WidgetTester tester, InMemoryBookRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookRepositoryProvider.overrideWithValue(repo),
        bookshelfActionsProvider.overrideWith(
          (ref) => DemoBookshelfActions(ref),
        ),
      ],
      child: const BookNotesApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'repository stream updates filtered and sorted provider results',
    () async {
      final repo = InMemoryBookRepository(_books());
      final container = ProviderContainer(
        overrides: [bookRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(() {
        container.dispose();
        repo.dispose();
      });

      final subscription = container.listen(visibleBooksProvider, (_, __) {});
      addTearDown(subscription.close);
      await container.read(booksStreamProvider.future);
      await Future<void>.delayed(Duration.zero);
      List<String> titles() => container
          .read(visibleBooksProvider)
          .requireValue
          .map((book) => book.title)
          .toList();

      expect(titles(), ['Beta', 'Alpha', 'Gamma']);
      final controller = container.read(shelfControllerProvider.notifier);
      controller.setQuery('  SCIENCE  ');
      expect(titles(), ['Alpha', 'Gamma']);
      controller.setSort(BookSort.title);
      expect(titles(), ['Alpha', 'Gamma']);
      controller.setSort(BookSort.title);
      expect(titles(), ['Gamma', 'Alpha']);
      controller.setQuery('');
      controller.setSort(BookSort.pages);
      expect(titles(), ['Beta', 'Gamma', 'Alpha']);
      controller.setSort(BookSort.subject);
      expect(titles(), ['Beta', 'Alpha', 'Gamma']);

      await repo.updateBook(_books().first.copyWith(title: 'Zeta'));
      await Future<void>.delayed(Duration.zero);
      expect(titles(), ['Beta', 'Gamma', 'Zeta']);
      await repo.deleteBook('b');
      await Future<void>.delayed(Duration.zero);
      expect(titles(), ['Gamma', 'Zeta']);
      await repo.createBook(
        const NewBookRequest(title: 'Delta', subject: 'Art'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(titles(), ['Delta', 'Gamma', 'Zeta']);
    },
  );

  testWidgets('shelf rearranges books into rows as the viewport narrows', (
    tester,
  ) async {
    final repo = InMemoryBookRepository(_books());
    addTearDown(repo.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _launch(tester, repo);

    final a = find.byKey(const ValueKey('a'));
    final b = find.byKey(const ValueKey('b'));
    final c = find.byKey(const ValueKey('c'));
    expect(a, findsOneWidget);
    expect(b, findsOneWidget);
    expect(c, findsOneWidget);
    expect(tester.getTopLeft(a).dy, tester.getTopLeft(b).dy);
    expect(tester.getTopLeft(b).dy, tester.getTopLeft(c).dy);
    expect(find.text('10 pages'), findsOneWidget);
    expect(find.text('Never opened'), findsOneWidget);
    expect(find.text('Import Folder'), findsOneWidget);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    final positions = [a, b, c].map(tester.getTopLeft).toList();
    expect(positions.map((p) => p.dy).toSet().length, greaterThan(1));
    for (final finder in [a, b, c]) {
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sort menu changes the visible book order in both directions', (
    tester,
  ) async {
    final repo = InMemoryBookRepository(_books());
    addTearDown(repo.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _launch(tester, repo);

    Future<void> sortByTitle() async {
      await tester.tap(find.byTooltip('Sort books'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title'));
      await tester.pumpAndSettle();
    }

    double x(String id) => tester.getTopLeft(find.byKey(ValueKey(id))).dx;
    await sortByTitle();
    expect(x('a'), lessThan(x('b')));
    expect(x('b'), lessThan(x('c')));
    await sortByTitle();
    expect(x('c'), lessThan(x('b')));
    expect(x('b'), lessThan(x('a')));
  });

  testWidgets('search by subject, clear search, and switch themes', (
    tester,
  ) async {
    final repo = InMemoryBookRepository(_books());
    addTearDown(repo.dispose);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _launch(tester, repo);

    await tester.enterText(find.byType(TextField), 'sCiEnCe');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
    expect(find.byKey(const ValueKey('c')), findsOneWidget);
    expect(find.byKey(const ValueKey('b')), findsNothing);
    await tester.enterText(find.byType(TextField), 'not found');
    await tester.pumpAndSettle();
    expect(find.text('No books match your search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('b')), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(BookCard).first)).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(BookCard).first)).brightness,
      Brightness.light,
    );
  });

  testWidgets('empty shelf can create a book and stream it onto the shelf', (
    tester,
  ) async {
    final repo = InMemoryBookRepository([]);
    addTearDown(repo.dispose);
    await _launch(tester, repo);
    expect(find.text('Your shelf is empty'), findsOneWidget);
    await tester.tap(find.text('New Book').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'New atlas',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Subject'), 'Maps');
    await tester.tap(find.text('Create book'));
    await tester.pumpAndSettle();
    expect(find.text('Your shelf is empty'), findsNothing);
    expect(find.text('New atlas'), findsWidgets);
    expect((await repo.listBooks()).single.subject, 'Maps');
  });

  testWidgets('context menu rename and confirmed delete update the shelf', (
    tester,
  ) async {
    final repo = InMemoryBookRepository([_books().first]);
    addTearDown(repo.dispose);
    await _launch(tester, repo);
    await tester.longPress(find.byKey(const ValueKey('a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'New name');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    expect(find.text('New name'), findsWidgets);
    expect((await repo.listBooks()).single.title, 'New name');

    await tester.longPress(find.byKey(const ValueKey('a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await repo.listBooks()), hasLength(1));
    await tester.longPress(find.byKey(const ValueKey('a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(await repo.listBooks(), isEmpty);
    expect(find.text('Your shelf is empty'), findsOneWidget);
  });

  testWidgets('large library scrolls to books beyond the initial viewport', (
    tester,
  ) async {
    final repo = InMemoryBookRepository(
      List.generate(100, (i) {
        final number = i.toString().padLeft(3, '0');
        return _book(
          'book-$number',
          'Book $number',
          'Library',
          i + 1,
          DateTime.utc(2025, 1, 1).subtract(Duration(days: i)),
        );
      }),
    );
    addTearDown(repo.dispose);
    await _launch(tester, repo);
    expect(find.byKey(const ValueKey('book-000')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('book-099')),
      500,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 100,
    );
    expect(find.byKey(const ValueKey('book-099')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('author search finds a customized book', (tester) async {
    final base = _books().first;
    final repo = InMemoryBookRepository([
      base.copyWith(
        cover: BookCoverRef(
          design: BookDesign.preset(BookTheme.diary)
              .copyWith(author: 'Ada Lovelace'),
        ),
      ),
    ]);
    addTearDown(repo.dispose);
    await _launch(tester, repo);
    await tester.enterText(find.byType(TextField), 'lovelace');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
  });

  testWidgets('long titles and different page counts fit at enlarged text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryBookRepository([
      _book('thin', 'A very long title that must not overflow its shelf',
          'Notes', 1, null),
      _book('thick', 'A substantial volume', 'Reference', 500, null),
    ]);
    addTearDown(repo.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookRepositoryProvider.overrideWithValue(repo),
        bookshelfActionsProvider
            .overrideWith((ref) => DemoBookshelfActions(ref)),
      ],
      child: const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: BookNotesApp(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(BookCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
