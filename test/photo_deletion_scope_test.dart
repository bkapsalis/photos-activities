import 'package:flutter_test/flutter_test.dart';
import 'package:bills_bay_area/core/services/photo_deletion_service.dart';

Map<String, dynamic> photo({String? category, String? location}) => {
  'category': ?category,
  'locationName': ?location,
};

bool matches(Map<String, dynamic> data) => PhotoDeletionService.matches(
  data,
  category: 'Museums - Historic Sites',
  locationName: 'Forbes Mill Museum',
);

void main() {
  group('PhotoDeletionService.matches', () {
    test('matches a photo in the named location and category', () {
      expect(
        matches(
          photo(
            category: 'Museums - Historic Sites',
            location: 'Forbes Mill Museum',
          ),
        ),
        isTrue,
      );
    });

    test('ignores case and surrounding whitespace on both fields', () {
      expect(
        matches(
          photo(
            category: '  museums - historic sites ',
            location: 'forbes mill museum  ',
          ),
        ),
        isTrue,
      );
    });

    test('spares another location in the same category', () {
      expect(
        matches(
          photo(
            category: 'Museums - Historic Sites',
            location: 'Filoli Historic House & Garden',
          ),
        ),
        isFalse,
      );
    });

    test('spares the same location name under a different category', () {
      expect(
        matches(
          photo(category: 'Hiking Areas', location: 'Forbes Mill Museum'),
        ),
        isFalse,
      );
    });

    test('spares a photo whose name merely starts the same', () {
      expect(
        matches(
          photo(
            category: 'Museums - Historic Sites',
            location: 'Forbes Mill Museum Annex',
          ),
        ),
        isFalse,
      );
    });

    test('spares photos with missing fields rather than treating them as ""', () {
      expect(matches(photo(category: 'Museums - Historic Sites')), isFalse);
      expect(matches(photo(location: 'Forbes Mill Museum')), isFalse);
      expect(matches(photo()), isFalse);
    });

    test('never matches when the target location is blank', () {
      // A blank tab name must not become "delete everything with no location".
      expect(
        PhotoDeletionService.matches(
          photo(category: 'Hiking Areas', location: ''),
          category: 'Hiking Areas',
          locationName: '   ',
        ),
        isFalse,
      );
    });

    test('a wrong field type spares the photo instead of throwing', () {
      // One malformed row must not abort the whole delete, and must never be
      // taken for a match. Sparing is the recoverable mistake.
      expect(
        PhotoDeletionService.matches(
          {'category': 'Hiking Areas', 'locationName': 42},
          category: 'Hiking Areas',
          locationName: 'Vasona Lake',
        ),
        isFalse,
      );
      expect(
        PhotoDeletionService.matches(
          {'category': null, 'locationName': null},
          category: 'Hiking Areas',
          locationName: 'Vasona Lake',
        ),
        isFalse,
      );
    });
  });
}
