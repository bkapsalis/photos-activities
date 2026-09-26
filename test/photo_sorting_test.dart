import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bills_bay_area/core/models/models.dart';
import 'package:bills_bay_area/core/utils/photo_sorting.dart';

PhotoPost _photo(
  String id, {
  required int hearts,
  DateTime? createdAt,
  String locationName = 'Vasona Lake',
}) =>
    PhotoPost(
      id: id,
      imageUrl: 'https://example.com/$id.jpg',
      location: Location(
        id: locationName.toLowerCase(),
        name: locationName,
        postCount: 0,
        category: 'Hiking Areas',
      ),
      user: const UserProfile(
        id: 'u1',
        name: 'Bill',
        initials: 'BK',
        avatarColor: Color(0xFF4CAF50),
      ),
      heartCount: hearts,
      category: 'Hiking Areas',
      createdAt: createdAt,
    );

void main() {
  group('sortedByPopularity', () {
    test('puts the most-liked photos first', () {
      final sorted = [
        _photo('a', hearts: 2),
        _photo('b', hearts: 9),
        _photo('c', hearts: 5),
      ].sortedByPopularity();

      expect(sorted.map((p) => p.id), ['b', 'c', 'a']);
    });

    test('breaks ties by newest first', () {
      final sorted = [
        _photo('old', hearts: 3, createdAt: DateTime(2024, 1, 1)),
        _photo('new', hearts: 3, createdAt: DateTime(2026, 1, 1)),
        _photo('mid', hearts: 3, createdAt: DateTime(2025, 1, 1)),
      ].sortedByPopularity();

      expect(sorted.map((p) => p.id), ['new', 'mid', 'old']);
    });

    test('hearts outrank recency', () {
      final sorted = [
        _photo('newButUnloved', hearts: 0, createdAt: DateTime(2026, 6, 1)),
        _photo('oldButLoved', hearts: 12, createdAt: DateTime(2020, 1, 1)),
      ].sortedByPopularity();

      expect(sorted.first.id, 'oldButLoved');
    });

    test('undated photos sink below dated ones at the same heart count', () {
      final sorted = [
        _photo('undated', hearts: 4),
        _photo('dated', hearts: 4, createdAt: DateTime(2020, 1, 1)),
      ].sortedByPopularity();

      expect(sorted.map((p) => p.id), ['dated', 'undated']);
    });

    test('does not mutate the original list', () {
      final original = [
        _photo('a', hearts: 1),
        _photo('b', hearts: 7),
      ];
      final sorted = original.sortedByPopularity();

      expect(original.map((p) => p.id), ['a', 'b']);
      expect(sorted.map((p) => p.id), ['b', 'a']);
    });

    test('handles empty and single-item lists', () {
      expect(<PhotoPost>[].sortedByPopularity(), isEmpty);
      expect(
        [_photo('only', hearts: 3)].sortedByPopularity().single.id,
        'only',
      );
    });
  });
}
