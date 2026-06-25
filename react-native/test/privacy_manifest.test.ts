import { readFileSync } from 'fs';
import { join } from 'path';

// Guards the SDK's Apple privacy manifest (PrivacyInfo.xcprivacy) against drift. It is the
// thing a consuming app's App Review checks for embedded SDKs, so these declarations must
// stay truthful: no tracking, no IDFA, no per-user identifier; ad-interaction only, not
// linked + not tracking. (Same manifest ships in the Flutter SDK; a Dart test mirrors this.)
const raw = readFileSync(join(__dirname, '..', 'ios', 'PrivacyInfo.xcprivacy'), 'utf8');
// Strip XML comments (they explain the policy and mention IDFA etc.), then collapse
// inter-tag whitespace, so assertions test the actual declarations not the prose.
const xml = raw.replace(/<!--[\s\S]*?-->/g, '').replace(/>\s+</g, '><');

describe('PrivacyInfo.xcprivacy (RN)', () => {
  it('declares no tracking and no tracking domains', () => {
    expect(xml).toContain('<key>NSPrivacyTracking</key><false/>');
    expect(xml).toContain('<key>NSPrivacyTrackingDomains</key><array/>');
  });

  it('never references IDFA or any device/advertising identifier', () => {
    expect(xml).not.toMatch(/IDFA|advertisingIdentifier|NSPrivacyCollectedDataTypeDeviceID/);
  });

  it('declares ad interaction as not-linked and not-tracking, for app functionality', () => {
    expect(xml).toContain('NSPrivacyCollectedDataTypeProductInteraction');
    expect(xml).toContain('<key>NSPrivacyCollectedDataTypeLinked</key><false/>');
    expect(xml).toContain('<key>NSPrivacyCollectedDataTypeTracking</key><false/>');
    expect(xml).toContain('NSPrivacyCollectedDataTypePurposeAppFunctionality');
  });

  it('declares no directly-used required-reason APIs (persistence is shared_preferences/AsyncStorage)', () => {
    expect(xml).toContain('<key>NSPrivacyAccessedAPITypes</key><array/>');
  });

  it('is a well-formed plist', () => {
    expect(xml).toContain('<plist version="1.0">');
    expect(xml.trim().endsWith('</plist>')).toBe(true);
  });
});
