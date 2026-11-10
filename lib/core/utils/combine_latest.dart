import 'dart:async';

/// [combine] of the latest value from each of [a] and [b], every time either
/// changes, once both have produced one. Errors from either pass through.
/// Listening listens to both; cancelling cancels both.
Stream<R> combineLatest<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false, hasB = false;
  var doneA = false, doneB = false;

  void emit() {
    if (hasA && hasB) controller.add(combine(lastA as A, lastB as B));
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (value) {
          lastA = value;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneA = true;
          if (doneB) controller.close();
        },
      );
      subB = b.listen(
        (value) {
          lastB = value;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneB = true;
          if (doneA) controller.close();
        },
      );
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
    },
    onCancel: () async {
      await Future.wait([
        if (subA != null) subA!.cancel(),
        if (subB != null) subB!.cancel(),
      ]);
    },
  );
  return controller.stream;
}
