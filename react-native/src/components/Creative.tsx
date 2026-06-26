import React from 'react';
import { Image, ImageResizeMode, Linking, TouchableOpacity } from 'react-native';
import { AdItem } from '../models';

/** Renders a creative image; tapping opens the store (a /c tracker URL, opened verbatim).
 *  The impression is already recorded by the picker. */
export function Creative({
  ad,
  width,
  height,
  resizeMode = 'contain',
  background,
}: {
  ad: AdItem;
  width?: number | string;
  height?: number | string;
  resizeMode?: ImageResizeMode;
  /** Opaque colour painted behind a contain-fit image so a sub-pixel gap never reveals the
   *  host background as a white hairline on iOS. Undefined keeps the bare (transparent) image. */
  background?: string;
}) {
  const onPress = () => {
    if (ad.store) Linking.openURL(ad.store).catch(() => {});
  };
  return (
    <TouchableOpacity
      activeOpacity={0.9}
      onPress={onPress}
      disabled={!ad.store}
      style={{ width: width ?? '100%', height: height ?? '100%', backgroundColor: background }}
    >
      <Image source={{ uri: ad.image }} style={{ width: '100%', height: '100%' }} resizeMode={resizeMode} />
    </TouchableOpacity>
  );
}
