import 'package:flutter/material.dart';
import '../models/models.dart';

// ── Users ──────────────────────────────────────────────

class MockUsers {
  static const maria = UserProfile(
    id: 'u1', name: 'Maria K.', initials: 'MK',
    avatarColor: Color(0xFFE53935), role: 'Local Guide',
  );
  static const jake = UserProfile(
    id: 'u2', name: 'Jake R.', initials: 'JR',
    avatarColor: Color(0xFF1E88E5),
  );
  static const sam = UserProfile(
    id: 'u3', name: 'Sam', initials: 'SW',
    avatarColor: Color(0xFF4CAF50),
  );
  static const alex = UserProfile(
    id: 'u4', name: 'Alex M.', initials: 'AM',
    avatarColor: Color(0xFFFF9800),
  );
  static const chris = UserProfile(
    id: 'u5', name: 'Chris L.', initials: 'CL',
    avatarColor: Color(0xFF8E24AA),
  );
  static const samW = UserProfile(
    id: 'u6', name: 'Sam W.', initials: 'SW',
    avatarColor: Color(0xFF4CAF50),
  );
  static const me = UserProfile(
    id: 'me', name: 'Me', initials: 'ME',
    avatarColor: Color(0xFF4CAF50), isMe: true,
  );
  static const localGuide88 = UserProfile(
    id: 'u7', name: 'LocalGuide88', initials: 'LG',
    avatarColor: Color(0xFF6D4C41),
  );
  static const hikingQueen = UserProfile(
    id: 'u8', name: 'HikingQueen', initials: 'HQ',
    avatarColor: Color(0xFF00ACC1),
  );
  static const photoWalker = UserProfile(
    id: 'u9', name: 'PhotoWalker', initials: 'PW',
    avatarColor: Color(0xFFD81B60),
  );
  static const keyWalker = UserProfile(
    id: 'u10', name: 'KeyWalker', initials: 'KW',
    avatarColor: Color(0xFF1E88E5),
  );
}

// ── Locations ──────────────────────────────────────────

class MockLocations {
  static const marinHeadlands = Location(
    id: 'l1', name: 'Marin Headlands', region: 'Marin County, CA',
    postCount: 234, category: 'Hiking',
  );
  static const mountTamalpais = Location(
    id: 'l2', name: 'Mount Tamalpais', region: 'Mill Valley, CA',
    postCount: 189, category: 'Hiking',
  );
  static const pointReyes = Location(
    id: 'l3', name: 'Point Reyes', region: 'Point Reyes, CA',
    postCount: 156, category: 'Hiking',
  );
  static const tildenPark = Location(
    id: 'l4', name: 'Tilden Park', region: 'Berkeley, CA',
    postCount: 145, category: 'Hiking',
  );
  static const eatonCanyonTrail = Location(
    id: 'l5', name: 'Eaton Canyon Trail', region: 'Pasadena, CA',
    postCount: 156, category: 'Hiking',
  );
  static const muirWoods = Location(
    id: 'l6', name: 'Muir Woods', region: 'Mill Valley, CA',
    postCount: 89, category: 'Hiking',
  );

  static const List<Location> hiking = [
    marinHeadlands, mountTamalpais, pointReyes,
    tildenPark, eatonCanyonTrail, muirWoods,
  ];
}

// ── Photo Posts ─────────────────────────────────────────

class MockPhotos {
  static final List<PhotoPost> hikingPhotos = [
    PhotoPost(
      id: 'p1', imageUrl: 'https://picsum.photos/seed/marin/800/600',
      location: MockLocations.marinHeadlands, user: MockUsers.maria,
      heartCount: 234, commentCount: 6, aspectRatio: 1.3,
    ),
    PhotoPost(
      id: 'p2', imageUrl: 'https://picsum.photos/seed/tamalpais/800/1000',
      location: MockLocations.mountTamalpais, user: MockUsers.jake,
      heartCount: 189, commentCount: 3, aspectRatio: 0.8,
    ),
    PhotoPost(
      id: 'p3', imageUrl: 'https://picsum.photos/seed/reyes/800/600',
      location: MockLocations.pointReyes, user: MockUsers.sam,
      heartCount: 312, commentCount: 8, aspectRatio: 1.2,
    ),
    PhotoPost(
      id: 'p4', imageUrl: 'https://picsum.photos/seed/tilden/800/900',
      location: MockLocations.tildenPark, user: MockUsers.alex,
      heartCount: 145, commentCount: 2, aspectRatio: 0.9,
    ),
    PhotoPost(
      id: 'p5', imageUrl: 'https://picsum.photos/seed/eaton/800/600',
      location: MockLocations.eatonCanyonTrail, user: MockUsers.chris,
      heartCount: 278, commentCount: 5, aspectRatio: 1.4,
    ),
    PhotoPost(
      id: 'p6', imageUrl: 'https://picsum.photos/seed/muirwoods/800/1100',
      location: MockLocations.muirWoods, user: MockUsers.maria,
      heartCount: 198, commentCount: 4, aspectRatio: 0.7,
    ),
    PhotoPost(
      id: 'p7', imageUrl: 'https://picsum.photos/seed/baytrail/800/700',
      location: MockLocations.marinHeadlands, user: MockUsers.samW,
      heartCount: 167, commentCount: 2, aspectRatio: 1.1,
    ),
    PhotoPost(
      id: 'p8', imageUrl: 'https://picsum.photos/seed/sunset/800/600',
      location: MockLocations.mountTamalpais, user: MockUsers.jake,
      heartCount: 421, commentCount: 12, aspectRatio: 1.3,
    ),
  ];
}

// ── Chat Messages (Location Chat) ──────────────────────

class MockChat {
  static final List<ChatMessage> locationChat = [
    ChatMessage(
      id: 'm1', user: MockUsers.samW,
      text: 'Early morning! I went at 7am last Saturday and had the whole trail to myself 🔥',
      timestamp: '10:37 AM', reactionCount: 8,
    ),
    ChatMessage(
      id: 'm2', user: MockUsers.me, isMe: true,
      text: "Just got back! The creek is running high. Don't forget waterproof boots!",
      timestamp: '10:42 AM',
    ),
    ChatMessage(
      id: 'm3', user: MockUsers.chris,
      text: 'Thanks for the tips! Heading out tomorrow morning 🙌',
      timestamp: '10:44 AM',
    ),
    ChatMessage(
      id: 'm4', user: MockUsers.alex,
      text: 'Wildflowers are blooming near the upper switchbacks too. Bring a camera!',
      timestamp: '10:49 AM', reactionCount: 15,
    ),
  ];
}

// ── Comments (Picture Chat) ────────────────────────────

class MockComments {
  static final List<Comment> photoComments = [
    Comment(
      id: 'c1', user: MockUsers.localGuide88,
      text: "This south overlook is one of my top picks in the Bay! Worth the extra half mile hike.",
      timestamp: 'Yesterday 3:42 PM', heartCount: 15,
    ),
    Comment(
      id: 'c2', user: MockUsers.hikingQueen,
      text: 'Were you there last weekend? I saw some red-tailed hawks soaring right above this spot!',
      timestamp: 'Yesterday 4:10 PM', heartCount: 7,
    ),
    Comment(
      id: 'c3', user: MockUsers.keyWalker,
      text: 'Adding this to my gonna bucket list! What a view!',
      timestamp: 'Today 9:15 AM', heartCount: 3,
    ),
  ];
}

// ── Categories ─────────────────────────────────────────

const List<String> categories = ['Hiking', 'Museums', 'Historical Sites'];

// ── Community Stats ────────────────────────────────────

class CommunityStats {
  static const int likes = 1158;
  static const int photos = 5;
  static const int spots = 5;
}
