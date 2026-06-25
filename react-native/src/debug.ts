// Opt-in debug logging. Off by default, zero cost when off (the message is only built
// when enabled). Set GoldenKrillDebug.enabled = true and grep your console for [GoldenKrill].
export const GoldenKrillDebug = { enabled: false };

export function gkLog(message: () => string): void {
  if (GoldenKrillDebug.enabled) {
    // eslint-disable-next-line no-console
    console.log(`[GoldenKrill] ${message()}`);
  }
}
