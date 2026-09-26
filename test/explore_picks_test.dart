import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/core/utils/explore_picks.dart';

PhotoPost _photo({
  required String id,
  required String location,
  required int hearts,
  String category = 'Hiking Areas',
}) {
  return PhotoPost(
    id: id,
    imageUrl: 'https://example.test/$id.jpg',
    location: Location(
      id: location.toLowerCase(),
      name: location,
      postCount: 0,
      category: category,
    ),
    user: const UserProfile(
      id: 'u1',
      name: 'Tester',
      initials: 'T',
      avatarColor: Colors.blue,
    ),
    heartCount: hearts,
    commentCount: 0,
    aspectRatio: 1,
    category: category,
  );
}

void main() {
  test('takes the most-liked photo from each location', () {
    final photos = [
      _photo(id: 'a1', location: 'Vasona Lake', hearts: 1),
      _photo(id: 'a2', location: 'Vasona Lake', hearts: 9),
      _photo(id: 'b1', location: 'Rancho', hearts: 4),
      _photo(id: 'b2', location: 'Rancho', hearts: 2),
    ];

    final picks = photos.topLikedPerLocation(perLocation: 1, random: Random(1));

    expect(picks.map((p) => p.id).toSet(), {'a2', 'b1'});
  });

  test(
    'every location is represented regardless of how many photos it has',
    () {
      final photos = [
        for (var i = 0; i < 50; i++)
          _photo(id: 'busy$i', location: 'Busy Place', hearts: i),
        _photo(id: 'quiet1', location: 'Quiet Place', hearts: 0),
      ];

      final picks = photos.topLikedPerLocation(
        perLocation: 2,
        random: Random(2),
      );

      // The busy location contributes 2, not 50 — a quiet location is never
      // crowded off the Explore feed.
      expect(picks.where((p) => p.location.name == 'Busy Place').length, 2);
      expect(picks.where((p) => p.location.name == 'Quiet Place').length, 1);
    },
  );

  test('perLocation caps how many each location contributes', () {
    final photos = [
      for (var i = 0; i < 5; i++)
        _photo(id: 'p$i', location: 'One Spot', hearts: i),
    ];

    expect(photos.topLikedPerLocation(perLocation: 3).length, 3);
    expect(photos.topLikedPerLocation(perLocation: 1).length, 1);
  });

  test('picks the top by hearts, not by arrival order', () {
    final photos = [
      _photo(id: 'low', location: 'Spot', hearts: 0),
      _photo(id: 'high', location: 'Spot', hearts: 100),
      _photo(id: 'mid', location: 'Spot', hearts: 50),
    ];

    final picks = photos.topLikedPerLocation(perLocation: 2);
    expect(picks.map((p) => p.id).toSet(), {'high', 'mid'});
  });

  test('a different seed produces a different order', () {
    final photos = [
      for (var i = 0; i < 12; i++)
        _photo(id: 'p$i', location: 'Loc$i', hearts: i),
    ];

    final a = photos.topLikedPerLocation(perLocation: 1, random: Random(1));
    final b = photos.topLikedPerLocation(perLocation: 1, random: Random(7));

    expect(a.length, b.length);
    expect(a.map((p) => p.id).toList() == b.map((p) => p.id).toList(), isFalse);
  });

  test('photos with a blank location name are skipped', () {
    final photos = [
      _photo(id: 'blank', location: '   ', hearts: 10),
      _photo(id: 'real', location: 'Real Place', hearts: 1),
    ];

    final picks = photos.topLikedPerLocation();
    expect(picks.map((p) => p.id), ['real']);
  });

  test('an empty feed yields no picks', () {
    expect(<PhotoPost>[].topLikedPerLocation(), isEmpty);
  });
}
