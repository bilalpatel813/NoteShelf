/// T4 - page curl geometry. Pure maths on dart:ui types: no widgets, no state.
///
/// Model (deliberately simple, not a paper simulation): the turning page is a
/// rectangle [CurlFrame.region] hinged on one vertical edge ([CurlFrame.hingeX]).
/// A fold line sweeps from the far edge to the hinge as progress goes 0 -> 1.
/// The part of the page beyond the fold is mirrored across the fold line and
/// lies on top of the rest (the "flap", seen from its back). The fold line is
/// slightly slanted mid-turn so it reads as a lifted corner, not a hard wipe.
///
/// Everything is computed in real screen coordinates for [direction] +1
/// (forward: the page swings right to left) and -1 (backward: left to right),
/// so callers never mirror widgets.
library;

import 'dart:math' as math;
import 'dart:ui';

/// 2D affine map: x' = a*x + c*y + e, y' = b*x + d*y + f.
class Affine2 {
  const Affine2(this.a, this.b, this.c, this.d, this.e, this.f);

  static const identity = Affine2(1, 0, 0, 1, 0, 0);

  /// Reflection across the line through [p] with UNIT direction [dir].
  factory Affine2.reflection(Offset p, Offset dir) {
    final dx = dir.dx, dy = dir.dy;
    final dot = dx * p.dx + dy * p.dy;
    return Affine2(
      2 * dx * dx - 1,
      2 * dx * dy,
      2 * dx * dy,
      2 * dy * dy - 1,
      2 * p.dx - 2 * dx * dot,
      2 * p.dy - 2 * dy * dot,
    );
  }

  final double a, b, c, d, e, f;

  /// this(other(p)): [other] is applied first.
  Affine2 after(Affine2 o) => Affine2(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.e + c * o.f + e,
    b * o.e + d * o.f + f,
  );

  Offset apply(Offset p) => Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  /// Column-major 4x4 for `Transform(transform: Matrix4.fromList(...))`.
  List<double> toColumnMajor4() => <double>[
    a, b, 0, 0, //
    c, d, 0, 0,
    0, 0, 1, 0,
    e, f, 0, 1,
  ];
}

/// Sutherland-Hodgman clip of a convex/concave polygon against one half-plane
/// {p : dot(p - origin, normal) >= 0} (or <= 0 when [keepPositive] is false).
List<Offset> clipPolygonToHalfPlane(
  List<Offset> poly,
  Offset origin,
  Offset normal, {
  required bool keepPositive,
}) {
  if (poly.isEmpty) return const [];
  double side(Offset p) {
    final s = (p.dx - origin.dx) * normal.dx + (p.dy - origin.dy) * normal.dy;
    return keepPositive ? s : -s;
  }

  final out = <Offset>[];
  for (var i = 0; i < poly.length; i++) {
    final cur = poly[i];
    final nxt = poly[(i + 1) % poly.length];
    final sc = side(cur), sn = side(nxt);
    if (sc >= 0) {
      out.add(cur);
      if (sn < 0) out.add(cur + (nxt - cur) * (sc / (sc - sn)));
    } else if (sn >= 0) {
      out.add(cur + (nxt - cur) * (sc / (sc - sn)));
    }
  }
  return out;
}

/// Unsigned polygon area (shoelace).
double polygonArea(List<Offset> p) {
  if (p.length < 3) return 0;
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s.abs() / 2;
}

Path _pathOf(List<Offset> poly) {
  final path = Path();
  if (poly.length >= 3) path.addPolygon(poly, true);
  return path;
}

/// Everything needed to draw one frame of the curl.
class CurlFrame {
  CurlFrame({
    required this.size,
    required this.progress,
    required this.direction,
    required this.unfolded,
    required this.hingeX,
    required this.region,
    required this.foldTop,
    required this.foldBottom,
    required this.normal,
    required this.revealedPoly,
    required this.flapPoly,
    required this.hingeSidePoly,
    required this.reflect,
    required this.back,
  });

  final Size size;
  final double progress;

  /// +1 forward (page swings right to left), -1 backward.
  final int direction;
  final bool unfolded;

  /// x of the binding the page turns around (gutter, or the page edge when folded).
  final double hingeX;

  /// The rectangle of the page being turned.
  final Rect region;
  final Offset foldTop, foldBottom;

  /// Unit vector perpendicular to the fold, pointing AWAY from the hinge.
  final Offset normal;

  /// Part of [region] already turned over (beyond the fold), before mirroring.
  /// This is where the incoming page is revealed.
  final List<Offset> revealedPoly;

  /// [revealedPoly] mirrored across the fold: the flap as it lies on screen.
  final List<Offset> flapPoly;

  /// Whole bounds on the hinge side of the fold: where the OUTGOING spread is
  /// still visible (includes the stationary page in two-page mode).
  final List<Offset> hingeSidePoly;

  /// Mirror across the fold line.
  final Affine2 reflect;

  /// Maps the incoming spread onto the flap: reflect after mirroring across the
  /// binding. In two-page mode the flap's back IS the incoming spread's page on
  /// the hinge's far side. Identity at progress 1.
  final Affine2 back;

  Rect get bounds => Offset.zero & size;
  Offset get foldMid => Offset((foldTop.dx + foldBottom.dx) / 2, (foldTop.dy + foldBottom.dy) / 2);
  Offset get foldDir {
    final d = foldBottom - foldTop;
    final len = d.distance;
    return len == 0 ? const Offset(0, 1) : d / len;
  }

  bool get isStart => progress <= 0;
  bool get isEnd => progress >= 1;

  late final Path revealedPath = _pathOf(revealedPoly);
  late final Path flapPath = _pathOf(flapPoly);
  late final Path hingeSidePath = _pathOf(hingeSidePoly);
}

class PageCurlGeometry {
  const PageCurlGeometry._();

  /// x of the binding the turning page is hinged on.
  static double hingeFor(Size size, {required bool unfolded, required int direction}) =>
      unfolded ? size.width / 2 : (direction > 0 ? 0.0 : size.width);

  /// The page being turned: the right half for a forward turn and the left half
  /// for a backward turn in two-page mode, the whole area when folded.
  static Rect regionFor(Size size, {required bool unfolded, required int direction}) {
    if (!unfolded) return Offset.zero & size;
    final mid = size.width / 2;
    return direction > 0
        ? Rect.fromLTRB(mid, 0, size.width, size.height)
        : Rect.fromLTRB(0, 0, mid, size.height);
  }

  /// The page that stays put (two-page mode) = the other half.
  static Rect stationaryRegionFor(Size size, {required bool unfolded, required int direction}) {
    if (!unfolded) return Rect.zero;
    final mid = size.width / 2;
    return direction > 0
        ? Rect.fromLTRB(0, 0, mid, size.height)
        : Rect.fromLTRB(mid, 0, size.width, size.height);
  }

  /// [tilt] is the mid-turn slant of the fold as a fraction of page height.
  static CurlFrame compute({
    required Size size,
    required bool unfolded,
    required int direction,
    required double progress,
    double tilt = 0.10,
  }) {
    assert(direction == 1 || direction == -1);
    final t = progress.clamp(0.0, 1.0).toDouble();
    final w = size.width, h = size.height;
    final hingeX = hingeFor(size, unfolded: unfolded, direction: direction);
    final region = regionFor(size, unfolded: unfolded, direction: direction);

    final uFold = region.width * (1 - t); // distance of the fold from the hinge
    final k = tilt * h * math.sin(math.pi * t); // 0 at both ends: no stray slivers
    final cx = hingeX + direction * uFold;
    final top = Offset(cx + direction * k, 0);
    final bottom = Offset(cx - direction * k, h);

    final d = bottom - top;
    final len = d.distance;
    final dir = len == 0 ? const Offset(0, 1) : d / len;
    var n = Offset(dir.dy, -dir.dx);
    if (n.dx * direction < 0) n = Offset(-n.dx, -n.dy);

    final page = <Offset>[region.topLeft, region.topRight, region.bottomRight, region.bottomLeft];
    final bounds = <Offset>[Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)];
    final revealed = clipPolygonToHalfPlane(page, top, n, keepPositive: true);
    final hingeSide = clipPolygonToHalfPlane(bounds, top, n, keepPositive: false);

    final reflect = Affine2.reflection(top, dir);
    final sigma = Affine2.reflection(Offset(hingeX, 0), const Offset(0, 1));
    return CurlFrame(
      size: size,
      progress: t,
      direction: direction,
      unfolded: unfolded,
      hingeX: hingeX,
      region: region,
      foldTop: top,
      foldBottom: bottom,
      normal: n,
      revealedPoly: revealed,
      flapPoly: [for (final p in revealed) reflect.apply(p)],
      hingeSidePoly: hingeSide,
      reflect: reflect,
      back: reflect.after(sigma),
    );
  }
}
