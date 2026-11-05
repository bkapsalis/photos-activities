import 'package:cloud_functions/cloud_functions.dart';

/// The moderator's AI tools. They run as Cloud Functions (functions/src):
/// the model is paid for and the AI comments are written on the server, out
/// of reach of anyone who is not a moderator.
class AiService {
  // Where the functions are deployed: REGION in functions/src/config.ts.
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-west1');

  /// Posts the animals in [photoId] as AI comments, having the AI look at
  /// the photo first if it has not yet. Once a moderator has deleted any of
  /// them, the AI looks afresh and the missing ones are posted again. Throws
  /// [FirebaseFunctionsException] with a message fit to show when it could
  /// not.
  Future<AnimalInfoOutcome> describeAnimals(String photoId) async {
    final result = await _functions
        .httpsCallable(
          'describeAnimals',
          // A look takes a few seconds, but the first call after a quiet
          // spell also waits for the function to start.
          options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
        )
        .call<Object?>({'photoId': photoId});
    return AnimalInfoOutcome.fromJson(result.data);
  }

  /// Posts the animals for the next few photos that have not had theirs
  /// posted. Call again until [AnimalBatchProgress.isFinished].
  Future<AnimalBatchProgress> describeNextBatch() async {
    final result = await _functions
        .httpsCallable(
          'describeAnimalsBatch',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
        )
        .call<Object?>({'limit': 12});
    return AnimalBatchProgress.fromJson(result.data);
  }
}

enum AnimalInfoStatus { posted, noAnimals, alreadyPosted }

/// What came of asking for one photo's animals.
class AnimalInfoOutcome {
  final AnimalInfoStatus status;
  final int count;
  final List<String> names;

  const AnimalInfoOutcome({
    required this.status,
    required this.count,
    this.names = const [],
  });

  factory AnimalInfoOutcome.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final names = map['names'];
    return AnimalInfoOutcome(
      status: switch (map['status']) {
        'posted' => AnimalInfoStatus.posted,
        'alreadyPosted' => AnimalInfoStatus.alreadyPosted,
        _ => AnimalInfoStatus.noAnimals,
      },
      count: (map['count'] as num?)?.toInt() ?? 0,
      names: names is List ? names.whereType<String>().toList() : const [],
    );
  }

  /// What to tell the moderator.
  String get message => switch (status) {
    AnimalInfoStatus.posted when count == 1 =>
      'Added an AI comment about the ${names.firstOrNull ?? 'animal'}.',
    AnimalInfoStatus.posted => 'Added $count AI comments: ${names.join(', ')}.',
    AnimalInfoStatus.noAnimals => 'The AI found no animals in this photo.',
    AnimalInfoStatus.alreadyPosted when count == 0 =>
      'Already checked: the AI found no animals in this photo.',
    AnimalInfoStatus.alreadyPosted =>
      "This photo's animals are already in the comments. Delete one to have "
          'the AI look again.',
  };
}

/// Where "Check all photos for animals" has got to after one batch.
class AnimalBatchProgress {
  /// Photos handled by this batch.
  final int checked;
  final int commentsAdded;

  /// Photos in this batch that could not be checked.
  final int failed;

  /// Photos still waiting.
  final int remaining;

  /// Photos whose check has failed, this batch's included. Later batches
  /// skip them; the photo's own button retries one.
  final int failedTotal;

  const AnimalBatchProgress({
    required this.checked,
    required this.commentsAdded,
    required this.failed,
    required this.remaining,
    required this.failedTotal,
  });

  factory AnimalBatchProgress.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    int read(String key) => (map[key] as num?)?.toInt() ?? 0;
    return AnimalBatchProgress(
      checked: read('checked'),
      commentsAdded: read('commentsAdded'),
      failed: read('failed'),
      remaining: read('remaining'),
      failedTotal: read('failedTotal'),
    );
  }

  /// Nothing left, or nothing more this run can do: a batch in which every
  /// photo failed would only fail the same way again.
  bool get isFinished => remaining == 0 || checked == 0 || failed == checked;
}
