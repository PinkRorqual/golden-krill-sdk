import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards the SDK's Apple privacy manifest (PrivacyInfo.xcprivacy) against drift. It is what
// a consuming app's App Review checks for embedded SDKs, so the declarations must stay
// truthful: no tracking, no IDFA, no per-user identifier; ad-interaction only, not linked +
// not tracking. (The same manifest ships in the React Native SDK; a jest test mirrors this.)
void main() {
  final raw = File('ios/PrivacyInfo.xcprivacy').readAsStringSync();
  // Strip XML comments (prose mentions IDFA etc.), then collapse inter-tag whitespace so we
  // assert on the actual declarations, not the explanation.
  final xml = raw
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(RegExp(r'>\s+<'), '><');

  group('PrivacyInfo.xcprivacy', () {
    test('declares no tracking and no tracking domains', () {
      expect(xml, contains('<key>NSPrivacyTracking</key><false/>'));
      expect(xml, contains('<key>NSPrivacyTrackingDomains</key><array/>'));
    });

    test('never references IDFA or any device/advertising identifier', () {
      expect(xml, isNot(contains('IDFA')));
      expect(xml, isNot(contains('advertisingIdentifier')));
      expect(xml, isNot(contains('DeviceID')));
    });

    test('declares ad interaction as not-linked and not-tracking, app functionality', () {
      expect(xml, contains('NSPrivacyCollectedDataTypeProductInteraction'));
      expect(xml, contains('<key>NSPrivacyCollectedDataTypeLinked</key><false/>'));
      expect(xml, contains('<key>NSPrivacyCollectedDataTypeTracking</key><false/>'));
      expect(xml, contains('NSPrivacyCollectedDataTypePurposeAppFunctionality'));
    });

    test('declares no directly-used required-reason APIs', () {
      expect(xml, contains('<key>NSPrivacyAccessedAPITypes</key><array/>'));
    });

    test('is a well-formed plist', () {
      expect(xml, contains('<plist version="1.0">'));
      expect(xml.trim().endsWith('</plist>'), isTrue);
    });
  });
}
