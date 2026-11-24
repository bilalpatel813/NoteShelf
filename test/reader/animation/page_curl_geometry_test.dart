// T4 geometry + drag-rule unit tests. Pure Dart: `flutter test test/reader/animation`.
import 'dart:math' as math;
import 'dart:ui';

import 'package:booknotes/features/reader/animation/page_curl_geometry.dart';
import 'package:booknotes/features/reader/animation/page_turn_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(800, 600);

CurlFrame _frame({
  required bool unfolded,
  required int dir,
  required double t,
}) => PageCurlGeometry.compute(
  size: _size,
  unfolded: unfolded,
  direction: dir,
  progress: t,
);

void main() {
  group('Affine2', () {
    test('reflection applied twice is the identity', () {
      final r = Affine2.reflection(
        const Offset(300, 0),
        const Offset(0.1, 0.99498743710662),
      );
      const p = Offset(123, 456);
      final q = r.apply(r.apply(p));
      expect(q.dx, closeTo(p.dx, 1e-9));
      expect(q.dy, closeTo(p.dy, 1e-9));
    });

    test('after() applies the argument first', () {
      final shiftX = const Affine2(1, 0, 0, 1, 10, 0);
      final doubleX = const Affine2(2, 0, 0, 1, 0, 0);
      final p = doubleX.after(shiftX).apply(const Offset(1, 0)); // (1+10)*2
      expect(p.dx, 22);
    });
  });

  group('clipPolygonToHalfPlane', () {
    const square = [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)];
    test('keeps exactly half of a square cut through its middle', () {
      final half = clipPolygonToHalfPlane(
        square,
        const Offset(5, 0),
        const Offset(1, 0),
        keepPositive: true,
      );
      expect(polygonArea(half), closeTo(50, 1e-9));
    });
    test('fully outside gives an empty polygon, fully inside is unchanged', () {
      expect(
        clipPolygonToHalfPlane(
          square,
          const Offset(20, 0),
          const Offset(1, 0),
          keepPositive: true,
        ),
        isEmpty,
      );
      final all = clipPolygonToHalfPlane(
        square,
        const Offset(-5, 0),
        const Offset(1, 0),
        keepPositive: true,
      );
      expect(polygonArea(all), closeTo(100, 1e-9));
    });
  });

  group('PageCurlGeometry', () {
    for (final unfolded in [false, true]) {
      for (final dir in [1, -1]) {
        final tag =
            '${unfolded ? 'unfolded' : 'folded'} ${dir > 0 ? 'forward' : 'backward'}';

        test(
          '$tag: start shows only the outgoing spread, end only the turned page',
          () {
            final f0 = _frame(unfolded: unfolded, dir: dir, t: 0);
            expect(polygonArea(f0.flapPoly), closeTo(0, 1e-6));
            expect(polygonArea(f0.hingeSidePoly), closeTo(800 * 600, 1e-3));

            final f1 = _frame(unfolded: unfolded, dir: dir, t: 1);
            expect(
              polygonArea(f1.revealedPoly),
              closeTo(f1.region.width * 600, 1e-3),
            );
            final stationary = unfolded
                ? 400.0 * 600
                : 0.0; // two-page mode keeps its other page
            expect(polygonArea(f1.hingeSidePoly), closeTo(stationary, 1e-3));
          },
        );

        test(
          '$tag: fold moves monotonically to the hinge; flap and rest partition the page',
          () {
            var previous = double.infinity;
            for (var i = 1; i < 20; i++) {
              final f = _frame(unfolded: unfolded, dir: dir, t: i / 20);
              final distance = (f.foldMid.dx - f.hingeX).abs();
              expect(distance, lessThan(previous), reason: 't=${i / 20}');
              previous = distance;
              expect(
                f.normal.dx * dir,
                greaterThan(0),
                reason: 'normal points away from hinge',
              );
              expect(
                polygonArea(f.flapPoly),
                closeTo(polygonArea(f.revealedPoly), 1e-4),
                reason: 'reflection preserves area',
              );
              final page = [
                f.region.topLeft,
                f.region.topRight,
                f.region.bottomRight,
                f.region.bottomLeft,
              ];
              final rest = clipPolygonToHalfPlane(
                page,
                f.foldTop,
                f.normal,
                keepPositive: false,
              );
              expect(
                polygonArea(rest) + polygonArea(f.revealedPoly),
                closeTo(f.region.width * f.region.height, 1e-3),
              );
            }
          },
        );
      }
    }

    test(
      'two-page mode: at the end the flap lands exactly on the stationary page',
      () {
        for (final dir in [1, -1]) {
          final f = _frame(unfolded: true, dir: dir, t: 1);
          final stationary = PageCurlGeometry.stationaryRegionFor(
            _size,
            unfolded: true,
            direction: dir,
          );
          final xs = f.flapPoly.map((o) => o.dx);
          expect(xs.reduce(math.min), closeTo(stationary.left, 1e-6));
          expect(xs.reduce(math.max), closeTo(stationary.right, 1e-6));
          // back transform is the identity: the incoming spread is drawn in place.
          expect(f.back.a, closeTo(1, 1e-9));
          expect(f.back.d, closeTo(1, 1e-9));
          expect(f.back.e, closeTo(0, 1e-9));
          expect(f.back.f, closeTo(0, 1e-9));
        }
      },
    );

    test('backward is the mirror image of forward', () {
      for (final unfolded in [false, true]) {
        for (final t in [0.2, 0.5, 0.8]) {
          final a = _frame(unfolded: unfolded, dir: 1, t: t);
          final b = _frame(unfolded: unfolded, dir: -1, t: t);
          expect(800 - a.foldTop.dx, closeTo(b.foldTop.dx, 1e-9));
          expect(a.foldTop.dy, closeTo(b.foldTop.dy, 1e-9));
          expect(
            polygonArea(a.flapPoly),
            closeTo(polygonArea(b.flapPoly), 1e-6),
          );
        }
      }
    });

    test('binding position: gutter when unfolded, page edge when folded', () {
      expect(_frame(unfolded: true, dir: 1, t: .5).hingeX, 400);
      expect(_frame(unfolded: true, dir: -1, t: .5).hingeX, 400);
      expect(_frame(unfolded: false, dir: 1, t: .5).hingeX, 0);
      expect(_frame(unfolded: false, dir: -1, t: .5).hingeX, 800);
    });
  });

  group('PageTurnDrag', () {
    test('direction and progress follow the finger', () {
      expect(PageTurnDrag.directionFor(-5), 1);
      expect(PageTurnDrag.directionFor(5), -1);
      expect(PageTurnDrag.progressDelta(-100, 1, 400), closeTo(0.25, 1e-9));
      expect(PageTurnDrag.progressDelta(100, -1, 400), closeTo(0.25, 1e-9));
      expect(
        PageTurnDrag.progressDelta(100, 1, 400),
        closeTo(-0.25, 1e-9),
      ); // dragging back
    });

    test(
      'commit: past halfway, or a fling the right way; cancel on a flick back',
      () {
        expect(
          PageTurnDrag.shouldCommit(progress: .6, velocityX: 0, direction: 1),
          isTrue,
        );
        expect(
          PageTurnDrag.shouldCommit(progress: .4, velocityX: 0, direction: 1),
          isFalse,
        );
        expect(
          PageTurnDrag.shouldCommit(
            progress: .1,
            velocityX: -1500,
            direction: 1,
          ),
          isTrue,
        );
        expect(
          PageTurnDrag.shouldCommit(
            progress: .1,
            velocityX: -1500,
            direction: -1,
          ),
          isFalse,
        ); // moving away
        expect(
          PageTurnDrag.shouldCommit(
            progress: .1,
            velocityX: 1500,
            direction: -1,
          ),
          isTrue,
        );
        expect(
          PageTurnDrag.shouldCommit(
            progress: .9,
            velocityX: 1500,
            direction: 1,
          ),
          isFalse,
        );
      },
    );

    test(
      'a mouse may only start a drag near the page edges; touch anywhere',
      () {
        const size = Size(1000, 600);
        expect(
          PageTurnDrag.mayStart(
            local: const Offset(500, 300),
            size: size,
            kind: PointerDeviceKind.mouse,
          ),
          isFalse,
        );
        expect(
          PageTurnDrag.mayStart(
            local: const Offset(50, 300),
            size: size,
            kind: PointerDeviceKind.mouse,
          ),
          isTrue,
        );
        expect(
          PageTurnDrag.mayStart(
            local: const Offset(960, 300),
            size: size,
            kind: PointerDeviceKind.mouse,
          ),
          isTrue,
        );
        expect(
          PageTurnDrag.mayStart(
            local: const Offset(500, 300),
            size: size,
            kind: PointerDeviceKind.touch,
          ),
          isTrue,
        );
      },
    );
  });
}
