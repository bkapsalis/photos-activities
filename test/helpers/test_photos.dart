import 'package:bills_bay_area/core/models/models.dart';
import 'package:flutter/material.dart';

/// A photo with just enough filled in for layout tests. [n] drives the id
/// (`p<n>`), the URL and the location name (`Spot <n>`).
PhotoPost testPhoto(int n, {int hearts = 0}) => PhotoPost(
  id: 'p$n',
  imageUrl: 'https://example.com/p$n.jpg',
  location: Location(
    id: 'spot_$n',
    name: 'Spot $n',
    postCount: 1,
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
);

List<PhotoPost> testPhotos(int count) =>
    [for (var i = 0; i < count; i++) testPhoto(i)];
