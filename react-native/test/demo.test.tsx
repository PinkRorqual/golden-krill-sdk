import React from 'react';
import TestRenderer, { act } from 'react-test-renderer';
import {
  GoldenKrillAds,
  GoldenKrillBanner,
  GoldenKrillInterstitial,
  GoldenKrillRewarded,
} from '../src/index';
import { makeAds } from './_helpers';

// Integration smoke that mirrors the shipped demo's wiring: ONE GoldenKrillAds drives all
// four surfaces (banner, mrec, interstitial, rewarded) at once, resolved through the public
// package entrypoint (src/index). Offline (empty fill), so slots collapse gracefully. This
// proves the exported surfaces compose + render + tear down together without throwing.
// (It composes the public API rather than importing the demo App directly: the demo relies
// on metro's lenient JSX + Expo runtime, neither of which ts-jest provides.)
const flushAll = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };

function DemoHarness({ ads, show }: { ads: GoldenKrillAds; show: boolean }) {
  return (
    <>
      <GoldenKrillBanner ads={ads} slot="banner" showBadge paidBuilder={async () => null} />
      <GoldenKrillBanner ads={ads} slot="mrec" showBadge paidBuilder={async () => null} />
      <GoldenKrillInterstitial ads={ads} visible={show} onClose={() => {}} closeAfterMs={0} />
      <GoldenKrillRewarded ads={ads} visible={show} onClose={() => {}} durationMs={100} />
    </>
  );
}

describe('SDK integration smoke (demo wiring)', () => {
  it('mounts all four surfaces from the public entrypoint and tears down cleanly', async () => {
    jest.useFakeTimers();
    const ads = makeAds({ a: [], o: [] }, { reserve_share: false, banner_rotation_sec: 99999 });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<DemoHarness ads={ads} show={false} />); });
    await act(async () => { await flushAll(); });
    await act(async () => { r.update(<DemoHarness ads={ads} show />); await flushAll(); }); // open full-screens
    await act(async () => { jest.advanceTimersByTime(200); });
    await act(async () => { r.update(<DemoHarness ads={ads} show={false} />); await flushAll(); }); // dismiss
    act(() => r.unmount());
    jest.useRealTimers();
    expect(true).toBe(true); // reaching here = the whole lifecycle ran without throwing
  });
});
