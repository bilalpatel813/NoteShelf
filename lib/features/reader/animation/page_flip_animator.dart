/// T4 - the simpler "page flip": the turning page narrows about the binding
/// (an edge-on rotation without perspective), then the page's back widens on
/// the other side. Pure frame builder; [PageTurnAnimator]s own the state.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'page_curl_geometry.dart';

class RectClipper extends CustomClipper<Rect> {
  const RectClipper(this.rect);
  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(RectClipper old) => old.rect != rect;
}

/// Horizontal scale by [s] about x = [hinge].
Matrix4 _scaleAbout(double hinge, double s) => Matrix4.fromList(<double>[
  s, 0, 0, 0, //
  0, 1, 0, 0,
  0, 0, 1, 0,
  hinge * (1 - s), 0, 0, 1,
]);

Widget _shaded(Widget child, double alpha) => Stack(
  fit: StackFit.expand,
  children: [
    child,
    IgnorePointer(
      child: ColoredBox(color: Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0))),
    ),
  ],
);

/// One frame of the flip at [progress] (0..1). [outgoing] / [incoming] are the
/// spreads built by the reader's SpreadBuilder, retained by the caller.
Widget buildFlipFrame({
  required Size size,
  required bool unfolded,
  required int direction,
  required double progress,
  required Widget outgoing,
  required Widget incoming,
}) {
  final t = progress.clamp(0.0, 1.0).toDouble();
  final hinge = PageCurlGeometry.hingeFor(
    size,
    unfolded: unfolded,
    direction: direction,
  );
  final turning = PageCurlGeometry.regionFor(
    size,
    unfolded: unfolded,
    direction: direction,
  );
  final still = PageCurlGeometry.stationaryRegionFor(
    size,
    unfolded: unfolded,
    direction: direction,
  );

  // Angle 0..pi. cos > 0: front of the page is facing us; cos < 0: its back.
  final c = math.cos(t * math.pi);
  final width = c.abs() < 0.001 ? 0.001 : c.abs();

  final children = <Widget>[
    Positioned.fill(child: incoming),
    // Two-page mode: the page that stays put remains visible until covered.
    if (unfolded)
      Positioned.fill(
        child: ClipRect(clipper: RectClipper(still), child: outgoing),
      ),
  ];

  if (c > 0) {
    children.add(
      Positioned.fill(
        child: Transform(
          transform: _scaleAbout(hinge, width),
          child: ClipRect(
            clipper: RectClipper(turning),
            child: _shaded(outgoing, 0.30 * (1 - c)),
          ),
        ),
      ),
    );
  } else if (unfolded) {
    // The back of the page is the incoming spread's page beside the binding.
    children.add(
      Positioned.fill(
        child: Transform(
          transform: _scaleAbout(hinge, width),
          child: ClipRect(
            clipper: RectClipper(still),
            child: _shaded(incoming, 0.30 * (1 - width)),
          ),
        ),
      ),
    );
  } else {
    // Folded layout, second half: the page has swung out past the edge; the
    // incoming page underneath is all that remains. The placeholder keeps the
    // child list the same length so nothing is re-created mid-turn.
    children.add(const SizedBox.shrink());
  }

  return Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.hardEdge,
    children: children,
  );
}
