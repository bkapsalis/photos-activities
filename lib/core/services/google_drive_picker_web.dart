import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../config/env_config.dart';
import 'picked_image.dart';

/// Google Drive on the web, through Google's own picker.
///
/// The person signs in with Google and lets the app open "only the specific
/// Drive files you use with this app" (the drive.file scope), then picks
/// photos in Google's window; the app can read those photos and nothing else
/// in their Drive. That is also why a whole folder cannot be picked: under
/// this scope Google opens the folder to the app but not the files in it.
/// Wider access (drive.readonly) is a restricted scope, which Google only
/// grants after a paid security review.
///
/// Needs, in the environment's Google Cloud project: the Google Picker and
/// Google Drive APIs enabled, [EnvConfig.googlePickerApiKey], and this site
/// among the authorized JavaScript origins of the OAuth web client
/// ([EnvConfig.googleServerClientId]).

const _gapiScript = 'https://apis.google.com/js/api.js';
const _identityScript = 'https://accounts.google.com/gsi/client';
const _driveFileScope = 'https://www.googleapis.com/auth/drive.file';
const _photoTypes = 'image/jpeg,image/png,image/webp,image/heic,image/heif';

bool get isConfigured => EnvConfig.instance.googlePickerApiKey != null;

Future<void>? _ready;
JSObject? _tokenClient;
Completer<String?>? _tokenWanted;
String? _token;
DateTime _tokenExpires = DateTime(0);

/// Loads Google's scripts and the picker, once, so a later tap can open the
/// sign-in window straight away. Safe to call any number of times.
Future<void> prepare() {
  if (!isConfigured) return Future.value();
  return _ready ??= _load().catchError((Object e) {
    _ready = null; // A failed load (offline, say) may be retried.
    throw e;
  });
}

Future<void> _load() async {
  await Future.wait([
    _loadScript(_gapiScript, () => globalContext.has('gapi')),
    _loadScript(_identityScript, () {
      final google = globalContext['google'] as JSObject?;
      final accounts = google?['accounts'] as JSObject?;
      return accounts?.has('oauth2') ?? false;
    }),
  ]);
  final pickerLoaded = Completer<void>();
  _gapi.callMethod(
    'load'.toJS,
    'picker'.toJS,
    (() => pickerLoaded.complete()).toJS,
  );
  await pickerLoaded.future;

  final config =
      {
            'client_id': EnvConfig.instance.googleServerClientId,
            'scope': _driveFileScope,
            // Offer the account already signed in to the app first.
            'login_hint': FirebaseAuth.instance.currentUser?.email ?? '',
          }.jsify()!
          as JSObject;
  config['callback'] = _onToken.toJS;
  config['error_callback'] = _onTokenError.toJS;
  _tokenClient = _oauth2.callMethod<JSObject>('initTokenClient'.toJS, config);
}

/// Adds [src] to the page unless it is there already, and waits until
/// [isLoaded]. Google's sign-in script is usually there already: the app's
/// own Google sign-in loads it, and loading it twice makes that package
/// report its load twice, which throws.
Future<void> _loadScript(String src, bool Function() isLoaded) async {
  if (isLoaded()) return;
  if (web.document.querySelector('script[src="$src"]') == null) {
    web.document.head!.append(
      web.HTMLScriptElement()
        ..src = src
        ..async = true,
    );
  }
  // Polled rather than awaited by event: a tag someone else added may have
  // finished loading already, or may still be on its way.
  for (var waited = 0; !isLoaded(); waited++) {
    if (waited == 150) throw StateError('$src did not load');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

JSObject get _google => globalContext['google']! as JSObject;
JSObject get _gapi => globalContext['gapi']! as JSObject;
JSObject get _oauth2 =>
    (_google['accounts']! as JSObject)['oauth2']! as JSObject;
JSObject get _picker => _google['picker']! as JSObject;

/// Photos picked in Drive, at most [limit], ticked; empty if none were.
Future<List<PickedImage>> pickPhotos({required int limit}) async {
  if (!isConfigured) {
    throw StateError('Google Drive is not set up for this site');
  }
  if (_tokenClient == null) await prepare();
  // Nothing may be awaited between the tap and asking for the sign-in
  // window: the browser lets a page open one only in the moments after a
  // tap. Hence the scripts are loaded ahead, by [prepare].
  final token = _validToken() ?? await _requestToken();
  if (token == null) return [];

  final picked = await _showPicker(token, limit);
  final ids = [for (final doc in picked) (doc['id']! as JSString).toDart];
  // The picker hands back no previews of Drive files; Drive itself has them.
  final previews = await Future.wait([
    for (final id in ids) _previewLink(id, token),
  ]);
  return [
    for (final (i, doc) in picked.indexed)
      PickedImage(
        name: (doc['name'] as JSString?)?.toDart ?? 'photo',
        preview: null,
        previewBuilder: previews[i] == null
            ? null
            : (_) => _drivePreview(previews[i]!),
        read: () => _download(ids[i], _validToken() ?? token),
      ),
  ];
}

/// Drive's preview at [url], as a plain <img>. Drive's preview server sends
/// no CORS headers, so Flutter cannot draw the picture itself, and it
/// refuses pages that say which site is asking, so this one does not.
///
/// Taps go to the tile underneath, which ticks the photo: Flutter would
/// otherwise hand them to the <img>, and the browser would offer to save it.
Widget _drivePreview(String url) => IgnorePointer(
  child: HtmlElementView.fromTagName(
    key: ValueKey(url),
    tagName: 'img',
    onElementCreated: (element) {
      (element as web.HTMLImageElement)
        ..referrerPolicy = 'no-referrer'
        // No broken-image icon if it fails; the tile stays blank.
        ..alt = ''
        ..src = url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.pointerEvents = 'none';
    },
  ),
);

String? _validToken() =>
    _token != null && DateTime.now().isBefore(_tokenExpires) ? _token : null;

Future<String?> _requestToken() {
  final wanted = _tokenWanted = Completer<String?>();
  _tokenClient!.callMethod('requestAccessToken'.toJS);
  return wanted.future;
}

void _onToken(JSObject response) {
  final wanted = _tokenWanted;
  _tokenWanted = null;
  final token = (response['access_token'] as JSString?)?.toDart;
  final granted =
      token != null &&
      _oauth2
          .callMethod<JSBoolean>(
            'hasGrantedAllScopes'.toJS,
            response,
            _driveFileScope.toJS,
          )
          .toDart;
  if (granted) {
    final seconds = int.tryParse('${response['expires_in'].dartify()}') ?? 0;
    _token = token;
    // A minute's grace, so a token is not used as it runs out.
    _tokenExpires = DateTime.now().add(Duration(seconds: seconds - 60));
  }
  wanted?.complete(granted ? token : null);
}

void _onTokenError(JSObject error) {
  final wanted = _tokenWanted;
  _tokenWanted = null;
  final type = (error['type'] as JSString?)?.toDart;
  // Closing Google's window is a change of mind; a blocked one is a fault.
  if (type == 'popup_closed') {
    wanted?.complete(null);
  } else {
    wanted?.completeError(StateError('Google sign-in failed: $type'));
  }
}

/// Shows Google's picker over the page and answers with the documents
/// picked, or none if it was closed.
Future<List<JSObject>> _showPicker(String token, int limit) {
  final done = Completer<List<JSObject>>();
  final view =
      (_picker['DocsView']! as JSFunction).callAsConstructor<JSObject>(
          (_picker['ViewId']! as JSObject)['DOCS'],
        )
        ..callMethod('setIncludeFolders'.toJS, true.toJS)
        ..callMethod('setMimeTypes'.toJS, _photoTypes.toJS)
        ..callMethod('setParent'.toJS, 'root'.toJS)
        ..callMethod(
          'setMode'.toJS,
          (_picker['DocsViewMode']! as JSObject)['GRID'],
        );

  void onPicked(JSObject data) {
    final action = (data['action'] as JSString?)?.toDart;
    if (action == 'picked') {
      final docs = (data['docs']! as JSArray<JSObject>).toDart;
      if (!done.isCompleted) done.complete(docs);
    } else if (action == 'cancel') {
      if (!done.isCompleted) done.complete(const []);
    }
  }

  final builder = (_picker['PickerBuilder']! as JSFunction)
      .callAsConstructor<JSObject>();
  builder
    ..callMethod('addView'.toJS, view)
    ..callMethod(
      'enableFeature'.toJS,
      (_picker['Feature']! as JSObject)['MULTISELECT_ENABLED'],
    )
    ..callMethod('setMaxItems'.toJS, limit.toJS)
    ..callMethod('setOAuthToken'.toJS, token.toJS)
    ..callMethod(
      'setDeveloperKey'.toJS,
      EnvConfig.instance.googlePickerApiKey!.toJS,
    )
    ..callMethod(
      'setAppId'.toJS,
      EnvConfig.instance.googleCloudProjectNumber.toJS,
    )
    ..callMethod('setTitle'.toJS, 'Choose photos'.toJS)
    ..callMethod('setCallback'.toJS, onPicked.toJS);
  builder
      .callMethod<JSObject>('build'.toJS)
      .callMethod('setVisible'.toJS, true.toJS);
  return done.future;
}

/// A link to Drive's preview of photo [id], [PickedImage.previewWidth]
/// pixels across, or null if it has none or Drive could not be asked. The
/// link is signed, so it needs no sign-in to show, and lasts some hours.
/// (The picker's own answer has no previews of Drive files.)
Future<String?> _previewLink(String id, String token) async {
  try {
    final response = await web.window
        .fetch(
          'https://www.googleapis.com/drive/v3/files/$id'
                  '?fields=thumbnailLink&supportsAllDrives=true'
              .toJS,
          _withToken(token),
        )
        .toDart;
    if (!response.ok) return null;
    final file = await response.json().toDart as JSObject;
    // Links end in the size asked for ("=s220"); any size may be asked.
    return (file['thumbnailLink'] as JSString?)?.toDart.replaceFirst(
      RegExp(r'=s\d+$'),
      '=s${PickedImage.previewWidth}',
    );
  } catch (_) {
    return null; // A photo without a preview is still a photo.
  }
}

Future<Uint8List> _download(String id, String token) async {
  final response = await web.window
      .fetch(
        'https://www.googleapis.com/drive/v3/files/$id'
                '?alt=media&supportsAllDrives=true'
            .toJS,
        _withToken(token),
      )
      .toDart;
  if (!response.ok) {
    throw StateError('Drive answered ${response.status} for $id');
  }
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

web.RequestInit _withToken(String token) => web.RequestInit(
  headers: {'Authorization': 'Bearer $token'}.jsify()! as JSObject,
);
