// @ts-check
/** @typedef {'narrow'|'balanced'|'wide'} Tier */
export const TIERS = /** @type {const} */ ({
  narrow: { width: 10, title: 'Narrow range', tagline: 'More concentration. More tending.', description: 'Small price changes can move the position out of range. Greater sensitivity to divergence loss.' },
  balanced: { width: 30, title: 'Balanced range', tagline: 'A little room to bloom.', description: 'A wider price window than the narrow tier. Still exposed to price movement and divergence loss.' },
  wide: { width: 65, title: 'Wide range', tagline: 'More room. Less concentration.', description: 'More price movement fits inside the range. Wider does not mean risk-free or protected from loss.' }
});
/** Educational range only; no market forecast or deposit calculation.
 * @param {number} value */
export function rangeModel(value) {
  const width = Math.max(5, Math.min(80, Number.isFinite(value) ? Math.round(value) : 30));
  const progress = (width - 5) / 75;
  const tier = /** @type {Tier} */ (width < 20 ? 'narrow' : width < 50 ? 'balanced' : 'wide');
  return { width, progress, tier, lower: 1 - width / 100, upper: 1 + width / 100, flowerScale: .62 + progress * .65, chartHalf: width * 3, ...{ explanation: TIERS[tier] } };
}
/** @param {unknown} value */
export function addressValue(value) {
  return typeof value === 'string' && /^0x[0-9a-fA-F]{40}$/.test(value) && !/^0x0{40}$/i.test(value) ? value : null;
}
/** Only HTTPS destinations, or relative paths on this origin, may enter links or images.
 * @param {unknown} value
 * @param {string} origin */
export function safeUrl(value, origin) {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const url = new URL(value, origin);
    return (url.protocol === 'https:' || (url.origin === origin && url.protocol === 'http:')) && !url.username && !url.password ? url.href : null;
  } catch { return null; }
}
/** @param {unknown} value */
export function marketNumber(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
}
/** @param {unknown} value
 * @param {string} origin */
export function normalizeCoin(value, origin) {
  const coin = value && typeof value === 'object' ? /** @type {Record<string,unknown>} */ (value) : {};
  const market = coin.market && typeof coin.market === 'object' ? /** @type {Record<string,unknown>} */ (coin.market) : {};
  return {token: addressValue(coin.token), coinUrl: safeUrl(coin.coinUrl, origin), chartUrl: safeUrl(coin.chartUrl, origin), logo: safeUrl(coin.logo, origin), status: typeof coin.status === 'string' ? coin.status.slice(0, 80) : null, market: {priceUsd: marketNumber(market.priceUsd), marketCap: marketNumber(market.marketCap), volume24h: marketNumber(market.volume24h)}};
}
/** @param {number} value
 * @param {boolean} [price] */
export function formatUsd(value, price = false) {
  if (price && value > 0 && value < .000001) return '$' + value.toPrecision(3);
  return new Intl.NumberFormat('en-US', {style:'currency',currency:'USD',notation:price?'standard':'compact',maximumFractionDigits:price && value < 1 ? 8 : 2}).format(value);
}
export const SITE_URL = 'https://sunflowergardensun.si-md.xyz/';
export const SHARE_TEXTS = {
  garden: 'Grow your liquidity. Let bees do the math. Explore Sunflower Garden, the $SUN range sandbox for the IMD ecosystem. No promises, just pollen.',
  tool: 'Narrow range or room to bloom? Try the interactive Sunflower Plot and learn the tradeoffs. Your garden. Your decisions. $SUN / IMD',
  sun: 'Meet Sunflower Garden ($SUN): a fixed-supply token for the IMD ecosystem on Robinhood Chain. Explore the mechanics before you plant.'
};
