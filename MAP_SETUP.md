# Map tab — Google Maps API key setup

The Map tab is built and wired on Android, iOS and web. It will show a blank
grey rectangle until you add an API key, because Google refuses to serve map
tiles to an unauthenticated app.

Everything below happens once, in your Google Cloud account.

---

## 1. Enable the three Maps APIs

Console → **APIs & Services → Library**, on project `photos-activities-dev`.
Enable each of:

| API | Used by |
|---|---|
| Maps SDK for Android | the Android app |
| Maps SDK for iOS | the iOS app |
| Maps JavaScript API | the web app |

They are separate products. Enabling one does not enable the others.

Billing is already active on this project. Google's Maps free tier currently
covers a generous number of map loads per month; a development app will not
come close. Set a **budget alert** anyway (Billing → Budgets & alerts) so a
runaway loop cannot surprise you.

## 2. Create the key

**APIs & Services → Credentials → Create credentials → API key.**

One key can serve all three platforms, or you can make three. One is simpler;
three lets you restrict each more tightly and revoke independently.

## 3. Restrict the key — do not skip this

A Maps key is **embedded in the client by design**. Anyone can read it out of
your APK, your IPA, or your web page's source. Secrecy is not what protects
it; **restrictions** are. An unrestricted key can be copied and billed to you.

On the key's page, under **Application restrictions**:

- **Android** — Android apps → add package name `com.billsbayarea.app.dev`
  with your debug SHA-1:
  `B1:48:63:E5:5A:EE:20:75:78:87:10:C0:AB:FC:61:6F:DF:8B:D9:DE`
  (Add the staging/prod package names and your release SHA-1 later.)
- **iOS** — iOS apps → add the bundle ID of each flavour you run:
  `com.billsbayarea.app.dev`, `com.billsbayarea.app.staging` and
  `com.billsbayarea.app` (the same names as the Android packages; until
  October 2026 every iOS flavour shared `com.billsbayarea.billsBayArea`).
- **Web** — Websites → add `http://localhost:5001/*` for development, plus
  your real domain before you ship.

Under **API restrictions**, limit the key to just the three Maps APIs above.

## 4. Put the key in the project

Each platform reads the key from a location git ignores, so the key never
lands in version control.

**Android** — add to `android/local.properties` (already gitignored):

```properties
MAPS_API_KEY=your_key_here
```

**iOS** — edit `ios/Flutter/Maps.xcconfig` (gitignored; created for you):

```
MAPS_API_KEY=your_key_here
```

**Web** — edit `web/index.html` and replace `YOUR_MAPS_API_KEY` in the
`maps.googleapis.com` script tag. This one *is* committed, which is why the
HTTP-referrer restriction in step 3 matters.

Run the web app on the port the key allows. `flutter run -d chrome` picks a
random port, and the map then fails with `RefererNotAllowedMapError`:

```
flutter run -d chrome --web-port 5001 -t lib/main_dev.dart
```

The VS Code web launch configs already pass `--web-port 5001`.

## 5. Restart

A full restart, not a hot reload — native config is read at launch.

---

## How the Map tab behaves

- It plots **only the photos currently on screen**, so changing the category,
  location tab, or search changes the pins. That is why the filters stay
  visible above the map.
- Each pin is a **thumbnail of the photo**, downloaded once and cached, so
  panning never re-fetches.
- **Tapping a pin opens that photo's page**, the same page you get from the
  grid.
- Photos whose location has no coordinates are **left off the map** and
  counted in a note at the bottom, rather than being guessed onto a point
  they were not taken at.

## Coordinates

Photo documents carry `locationLat` / `locationLng`. Three locations were
geocoded via OpenStreetMap and backfilled onto 53 photos:

| Location | Latitude | Longitude | Photos |
|---|---|---|---|
| Filoli Estate, Woodside | 37.469924 | -122.311352 | 28 |
| Vasona Lake County Park | 37.240923 | -121.970109 | 17 |
| Forbes Mill Museum, Los Gatos | 37.222207 | -121.980560 | 8 |

**28 photos labelled "Bay Area Hiking" have no coordinates.** That is a region,
not a place, so there is no honest point to pin them to. They are excluded
from the map. To include them, re-label those photos with real place names.

New uploads do not capture coordinates yet — the upload form has no location
picker, so `locationLat`/`locationLng` are written as null. Adding a picker,
or reading GPS out of photo EXIF, is the next step if you want the map to stay
current automatically.
