import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Lets the thumbnail strip coast after a flick — slowing gradually, as a
/// list does — and then come to rest with a thumbnail exactly centred.
///
/// PageView's own page snapping caps every fling at one page, which feels
/// like the strip hitting a wall. This instead asks the platform's physics
/// (iOS-style bounce or Android-style clamp, whichever ScrollConfiguration
/// supplies as the parent) where the glide would naturally stop, rounds that
/// to the nearest thumbnail, and builds a friction curve that decelerates
/// onto exactly that spot. It is the approach Flutter's own wheel picker,
/// FixedExtentScrollPhysics, takes for its items.
///
/// Use with the PageView's `pageSnapping` turned off, or PageView wraps this
/// in its one-page snapping again.
class CarouselMomentumPhysics extends ScrollPhysics {
  const CarouselMomentumPhysics({super.parent});

  @override
  CarouselMomentumPhysics applyTo(ScrollPhysics? ancestor) =>
      CarouselMomentumPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Overscrolled past an end: the platform's bounce or clamp brings it back.
    if (position is! PageMetrics || position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    // A page is one thumbnail slot. PageView puts page n at n of these
    // whenever pages are narrower than the viewport, as thumbnails are.
    final page = position.viewportDimension * position.viewportFraction;
    if (page <= 0) return super.createBallisticSimulation(position, velocity);

    final tolerance = toleranceFor(position);
    final natural = super.createBallisticSimulation(position, velocity);
    final naturalEnd = natural?.x(double.infinity) ?? position.pixels;

    // Gliding into either end: let the platform finish it. Both ends are
    // themselves thumbnail positions, so it still stops on one.
    if (natural != null &&
        (naturalEnd <= position.minScrollExtent ||
            naturalEnd >= position.maxScrollExtent)) {
      return natural;
    }

    final target = ((naturalEnd / page).round() * page).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final distance = target - position.pixels;

    if (velocity.abs() < tolerance.velocity &&
        distance.abs() < tolerance.distance) {
      return null; // Already resting on a thumbnail.
    }

    // Too slow to carry on, or the nearest thumbnail is back the way it came
    // from: ease into place rather than coast.
    if (velocity.abs() < tolerance.velocity || distance.sign != velocity.sign) {
      return SpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }

    // Coast, decelerating smoothly onto the chosen thumbnail.
    return FrictionSimulation.through(
      position.pixels,
      target,
      velocity,
      tolerance.velocity * velocity.sign,
    );
  }
}
