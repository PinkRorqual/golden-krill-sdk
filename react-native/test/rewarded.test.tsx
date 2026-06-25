import React from 'react';
import TestRenderer, { act } from 'react-test-renderer';
import { Linking } from 'react-native';
import { GoldenKrillRewarded } from '../src/components/GoldenKrillRewarded';
import { makeAds } from './_helpers';

const flushAll = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };
const closeBtn = (r: TestRenderer.ReactTestRenderer) =>
  r.root.findAll((n) => n.type === 'Pressable' && n.props.accessibilityLabel === 'Close');

describe('GoldenKrillRewarded', () => {
  it('spins until loaded, runs the countdown, then earns on close', async () => {
    jest.useFakeTimers();
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false });
    const onClose = jest.fn();
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => {
      r = TestRenderer.create(<GoldenKrillRewarded ads={ads} visible onClose={onClose} durationMs={300} />);
    });
    await act(async () => { await flushAll(); }); // picks the ad
    expect(r.root.findAll((n) => n.type === 'ActivityIndicator').length).toBe(1); // not loaded yet
    const img = r.root.findAll((n) => n.type === 'Image').find((n) => typeof n.props.onLoad === 'function');
    await act(async () => { img!.props.onLoad(); }); // image ready -> countdown starts
    expect(closeBtn(r).length).toBe(0); // still counting down
    await act(async () => { jest.advanceTimersByTime(350); }); // past the 300ms countdown
    expect(closeBtn(r).length).toBe(1); // reward earned -> dismissable
    act(() => closeBtn(r)[0].props.onPress());
    expect(onClose).toHaveBeenCalledWith(true);
    jest.useRealTimers();
  });

  it('collapses with onClose(false) on no-fill', async () => {
    const ads = makeAds({ a: [], o: [] }, { reserve_share: false });
    const onClose = jest.fn();
    await act(async () => { TestRenderer.create(<GoldenKrillRewarded ads={ads} visible onClose={onClose} />); });
    await act(async () => { await flushAll(); });
    expect(onClose).toHaveBeenCalledWith(false);
  });

  it('renders badge + opens the store on creative tap', async () => {
    jest.useFakeTimers();
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false });
    const onClose = jest.fn();
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillRewarded ads={ads} visible onClose={onClose} durationMs={300} showBadge />); });
    await act(async () => { await flushAll(); });
    const img = r.root.findAll((n) => n.type === 'Image').find((n) => typeof n.props.onLoad === 'function');
    await act(async () => { img!.props.onLoad(); });
    const touch = r.root.find((n) => n.type === 'TouchableOpacity');
    act(() => touch.props.onPress());
    expect(Linking.openURL).toHaveBeenCalledWith('s'); // store url 's'
    const badge = r.root.findAll((n) => n.type === 'Pressable' && n.props.accessibilityLabel !== 'Close')[0];
    act(() => badge.props.onPress());
    jest.useRealTimers();
  });

  it('resets and collapses when visible turns false', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false });
    const onClose = jest.fn();
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillRewarded ads={ads} visible onClose={onClose} />); });
    await act(async () => { await flushAll(); });
    await act(async () => { r.update(<GoldenKrillRewarded ads={ads} visible={false} onClose={onClose} />); });
    expect(r.toJSON()).toBeNull();
  });
});
