# Store listing texts

Copy-ready texts for Google Play Console and App Store Connect. Character
limits are in brackets; every text here fits.

Links used throughout:

- Website: https://photos-activities-prod.web.app
- Privacy policy: https://photos-activities-prod.web.app/privacy
- Delete account: https://photos-activities-prod.web.app/delete-account
- Contact email: bkapsalis@gmail.com. Both stores show the listing's contact
  email publicly. Use a separate address here if you'd rather not show this
  one.

---

## Shared description

Both stores use this as the full description [4000].

```
Find your next outing in the San Francisco Bay Area.

Bill's Bay Area Fun Activities is a photo guide to places worth visiting around the Bay: hiking trails, lakes and parks, museums and historic sites. Every photo was taken on location, so you can see what a place really looks like before you go.

WHAT YOU CAN DO
• Browse photos by category (Hiking Areas, or Museums and Historic Sites) and by place.
• Switch between a photo grid and a large carousel.
• See every photo on a map, and get directions to the spot with one tap.
• Explore the most-liked photos from each place.
• Like photos, leave comments, and join each place's chat to swap tips with other visitors.

EASY TO START
Browse as a guest right away, with no account needed. Or sign in with Google, Apple or email to keep your name on your comments.

FRIENDLY BY DESIGN
Community rules, reporting and blocking, and automatic checks of new photos keep the app a pleasant place. There are no ads, and your information is never sold.

Works on phones and tablets, upright or sideways, and on the web at photos-activities-prod.web.app.
```

---

## Google Play Console

Under **Grow users → Store presence → Main store listing**:

| Field | Text |
|---|---|
| App name [30] | `Bill's Bay Area Fun Activities` |
| Short description [80] | `Real photos of Bay Area hikes, museums and historic sites, with maps.` |
| Full description [4000] | the shared description above |
| App icon | `design/icon/play-store-icon-512.png` |
| Feature graphic | `design/store/feature-graphic-1024x500.png` |
| Phone screenshots | `build/store_shots/play-phone/` |
| 7" and 10" tablet screenshots | `build/store_shots/play-tablet/` |

Under **Store settings**:

- App category: **Travel & Local**
- Tags: Travel guides, Hiking, Museums (pick the closest ones Play offers)
- Contact email: see the top of this file. Website: the website link.

---

## App Store Connect

| Field | Text |
|---|---|
| Name [30] | `Bill's Bay Area Fun Activities` |
| Subtitle [30] | `Hikes, museums & history` |
| Promotional text [170] | `Real photos of Bay Area hikes, museums and historic sites, with a map and directions to every spot. Browse as a guest, no account needed.` |
| Description [4000] | the shared description above |
| Keywords [100] | `hiking,trails,museum,history,san francisco,photos,parks,outdoors,day trip,things to do,map,guide` |
| Support URL | `https://photos-activities-prod.web.app/privacy` (its Contact section has the email address) |
| Marketing URL | `https://photos-activities-prod.web.app` |
| Privacy Policy URL | the privacy policy link |
| Copyright | `2026 Bill Kapsalis` |
| Primary category | **Travel** |
| Secondary category | **Photo & Video** |
| iPhone 6.9" screenshots | `build/store_shots/iphone-6.9/` |
| iPad 13" screenshots | `build/store_shots/ipad-13/` |

Apple already searches the words in the name, so the keywords skip "Bay",
"Area", "Fun" and "Activities". They have no spaces after the commas.

### Notes for the App Review team

Paste into **App Review Information → Notes** [4000]:

```
Thank you for reviewing Bill's Bay Area Fun Activities.

SIGNING IN
Tap "Continue as Guest" on the first screen to use the app without an account. Google, Apple and email sign-in also work.

UPLOADS
During launch, only the moderator (the developer) can upload photos, so reviewers will not see an upload option. Everything else is open to everyone: browsing, the map and directions, likes, comments and each place's chat.

USER-GENERATED CONTENT (Guideline 1.2)
- Report: tap the "⋯" menu ("Report or block") on someone else's photo, comment or chat message, then "Report".
- Block: the same "⋯" menu, then "Block [name]".
- New photos are checked automatically by AI, and the moderator reviews every report.
- Everyone agrees to the Community rules on the sign-in screen ("By continuing, you agree to the Community rules"). The rules are also under Profile.
- Contact: bkapsalis@gmail.com, also listed in the privacy policy.

ACCOUNT DELETION (Guideline 5.1.1(v))
Profile → Delete account. It deletes the account and everything it posted. Guest accounts can try it straight away.
```

If you set up a reviewer account (an email and password), enter it under
**Sign-in required**. Otherwise untick that box: guest access covers the
whole app.

---

## Privacy answers

These come from the privacy policy. Neither store counts Google's handling
of your Firebase data as "sharing", because Google processes it on your
behalf.

### Apple: App Privacy

Under **App Store Connect → App Privacy**:

- **Tracking:** No. The app never tracks people across other companies'
  apps or websites.
- **Data collected:**

| Data type | Linked to the person? | Used for |
|---|---|---|
| Contact Info → Name | Yes | App Functionality |
| Contact Info → Email Address | Yes | App Functionality |
| User Content → Photos or Videos | Yes | App Functionality |
| User Content → Other User Content (comments, chat) | Yes | App Functionality |
| Location → Precise Location (only on photos taken in the app) | Yes | App Functionality |
| Identifiers → User ID | Yes | App Functionality |
| Usage Data → Product Interaction | No | Analytics |
| Diagnostics → Crash Data | Yes | App Functionality |
| Diagnostics → Performance Data | No | Analytics |
| Location → Coarse Location (Analytics works it out from the IP address) | No | Analytics |

### Google Play: Data safety

Under **Policy → App content → Data safety**:

- Collects data: **Yes**. Shares data with third parties: **No**.
- Encrypted in transit: **Yes**.
- People can ask for their data to be deleted: **Yes**. Give the delete
  account link above.
- Data types, all **collected, not shared**:

| Category → type | Required or optional | Purposes |
|---|---|---|
| Personal info → Name | Optional (guests have none) | App functionality, Account management |
| Personal info → Email address | Optional | App functionality, Account management |
| Personal info → User IDs | Required | App functionality, Account management |
| Photos and videos → Photos | Optional | App functionality |
| Location → Precise location | Optional | App functionality |
| Location → Approximate location | Required | Analytics |
| Messages → Other in-app messages (comments, chat) | Optional | App functionality |
| App activity → App interactions | Required | Analytics |
| App info and performance → Crash logs | Required | App functionality, Analytics |
| App info and performance → Diagnostics | Required | Analytics |

### Other Play Console forms

- **Ads:** No ads.
- **App access:** "All or some functionality is restricted". Explain that
  guests can use everything except uploading, which is moderator-only during
  launch, so no login details are needed.
- **Content rating:** answer **Yes** to "users can interact or exchange
  content" and "users can share content". Answer No to violence, gambling
  and the rest.
- **Target audience:** **18 and over** only (the privacy policy says the
  app is not intended for anyone under 18). Answer No to "appeals to
  children".
- **Government apps, Financial features, Health:** No.
