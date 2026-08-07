import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';

class UserProfile {
  final String id;
  final String name;
  final String initials;
  final Color avatarColor;
  final String? role;
  final bool isMe;

  const UserProfile({
    required this.id,
    required this.name,
    required this.initials,
    required this.avatarColor,
    this.role,
    this.isMe = false,
  });

  factory UserProfile.fromFirebaseUser(auth.User user) {
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

    final colors = [
      const Color(0xFF4CAF50),
      const Color(0xFF1E88E5),
      const Color(0xFFE53935),
      const Color(0xFFFF9800),
      const Color(0xFF8E24AA),
      const Color(0xFF00ACC1),
    ];
    final colorIndex = user.uid.hashCode.abs() % colors.length;

    return UserProfile(
      id: user.uid,
      name: name,
      initials: initials,
      avatarColor: colors[colorIndex],
      role: 'Contributor',
      isMe: true,
    );
  }
}

class Location {
  final String id;
  final String name;
  final String? region;
  final int postCount;
  final String category;

  const Location({
    required this.id,
    required this.name,
    this.region,
    required this.postCount,
    required this.category,
  });

  factory Location.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Location(
      id: doc.id,
      name: data['name'] as String? ?? '',
      region: data['region'] as String?,
      postCount: (data['postCount'] as num?)?.toInt() ?? 0,
      category: data['category'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'region': region,
      'postCount': postCount,
      'category': category,
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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'imageUrl': imageUrl,
      'locationId': location.id,
      'locationName': location.name,
      'locationRegion': location.region,
      'category': category.isNotEmpty ? category : location.category,
      'userId': user.id,
      'userName': user.name,
      'userInitials': user.initials,
      'userAvatarColor': user.avatarColor.toARGB32(),
      'heartCount': heartCount,
      'commentCount': commentCount,
      'aspectRatio': aspectRatio,
      'createdAt': FieldValue.serverTimestamp(),
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
