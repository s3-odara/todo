export function monotonic_microseconds() {
  return Math.trunc(globalThis.performance.now() * 1000);
}
