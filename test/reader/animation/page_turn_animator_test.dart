// T4 animator widget tests: `flutter test test/reader/animation`.
//
// The harness drives the animators through the real PageTurnScope contract with
// plain text pages, so these tests do not depend on the reader or on storage.
import 'package:booknotes/features/reader/animation/page_curl_geometry.dart';
import 'package:booknotes/features/reader/animation/page_curl_painter.dart';
import 'package:booknotes/features/reader/animation/page_turn_animator.dart';
import 'package:booknotes/features/reader/reader_models.dart';
import 'package:booknotes/features/reader/reader_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pageCount = 7; // odd: unfolded spreads are (1,2) (3,4) (5,6) (7,-)

class _Harness extends StatefulWidget {
  const _Harness({
    required this.anchor,
    required this.layout,
    required this.gestures,
    required this.animator,
  });

  final ValueNotifier<int> anchor;
  final ReaderLayout layout;
  final bool gestures;
  final PageTurnAnimator animator;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _prev = 1;

  @override
  Widget build(BuildContext context) {
    final unfolded = widget.layout == ReaderLayout.unfolded;
    final step = unfolded ? 2 : 1;
    const last =
        _pageCount; // 7 is odd, so the last anchor is 7 in both layouts
    return ValueListenableBuilder<int>(
      valueListenable: widget.anchor,
      builder: (context, a, _) {
        final prev = _prev;
        _prev = a;
        final scope = PageTurnScope(
          anchor: a,
          previousAnchor: prev,
          layout: widget.layout,
          canGoBack: a > 1,
          canGoForward: a < last,
          gesturesEnabled: widget.gestures,
          goBack: () => widget.anchor.value = (a - step).clamp(1, last).toInt(),
          goForward: () =>
              widget.anchor.value = (a + step).clamp(1, last).toInt(),
          buildSpread: (c, n, {required interactive}) => _Spread(n, unfolded),
        );
        return widget.animator.build(context, scope);
      },
    );
  }
}

class _Spread extends StatelessWidget {
  const _Spread(this.n, this.unfolded);
  final int n;
  final bool unfolded;

  Widget _page(int p) => ColoredBox(
    color: Colors.white,
    child: Center(child: Text('page $p')),
  );

  @override
  Widget build(BuildContext context) {
    if (!unfolded) return _page(n);
    return Row(
      children: [
        Expanded(child: _page(n)),
        Expanded(
          child: n + 1 <= _pageCount ? _page(n + 1) : const SizedBox.expand(),
        ),
      ],
    );
  }
}

Future<void> _pump(
  WidgetTester t, {
  required ValueNotifier<int> anchor,
  ReaderLayout layout = ReaderLayout.folded,
  bool gestures = true,
  bool reduced = false,
  PageTurnAnimator animator = const CurlPageTurnAnimator(),
}) => t.pumpWidget(
  MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 600,
          height: 400,
          child: _Harness(
            anchor: anchor,
            layout: layout,
            gestures: gestures,
            animator: animator,
          ),
        ),
      ),
    ),
  ),
);

bool _turning() => find.byKey(pageTurnFrameKey).evaluate().isNotEmpty;

/// The curl frame currently being painted, or null when no curl is on screen.
CurlFrame? _curl(WidgetTester t) {
  final f = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is CurlShadowPainter,
  );
  if (f.evaluate().isEmpty) return null;
  return (t.widget<CustomPaint>(f).painter! as CurlShadowPainter).frame;
}

Set<int> _visible() => {
  for (var n = 1; n <= _pageCount + 1; n++)
    if (find.text('page $n').evaluate().isNotEmpty) n,
};

const _ms = Duration(milliseconds: 1);

void main() {
  group('turn direction', () {
    testWidgets(
      'forward: both pages shown mid-turn, fold sweeps toward the binding, ends on the new page',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a);
        expect(_turning(), isFalse);
        expect(_visible(), {1});

        a.value = 2;
        await t.pump();
        await t.pump(_ms * 120);
        expect(_turning(), isTrue);
        expect(_visible(), {1, 2});
        final f1 = _curl(t)!;
        expect(f1.direction, 1);

        await t.pump(_ms * 100);
        final f2 = _curl(t)!;
        expect(f2.progress, greaterThan(f1.progress));
        expect(f2.foldMid.dx, lessThan(f1.foldMid.dx));

        await t.pumpAndSettle();
        expect(_turning(), isFalse);
        expect(_visible(), {2});
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'backward: fold sweeps the other way and ends on the earlier page',
      (t) async {
        final a = ValueNotifier(3);
        await _pump(t, anchor: a);
        a.value = 2;
        await t.pump();
        await t.pump(_ms * 120);
        final f1 = _curl(t)!;
        expect(f1.direction, -1);
        expect(_visible(), {2, 3});

        await t.pump(_ms * 100);
        expect(_curl(t)!.foldMid.dx, greaterThan(f1.foldMid.dx));

        await t.pumpAndSettle();
        expect(_visible(), {2});
        expect(_turning(), isFalse);
      },
    );
  });

  group('layouts', () {
    testWidgets(
      'unfolded forward: stationary page stays, flap carries the incoming left page',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a, layout: ReaderLayout.unfolded);
        expect(_visible(), {1, 2});

        a.value = 3;
        await t.pump();
        await t.pump(_ms * 150);
        expect(_visible(), {
          1,
          2,
          3,
          4,
        }); // outgoing spread and incoming spread together
        expect(
          find.text('page 1'),
          findsOneWidget,
        ); // stationary left page: not animated twice
        expect(
          find.text('page 3'),
          findsNWidgets(2),
        ); // revealed base + the flap's back
        final f = _curl(t)!;
        expect(f.unfolded, isTrue);
        expect(f.hingeX, 300); // gutter of the 600 px wide book

        await t.pumpAndSettle();
        expect(_visible(), {3, 4});
        expect(find.text('page 3'), findsOneWidget);
      },
    );

    testWidgets(
      'unfolded backward turns the left page around the same gutter',
      (t) async {
        final a = ValueNotifier(3);
        await _pump(t, anchor: a, layout: ReaderLayout.unfolded);
        a.value = 1;
        await t.pump();
        await t.pump(_ms * 150);
        final f = _curl(t)!;
        expect(f.direction, -1);
        expect(f.hingeX, 300);
        expect(_visible(), {1, 2, 3, 4});
        await t.pumpAndSettle();
        expect(_visible(), {1, 2});
      },
    );

    testWidgets('folded layout animates a single page over the full width', (
      t,
    ) async {
      final a = ValueNotifier(1);
      await _pump(t, anchor: a);
      a.value = 2;
      await t.pump();
      await t.pump(_ms * 100);
      final f = _curl(t)!;
      expect(f.unfolded, isFalse);
      expect(f.region.width, 600);
      expect(f.hingeX, 0);
    });

    testWidgets(
      'odd final page: right side is blank, nothing is invented for page 8',
      (t) async {
        final a = ValueNotifier(5);
        await _pump(t, anchor: a, layout: ReaderLayout.unfolded);
        a.value = 7;
        await t.pump();
        await t.pump(_ms * 150);
        expect(_visible(), {5, 6, 7});
        await t.pumpAndSettle();
        expect(_visible(), {7});

        a.value = 5; // and back again
        await t.pump();
        await t.pump(_ms * 150);
        expect(_visible(), {5, 6, 7});
        await t.pumpAndSettle();
        expect(_visible(), {5, 6});
        expect(t.takeException(), isNull);
      },
    );
  });

  group('interruption', () {
    testWidgets('rapid repeated navigation never runs two turns at once', (
      t,
    ) async {
      final a = ValueNotifier(1);
      await _pump(t, anchor: a);
      for (var i = 0; i < 5; i++) {
        a.value = a.value + 1;
        await t.pump();
        await t.pump(_ms * 30);
        // One turn = at most two distinct pages on screen and one frame.
        expect(
          _visible().length,
          lessThanOrEqualTo(2),
          reason: 'step $i: ${_visible()}',
        );
        expect(
          find.byKey(pageTurnFrameKey).evaluate().length,
          lessThanOrEqualTo(1),
        );
      }
      await t.pumpAndSettle();
      expect(_visible(), {6});
      expect(_turning(), isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'direction change mid-turn reverses in place and settles on the old page',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a);
        a.value = 2;
        await t.pump();
        await t.pump(_ms * 150);
        final before = _curl(t)!.progress;
        expect(before, greaterThan(0));

        a.value = 1; // user turns straight back
        await t.pump();
        await t.pump(_ms * 60);
        final after = _curl(t)!;
        expect(
          after.direction,
          1,
          reason: 'same page keeps turning, now backwards',
        );
        expect(after.progress, lessThan(before));

        await t.pumpAndSettle();
        expect(_visible(), {1});
        expect(_turning(), isFalse);
      },
    );
  });

  group('reduced motion', () {
    testWidgets('uses a short fade, never the curl', (t) async {
      final a = ValueNotifier(1);
      await _pump(t, anchor: a, reduced: true);
      a.value = 2;
      await t.pump();
      await t.pump(_ms * 50);
      expect(_turning(), isTrue);
      expect(_curl(t), isNull);
      expect(_visible(), {1, 2}); // cross-fading
      await t.pump(
        _ms * 200,
      ); // fade completes; settling needs one more frame to build
      await t.pump();
      expect(_turning(), isFalse);
      expect(_visible(), {2});
    });

    testWidgets('a swipe still navigates, without any drag curl', (t) async {
      final a = ValueNotifier(1);
      await _pump(t, anchor: a, reduced: true);
      await t.fling(find.text('page 1'), const Offset(-300, 0), 1200);
      await t.pump();
      expect(_curl(t), isNull);
      await t.pumpAndSettle();
      expect(a.value, 2);
      expect(_visible(), {2});
    });
  });

  group('gestures', () {
    testWidgets(
      'View mode: swiping left turns forward, swiping right turns back',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a);
        await t.fling(find.text('page 1'), const Offset(-300, 0), 1200);
        await t.pumpAndSettle();
        expect(a.value, 2);
        expect(_visible(), {2});

        await t.fling(find.text('page 2'), const Offset(300, 0), 1200);
        await t.pumpAndSettle();
        expect(a.value, 1);
        expect(_visible(), {1});
      },
    );

    testWidgets(
      'the curl follows the finger; the reader only moves on release',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a);
        final g = await t.startGesture(t.getCenter(find.text('page 1')));
        await g.moveBy(const Offset(-100, 0));
        await t.pump();
        await g.moveBy(const Offset(-120, 0));
        await t.pump();
        final f1 = _curl(t)!;
        expect(a.value, 1, reason: 'no navigation while dragging');
        expect(f1.progress, greaterThan(0));
        await g.moveBy(const Offset(-120, 0));
        await t.pump();
        expect(_curl(t)!.progress, greaterThan(f1.progress));
        await g.moveBy(const Offset(120, 0)); // changes its mind a little
        await t.pump();
        expect(_curl(t)!.progress, lessThan(1));

        await g.moveBy(const Offset(-200, 0)); // well past half the 600 px page
        await t.pump();
        await g.up();
        await t.pumpAndSettle();
        expect(a.value, 2);
        expect(_visible(), {2});
        expect(_turning(), isFalse);
      },
    );

    testWidgets(
      'a short drag released early cancels: same page, no navigation',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a);
        final g = await t.startGesture(t.getCenter(find.text('page 1')));
        await g.moveBy(const Offset(-60, 0));
        await t.pump();
        await g.moveBy(const Offset(-60, 0));
        await t.pump();
        expect(_turning(), isTrue);
        await g.up();
        await t.pumpAndSettle();
        expect(a.value, 1);
        expect(_visible(), {1});
        expect(_turning(), isFalse);
      },
    );

    testWidgets('Edit mode (gesturesEnabled false): swipes do nothing', (
      t,
    ) async {
      final a = ValueNotifier(1);
      await _pump(t, anchor: a, gestures: false);
      await t.fling(find.text('page 1'), const Offset(-300, 0), 1200);
      await t.pumpAndSettle();
      expect(a.value, 1);
      expect(_turning(), isFalse);
    });

    testWidgets('cannot drag past the first or last page', (t) async {
      final a = ValueNotifier(1);
      await _pump(t, anchor: a);
      await t.fling(
        find.text('page 1'),
        const Offset(300, 0),
        1200,
      ); // back from page 1
      await t.pumpAndSettle();
      expect(a.value, 1);
      expect(_turning(), isFalse);

      a.value = _pageCount;
      await t.pumpAndSettle();
      await t.fling(find.text('page $_pageCount'), const Offset(-300, 0), 1200);
      await t.pumpAndSettle();
      expect(a.value, _pageCount);
    });

    testWidgets('a drag cannot start while a button turn is running', (
      t,
    ) async {
      final a = ValueNotifier(1);
      await _pump(t, anchor: a);
      a.value = 2;
      await t.pump();
      await t.pump(_ms * 100);
      final g = await t.startGesture(t.getCenter(find.byKey(pageTurnFrameKey)));
      await g.moveBy(const Offset(-200, 0));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(a.value, 2, reason: 'the drag was ignored');
      expect(_visible(), {2});
    });
  });

  group('styles', () {
    testWidgets('flip: forward and backward show the right pages and settle', (
      t,
    ) async {
      final a = ValueNotifier(1);
      await _pump(t, anchor: a, animator: const FlipPageTurnAnimator());
      a.value = 2;
      await t.pump();
      await t.pump(_ms * 100);
      expect(_turning(), isTrue);
      expect(_curl(t), isNull);
      expect(_visible(), {1, 2});
      await t.pumpAndSettle();
      expect(_visible(), {2});

      a.value = 1;
      await t.pump();
      await t.pump(_ms * 100);
      expect(_visible(), {1, 2});
      await t.pumpAndSettle();
      expect(_visible(), {1});
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'flip, unfolded: stationary page stays and the back shows the incoming page',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(
          t,
          anchor: a,
          layout: ReaderLayout.unfolded,
          animator: const FlipPageTurnAnimator(),
        );
        a.value = 3;
        await t.pump();
        await t.pump(
          _ms * 300,
        ); // past the half-way angle: the back of the page is showing
        expect(_visible(), {1, 2, 3, 4});
        await t.pumpAndSettle();
        expect(_visible(), {3, 4});
      },
    );

    testWidgets(
      'slide stays available as the fallback and does not use the engine',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a, animator: const SlidePageTurnAnimator());
        a.value = 2;
        await t.pump();
        await t.pump(_ms * 100);
        expect(_turning(), isFalse);
        await t.pumpAndSettle();
        expect(_visible(), {2});
      },
    );

    test('animatorForStyle maps every style, and only slide leaves gestures to the reader', () {
      expect(animatorForStyle(PageTurnStyle.curl), isA<CurlPageTurnAnimator>());
      expect(animatorForStyle(PageTurnStyle.flip), isA<FlipPageTurnAnimator>());
      expect(
        animatorForStyle(PageTurnStyle.slide),
        isA<SlidePageTurnAnimator>(),
      );
      expect(animatorForStyle(PageTurnStyle.curl).handlesGestures, isTrue);
      expect(animatorForStyle(PageTurnStyle.flip).handlesGestures, isTrue);
      expect(animatorForStyle(PageTurnStyle.slide).handlesGestures, isFalse);
    });
  });

  group('disposal', () {
    testWidgets(
      'removing the widget mid-turn leaves no exception or pending ticker',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a);
        a.value = 2;
        await t.pump();
        await t.pump(_ms * 100);
        expect(_turning(), isTrue);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'removing the widget mid-drag and while a commit is pending is safe',
      (t) async {
        final a = ValueNotifier(1);
        await _pump(t, anchor: a);
        final g = await t.startGesture(t.getCenter(find.text('page 1')));
        await g.moveBy(const Offset(-100, 0));
        await t.pump();
        await g.moveBy(const Offset(-300, 0));
        await t.pump();
        await t.pumpWidget(const SizedBox());
        await g.up();
        await t.pump(const Duration(seconds: 2)); // past the commit time-out
        expect(t.takeException(), isNull);
      },
    );
  });
}
