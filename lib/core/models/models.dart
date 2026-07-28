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
}

class PhotoPost {
  final String id;
  final String imageUrl;
  final Location location;
  final UserProfile user;
  final int heartCount;
  final int commentCount;
  final double aspectRatio;

  const PhotoPost({
    required this.id,
    required this.imageUrl,
    required this.location,
    required this.user,
    required this.heartCount,
    this.commentCount = 0,
    this.aspectRatio = 1.0,
  });
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
}
