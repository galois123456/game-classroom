function normalizeOrigin(value, label) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  let url;
  try {
    url = new URL(raw.includes('://') ? raw : `https://${raw}`);
  } catch {
    throw new Error(`${label} must be a valid site origin or hostname.`);
  }
  const localHttp = url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !localHttp) || url.username || url.password ||
      url.pathname !== '/' || url.search || url.hash) {
    throw new Error(`${label} must be an HTTPS origin without a path, query, or fragment.`);
  }
  return url.origin;
}

export function resolvePublicAppUrl(explicitUrl, productionHost) {
  return normalizeOrigin(explicitUrl, 'PUBLIC_APP_URL') ||
    normalizeOrigin(productionHost, 'VERCEL_PROJECT_PRODUCTION_URL');
}
