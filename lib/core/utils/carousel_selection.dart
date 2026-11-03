import '../models/models.dart';

/// Which photo the carousel should have selected after its list changes.
///
/// The feed is a live Firestore stream, so the list is rebuilt whenever any
/// photo in the category changes — someone likes one, a new upload lands.
/// Following the selected photo by id keeps the reader on the picture they
/// were looking at through those updates, even when the popularity sort moves
/// it. When it is gone (a different location tab, or the photo was deleted)
/// the carousel starts again from the first photo.
int resolveCarouselSelection(List<PhotoPost> photos, String? selectedId) {
  if (photos.isEmpty) return 0;
  if (selectedId == null) return 0;
  final index = photos.indexWhere((p) => p.id == selectedId);
  return index == -1 ? 0 : index;
}
