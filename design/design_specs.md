# Bills Bay Area - Design Specifications

## App Name
Bills Bay Area Fun thing to do!

## Design System
- Material 3
- Adaptive Auto Layout
- Flutter + React (cross-platform)

## Viewports
- Mobile (iOS/Android): 393 × 852
- Web (Desktop Browser): 1440 × 900

---

## Screen 1: Home / Discovery

### Mobile Layout
- Bottom navigation bar with 4 tabs: Home, Explore, Map, Profile
- Top area: "Discover" label, app title "Bills Bay Area 🏔", notification bell + user avatar
- Search bar: "Search Bay Area spots..."
- Sliding tab bar with 3 category tabs: "Hiking", "Museums", "Historical Sites"
- Vertical Masonry photo feed showing user uploads
  - Each card has: photo, location pill overlay (e.g., "Marin Headlands"), user avatar + name, heart count
  - Cards are staggered/masonry layout
- FAB (Floating Action Button) - green "+" button at bottom right

### Web Layout
- Browser chrome with URL "billsbayarea.app"
- Top horizontal navigation bar with:
  - App logo + "Bills Bay Area" title
  - Category pills: Hiking, Museums, Historical Sites
  - Search bar
  - Notification bell, "Community Chat" button, "Open Chat" button, "+ Upload" button, user avatar
- Left sidebar panel:
  - Active category title (e.g., "Hiking") with subtitle "6 photo spots"
  - Community stats: 1,158 Likes, 5 Photos, 5 Spots
  - Locations list: Marin Headlands (234), Mt. Tamalpais (189), Eaton Canyon Trail (156), Tilden Park (145), Muir Woods (89)
  - Trending / Favorites links
- Main body: Multi-column responsive grid photo feed
  - Cards with photo, location pill, user avatar + name, heart count

---

## Screen 2: Contextual Location Chat

### Mobile Layout
- Full-screen overlay/sheet for the chat room
- Chat room title context (e.g., "Eaton Canyon Trail Chat")
- Scrolling message thread with:
  - User avatars (colored circles with initials)
  - Message bubbles (gray for others, green/teal for "ME")
  - Timestamps (e.g., "10:36 AM")
  - Heart/reaction counts on messages
- Users shown: Sam W., ME (green), Chris L., Alex M.
- Bottom input area: photo icon, "Message the group..." text field, emoji icon, send button (green circle)

### Web Layout
- Split-pane layout
- Left side: The photo/image being discussed
- Right side: Chat panel with messages (same format as mobile)
- Bottom: Message input with send button
- The main photo feed remains partially visible behind

---

## Screen 3: Picture-Specific Chat Room (Picture Chat)

### Mobile Layout (393 × 852)
- Opens on click of a picture card
- ~40% top: Selected photo fixed at top with location pill overlay ("Marin Headlands · Marin County, CA")
- Below photo: User info row — avatar (colored circle "MK"), "Maria K.", "Local Guide", heart icon + count (234), comment icon + count (6)
- ~60% bottom: "Comments & Discussion" section
  - Header: "Comments & Discussion" title + category pill (e.g., green "Hiking" tag)
  - Subtitle: "6 comments · Marin Headlands"
  - Scrolling comment thread:
    - Each comment: colored avatar circle with initials, username, message text, timestamp + heart reaction count
    - Example users: LocalGuide88, HikingQueen, PhotoWalker
    - Timestamps: "Yesterday 3:42 PM", etc.
  - Bottom input: user avatar, "Add a comment..." text field, emoji icon, green send button

### Web Layout (1440 × 900)
- Centralized floating modal/card overlay on the page
- Left side: Photo with location pill overlay ("Marin Headlands · Marin County, CA")
  - Below photo: User row — avatar "MK", "Maria K.", "Local Guide · Bay Area", green "Follow" button
  - Action icons: heart (234), bookmark, share, comment
- Right side: Comment/chat panel
  - Comment entries with avatars, usernames, message text
  - Example: "KeyWalker" — "Adding this to my gonna bucket list! What..."
  - Bottom: "Add a comment..." input with emoji icon + green send button

---

## Color Palette (from designs)
- Primary Green: ~#4CAF50 (tabs, FAB, send button, "ME" messages)
- Background Dark (Figma): #1E1E1E
- Card Background: White
- Location pills: Dark with white text + green dot
- User avatar colors: Various (red, green, blue, orange, purple)
- Heart icon: Red/pink

## Typography
- App title: Bold, ~20pt
- Location pills: Medium, ~12pt
- User names: Medium, ~14pt
- Heart counts: Regular, ~12pt
- Chat messages: Regular, ~14pt
- Timestamps: Light, ~11pt, gray

## Key Interactions
- Click a photo → opens Picture Chat
- Click the chat icon → opens Location Chat
- Tab navigation switches category feeds
- Bottom nav (mobile) / sidebar nav (web) for main navigation
