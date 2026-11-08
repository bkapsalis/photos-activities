import 'package:bills_bay_area/core/widgets/orientation_policy.dart';
import 'package:bills_bay_area/core/widgets/shared_widgets.dart';
import 'package:bills_bay_area/features/home/widgets/web_home_layout.dart';
import 'package:bills_bay_area/features/picture_chat/picture_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Screen sizes in logical pixels, upright.
const _phone = Size(412, 915); // Pixel 9 Pro XL
const _iPadMini = Size(744, 1133);
const _pixelTablet = Size(800, 1280);
const _iPad11 = Size(834, 1194); // iPad Air and Pro 11"
const _iPad13 = Size(1032, 1376); // iPad Pro 13"
const _foldOpen = Size(701, 841); // Pixel Fold, unfolded

Size _sideways(Size s) => Size(s.height, s.width);

void main() {
  group('which way the screen may turn', () {
    test('a phone is a phone either way up', () {
      expect(isPhoneSized(_phone), isTrue);
      expect(isPhoneSized(_sideways(_phone)), isTrue);
    });

    test('tablets and an unfolded foldable are not', () {
      for (final size in [_iPadMini, _pixelTablet, _iPad11, _iPad13]) {
        expect(isPhoneSized(size), isFalse, reason: '$size');
        expect(isPhoneSized(_sideways(size)), isFalse, reason: '$size');
      }
      expect(isPhoneSized(_foldOpen), isFalse);
    });

    test('phones stay upright; tablets are left free', () {
      expect(orientationsFor(phone: true), [DeviceOrientation.portraitUp]);
      expect(orientationsFor(phone: false), isEmpty);
    });

    testWidgets('the policy tells the platform, and again when a foldable '
        'opens', (tester) async {
      final requests = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            requests.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      Widget at(Size size) => MediaQuery(
        data: MediaQueryData(size: size),
        child: const OrientationPolicy(child: SizedBox()),
      );

      await tester.pumpWidget(at(const Size(373, 841))); // folded
      await tester.pumpWidget(at(_sideways(const Size(373, 841))));
      await tester.pumpWidget(at(_foldOpen));

      // Turning the folded phone asks nothing new; opening it frees it.
      expect(requests, [
        ['DeviceOrientation.portraitUp'],
        <String>[],
      ]);
    });
  });

  group('the wide layout on tablets', () {
    test('upright tablets get a two-row top bar and no sidebar', () {
      for (final size in [_iPadMini, _pixelTablet, _iPad11, _foldOpen]) {
        final layout = wideTopBarLayout(size.width);
        expect(layout.oneRow, isFalse, reason: '$size');
        expect(wideLayoutShowsSidebar(size.width), isFalse, reason: '$size');
      }
    });

    test('sideways tablets keep the sidebar; the biggest gets one row', () {
      for (final size in [_pixelTablet, _iPad11, _iPad13]) {
        expect(
          wideLayoutShowsSidebar(_sideways(size).width),
          isTrue,
          reason: '$size',
        );
      }
      expect(wideTopBarLayout(_sideways(_pixelTablet).width).oneRow, isFalse);
      expect(wideTopBarLayout(_sideways(_iPad13).width).oneRow, isTrue);
    });

    test('the narrowest windows show the upload buttons as icons', () {
      expect(wideTopBarLayout(600).iconOnlyActions, isTrue);
      expect(wideTopBarLayout(_iPadMini.width).iconOnlyActions, isTrue);
      expect(wideTopBarLayout(_pixelTablet.width).iconOnlyActions, isFalse);
    });
  });

  group('the photo screen', () {
    test('an upright tablet shows the photo across the top', () {
      expect(showsPhotoBesideChat(_pixelTablet, isWeb: false), isFalse);
      expect(showsPhotoBesideChat(_iPad13, isWeb: false), isFalse);
    });

    test('a sideways tablet shows it beside the comments', () {
      expect(showsPhotoBesideChat(_sideways(_iPad11), isWeb: false), isTrue);
      expect(showsPhotoBesideChat(_sideways(_iPadMini), isWeb: false), isTrue);
    });

    test('a browser goes by width alone, and a phone never', () {
      expect(showsPhotoBesideChat(const Size(800, 1000), isWeb: true), isTrue);
      expect(showsPhotoBesideChat(const Size(500, 900), isWeb: true), isFalse);
      expect(showsPhotoBesideChat(_phone, isWeb: false), isFalse);
    });
  });

  group('ReadableWidth', () {
    Future<Size> childSize(WidgetTester tester, Size screen) async {
      await tester.binding.setSurfaceSize(screen);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const key = Key('content');
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: ReadableWidth(
            child: ColoredBox(key: key, color: Colors.red),
          ),
        ),
      );
      return tester.getSize(find.byKey(key));
    }

    testWidgets('caps a tablet page at 720, centred', (tester) async {
      final size = await childSize(tester, _sideways(_pixelTablet));
      expect(size.width, 720);
      expect(
        tester.getTopLeft(find.byKey(const Key('content'))).dx,
        (1280 - 720) / 2,
      );
    });

    testWidgets('leaves a phone page alone', (tester) async {
      final size = await childSize(tester, _phone);
      expect(size.width, _phone.width);
    });
  });
}
