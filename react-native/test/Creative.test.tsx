import React from 'react';
import TestRenderer, { act } from 'react-test-renderer';
import { Linking } from 'react-native';
import { Creative } from '../src/components/Creative';

describe('Creative', () => {
  beforeEach(() => (Linking.openURL as jest.Mock).mockClear());

  it('renders the image and opens the store on tap', () => {
    let r!: TestRenderer.ReactTestRenderer;
    act(() => { r = TestRenderer.create(<Creative ad={{ id: 1, image: 'https://i', store: 'https://store/app' }} />); });
    expect(r.root.findAll((n) => n.type === 'Image').length).toBe(1);
    const touch = r.root.find((n) => n.type === 'TouchableOpacity');
    act(() => touch.props.onPress());
    expect(Linking.openURL).toHaveBeenCalledWith('https://store/app');
  });

  it('is disabled and opens nothing without a store', () => {
    let r!: TestRenderer.ReactTestRenderer;
    act(() => { r = TestRenderer.create(<Creative ad={{ id: 1, image: 'https://i' }} />); });
    const touch = r.root.find((n) => n.type === 'TouchableOpacity');
    expect(touch.props.disabled).toBe(true);
    act(() => touch.props.onPress());
    expect(Linking.openURL).not.toHaveBeenCalled();
  });

  it('paints an opaque backing when background is set (iOS white-hairline fix)', () => {
    let r!: TestRenderer.ReactTestRenderer;
    act(() => { r = TestRenderer.create(<Creative ad={{ id: 1, image: 'https://i' }} background="#123456" />); });
    const touch = r.root.find((n) => n.type === 'TouchableOpacity');
    expect(touch.props.style.backgroundColor).toBe('#123456');
  });

  it('has no backing when background is unset (default behaviour unchanged)', () => {
    let r!: TestRenderer.ReactTestRenderer;
    act(() => { r = TestRenderer.create(<Creative ad={{ id: 1, image: 'https://i' }} />); });
    const touch = r.root.find((n) => n.type === 'TouchableOpacity');
    expect(touch.props.style.backgroundColor).toBeUndefined();
  });
});
