# Bills Bay Area Photos App — Conversation Summary
**Date**: August 2–7, 2026  
**Conversation ID**: `7e88e09f-3b3c-4e95-9d16-266d53627051`  
**Project**: `/Users/williamkapsalis/antigravity-flutter-firebase/Photo-Three-Env/bills_photos`

---

## Project Overview

A Flutter + Firebase photo-sharing app for Bay Area locations. Uses **3 Firebase environments** (dev/staging/prod) with flavors. The app displays photos in a masonry grid by category (Hiking, Museums, Historic Sites), supports community chat per location, picture comments, hearts, and photo uploads.

### Key Firebase Services
- **Firestore** — photos, locations, chat messages, comments collections
- **Firebase Storage** — photo image uploads
- **Firebase Auth** — anonymous auth for dev

### Firebase Dev Project: `photos-activities-dev`

---

## What Was Built in This Conversation

### 1. Firestore Stream Connectivity (Completed)
Connected all UI screens to live Firestore streams:
- **Photo Feed**: `MobileHomeLayout` and `WebHomeLayout` use `StreamBuilder<List<PhotoPost>>` with `FirestoreService.streamPhotosByCategory(category)`
- **Location Chat**: `LocationChatScreen` streams `FirestoreService.streamChatMessages(locationId)` with `sendChatMessage()`
- **Picture Comments**: `PictureChatScreen` streams `FirestoreService.streamComments(photoId)` with `addComment()` and `incrementHeartCount()`
- **Auto-Seeding**: `seedSampleDataIfEmpty()` populates Firestore when empty

### 2. Photo Upload (Completed)
- **Single Upload**: `UploadPhotoDialog` — pick from gallery, camera, or preset emulator-friendly photo
- **Batch Upload**: `BatchUploadDialog` — select up to 50 photos from gallery with progress tracking
- **Storage**: `StorageService.uploadBytes()` uploads `Uint8List` via `putData()` (avoids Android temp cache file issues)
- **Category path sanitization**: e.g. "Historic Sites" → "historic-sites" in Storage paths

### 3. Edit & Delete Features (Completed)
- **Edit Photo**: `EditPhotoDialog` — modify spot name, region, category. Accessible via `⋮` menu on `PhotoCard` and `PictureChatScreen`
- **Delete Photo**: Confirmation dialog → `FirestoreService.deletePhoto()`. Available on `PhotoCard` and `PictureChatScreen`
- **Edit Comment**: Inline dialog via `⋯` menu on each `_CommentTile` → `FirestoreService.updateComment()`
- **Delete Comment**: Via `⋯` menu → `FirestoreService.deleteComment()` (also decrements comment count)

### 4. Bug Fixes (Completed)
- **Google Photos upload crash**: Fixed `PathNotFoundException` when Android cache files were cleaned before upload. Solution: read bytes into memory at pick time, upload via `uploadBytes()` instead of re-reading XFile path
- **Android permissions**: Added `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE`, `CAMERA` to AndroidManifest.xml
- **Batch upload thumbnails**: Removed image compression parameters from `pickMultiImage()` that caused blank thumbnails on Android
- **Batch upload button visibility**: Redesigned dialog with responsive `insetPadding`, `maxHeight: 85% screen`, pinned bottom action button

---

## Key Files Modified/Created

### Core Services
| File | Purpose |
|------|---------|
| `lib/core/services/firestore_service.dart` | Firestore CRUD, streams, seed data, `updatePhotoDetails()`, `updateComment()`, `deleteComment()` |
| `lib/core/services/storage_service.dart` | `uploadBytes()`, `uploadXFile()`, `pickImage()`, `pickMultiImage(limit: 50)` |

### Feature Widgets
| File | Purpose |
|------|---------|
| `lib/features/home/widgets/upload_photo_dialog.dart` | Single photo upload dialog |
| `lib/features/home/widgets/batch_upload_dialog.dart` | **[NEW]** Multi-photo batch upload (up to 50) with progress |
| `lib/features/home/widgets/edit_photo_dialog.dart` | **[NEW]** Edit photo spot details |
| `lib/features/home/widgets/photo_card.dart` | Photo card with `⋮` menu (Edit/Delete) |
| `lib/features/home/widgets/mobile_home_layout.dart` | Mobile layout, FAB with single/batch upload options |
| `lib/features/home/widgets/web_home_layout.dart` | Web layout with Upload + Batch Upload buttons |
| `lib/features/picture_chat/picture_chat_screen.dart` | Photo detail + comments, edit/delete for photos & comments |

### Config & Rules
| File | Purpose |
|------|---------|
| `firestore.rules` | Deployed to dev — authenticated users can create/update/delete photos, comments, chat messages |
| `android/app/src/main/AndroidManifest.xml` | Media/camera permissions |
| `ios/Runner/Info.plist` | Photo library/camera usage descriptions |

### Models
| File | Purpose |
|------|---------|
| `lib/core/models/models.dart` | `UserProfile.fromFirebaseUser()` factory, `PhotoPost`, `Comment`, `Location`, `ChatMessage` |

---

## Running the App

```bash
# Dev flavor on Android emulator
flutter run --flavor dev -t lib/main_dev.dart -d emulator-5554

# Dev flavor on Chrome Web
flutter run --flavor dev -t lib/main_dev.dart -d chrome
```

A background `flutter run` task is currently running as **task-192**. Send `R` via `manage_task send_input` for hot restart.

---

## Firestore Data Model

```
photos/{photoId}
  ├── imageUrl, locationName, locationRegion, category
  ├── userId, userName, heartCount, commentCount
  └── createdAt

comments/{photoId}/messages/{commentId}
  ├── text, userId, userName, timestamp
  └── heartCount

chats/{locationId}/messages/{messageId}
  ├── text, userId, userName, timestamp
  └── isMe (computed client-side)

locations/{locationId}
  ├── name, region, category, postCount
```

---

## Current State

- `flutter analyze --no-fatal-infos` passes with **0 errors** (11 info-level `avoid_print` warnings only)
- Firestore rules deployed to `photos-activities-dev`
- App running on `emulator-5554` via task-192
- All features functional: photo feed streams, single upload, batch upload (50 max), edit/delete photos, edit/delete comments, location chat, picture chat, hearts
