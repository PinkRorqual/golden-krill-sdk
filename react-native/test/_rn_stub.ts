// Lightweight react-native mock for node-env tests. The logic tests only touch
// Platform.OS; the component tests render the primitives as host elements (so
// react-test-renderer can find them by type and call their onPress/onLoad props),
// which avoids pulling in the full RN runtime / a metro babel preset.
import React from 'react';

const host = (name: string) => {
  const C = (props: any) => React.createElement(name, props, props?.children);
  C.displayName = name;
  return C;
};

export const View = host('View');
export const Text = host('Text');
export const Image = host('Image');
export const Modal = host('Modal');
export const Pressable = host('Pressable');
export const TouchableOpacity = host('TouchableOpacity');
export const ActivityIndicator = host('ActivityIndicator');

export const StyleSheet = {
  create: <T,>(styles: T): T => styles,
  absoluteFill: {} as any,
};

export const Linking = { openURL: jest.fn(() => Promise.resolve(true)) };

export const BackHandler = {
  addEventListener: (_event: string, _handler: () => boolean) => ({ remove: () => {} }),
};

export const Platform = { OS: 'android' as const };

// Type-only in the SDK source; exported as a harmless alias for the value import.
export type ImageResizeMode = 'contain' | 'cover' | 'stretch' | 'center' | 'repeat';
