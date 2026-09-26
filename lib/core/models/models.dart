import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';

import 'photo_metadata.dart';
export 'photo_metadata.dart';

class UserProfile {
  final String id;
  final String name;
  final String initials;
  final Color avatarColor;
  final String? role;
  final bool isMe;
  final bool isGuest;

  const UserProfile({
    required this.id,
    required this.name,
    required this.initials,
    required this.avatarColor,
    this.role,
    this.isMe = false,
    this.isGuest = false,
  });

  /// Every guest would otherwise be called "Guest", so a uid fragment keeps
  /// them distinguishable in a shared chat.
  static String guestName(String uid) {
    final suffix = uid.length >= 4 ? uid.substring(0, 4) : uid;
    return 'Guest $suffix';
  }

  factory UserProfile.fromFirebaseUser(auth.User user) {
    if (user.isAnonymous) {
      return UserProfile(
        id: user.uid,
        name: guestName(user.uid),
        initials: 'G',
        avatarColor: _colorForUid(user.uid),
        role: 'Guest',
        isMe: true,
        isGuest: true,
      );
    }

    final name = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName!
        : (user.email != null && user.email!.isNotEmpty)
            ? user.email!.split('@').first
            : 'Bay Explorer';

    final parts = name.trim().split(RegExp(r'\s+'));
    String initials = 'BE';
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      if (parts.length >= 2 && parts.last.isNotEmpty) {
        initials = '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      } else {
        initials = parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
      }
    }

    return UserProfile(
      id: user.uid,
      name: name,
      initials: initials,
      avatarColor: _colorForUid(user.uid),
      role: 'Contributor',
      isMe: true,
    );
  }

  static Color _colorForUid(String uid) {
    const colors = [
      Color(0xFF4CAF50),
      Color(0xFF1E88E5),
      Color(0xFFE53935),
      Color(0xFFFF9800),
      Color(0xFF8E24AA),
      Color(0xFF00ACC1),
    ];
    return colors[uid.hashCode.abs() % colors.length];
  }
}

class Location {
  final String id;
  final String name;
  final String? region;
  final int postCount;
  final String category;

  /// Where this place actually is. Null for photos uploaded before
  /// coordinates were captured, and for place names too vague to pin
  /// (a region rather than a spot). Anything with a null pair is simply
  /// left off the map rather than guessed at.
  final double? latitude;
  final double? longitude;

  const Location({
    required this.id,
    required this.name,
    this.region,
    required this.postCount,
    required this.category,
    this.latitude,
    this.longitude,
  });

  /// True only when this place can be put on a map.
  bool get hasCoordinates => latitude != null && longitude != null;

  factory Location.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Location(
      id: doc.id,
      name: data['name'] as String? ?? '',
      region: data['region'] as String?,
      postCount: (data['postCount'] as num?)?.toInt() ?? 0,
      category: data['category'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'region': region,
      'postCount': postCount,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class PhotoPost {
  final String id;
  final String imageUrl;
  final Location location;
  final UserProfile user;
  final int heartCount;
  final int commentCount;
  final double aspectRatio;
  final String category;
  final DateTime? createdAt;

  /// What the original file said about itself, read before the upload was
  /// compressed. [PhotoMetadata.empty] for photos uploaded before capture
  /// existed, and for files that carried nothing.
  final PhotoMetadata metadata;

  const PhotoPost({
    required this.id,
    required this.imageUrl,
    required this.location,
    required this.user,
    required this.heartCount,
    this.commentCount = 0,
    this.aspectRatio = 1.0,
    this.category = '',
    this.createdAt,
    this.metadata = PhotoMetadata.empty,
  });

  factory PhotoPost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Build a lightweight location from the flat fields
    final location = Location(
      id: data['locationId'] as String? ?? '',
      name: data['locationName'] as String? ?? '',
      region: data['locationRegion'] as String?,
      postCount: 0,
      category: data['category'] as String? ?? '',
      latitude: (data['locationLat'] as num?)?.toDouble(),
      longitude: (data['locationLng'] as num?)?.toDouble(),
    );

    // Build a lightweight user profile from the flat fields
    final user = UserProfile(
      id: data['userId'] as String? ?? '',
      name: data['userName'] as String? ?? 'User',
      initials: data['userInitials'] as String? ?? 'U',
      avatarColor: Color(
        (data['userAvatarColor'] as num?)?.toInt() ?? 0xFF4CAF50,
      ),
    );

    return PhotoPost(
      id: doc.id,
      imageUrl: data['imageUrl'] as String? ?? '',
      location: location,
      user: user,
      heartCount: (data['heartCount'] as num?)?.toInt() ?? 0,
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      aspectRatio: (data['aspectRatio'] as num?)?.toDouble() ?? 1.0,
      category: data['category'] as String? ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      metadata: PhotoMetadata.fromFirestore(
        data['metadata'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'imageUrl': imageUrl,
      'locationId': location.id,
      'locationName': location.name,
      'locationRegion': location.region,
      'locationLat': location.latitude,
      'locationLng': location.longitude,
      'category': category.isNotEmpty ? category : location.category,
      'userId': user.id,
      'userName': user.name,
      'userInitials': user.initials,
      'userAvatarColor': user.avatarColor.toARGB32(),
      'heartCount': heartCount,
      'commentCount': commentCount,
      'aspectRatio': aspectRatio,
      'createdAt': FieldValue.serverTimestamp(),
      'metadata': metadata.toFirestore(),
    };
  }
}

class ChatMessage {
  final String id;
  final UserProfile user;
  final String text;
  final String timestamp;
  final int reactionCount;
  final bool isMe;

  const ChatMessage({
    required this.id,
    required this.user,
    required this.text,
    required this.timestamp,
    this.reactionCount = 0,
    this.isMe = false,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final user = UserProfile(
      id: data['userId'] as String? ?? '',
      name: data['userName'] as String? ?? 'User',
      initials: data['userInitials'] as String? ?? 'U',
      avatarColor: Color(
        (data['userAvatarColor'] as num?)?.toInt() ?? 0xFF4CAF50,
      ),
    );

    // Format timestamp
    String formattedTime = '';
    if (data['timestamp'] is Timestamp) {
      final dt = (data['timestamp'] as Timestamp).toDate();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) {
        formattedTime = 'Just now';
      } else if (diff.inHours < 1) {
        formattedTime = '${diff.inMinutes}m ago';
      } else if (diff.inDays < 1) {
        formattedTime = '${diff.inHours}h ago';
      } else {
        formattedTime = '${diff.inDays}d ago';
      }
    }

    return ChatMessage(
      id: doc.id,
      user: user,
      text: data['text'] as String? ?? '',
      timestamp: formattedTime,
      reactionCount: (data['reactionCount'] as num?)?.toInt() ?? 0,
      isMe: data['isMe'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': user.id,
      'userName': user.name,
      'userInitials': user.initials,
      'userAvatarColor': user.avatarColor.toARGB32(),
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'reactionCount': reactionCount,
      'isMe': isMe,
    };
  }
}

class Comment {
  final String id;
  final UserProfile user;
  final String text;
  final String timestamp;
  final int heartCount;

  const Comment({
    required this.id,
    required this.user,
    required this.text,
    required this.timestamp,
    this.heartCount = 0,
  });

  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final user = UserProfile(
      id: data['userId'] as String? ?? '',
      name: data['userName'] as String? ?? 'User',
      initials: data['userInitials'] as String? ?? 'U',
      avatarColor: Color(
        (data['userAvatarColor'] as num?)?.toInt() ?? 0xFF4CAF50,
      ),
    );

    // Format timestamp
    String formattedTime = '';
    if (data['timestamp'] is Timestamp) {
      final dt = (data['timestamp'] as Timestamp).toDate();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) {
        formattedTime = 'Just now';
      } else if (diff.inHours < 1) {
        formattedTime = '${diff.inMinutes}m ago';
      } else if (diff.inDays < 1) {
        formattedTime = '${diff.inHours}h ago';
      } else {
        formattedTime = '${diff.inDays}d ago';
      }
    }

    return Comment(
      id: doc.id,
      user: user,
      text: data['text'] as String? ?? '',
      timestamp: formattedTime,
      heartCount: (data['heartCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': user.id,
      'userName': user.name,
      'userInitials': user.initials,
      'userAvatarColor': user.avatarColor.toARGB32(),
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'heartCount': heartCount,
    };
  }
}
