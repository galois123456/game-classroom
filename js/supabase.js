// Shared teacher Auth client. The build can generate config.js from public env vars.
const cfg=window.APP_CONFIG;
window.configReady=Boolean(cfg && /^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(cfg.SUPABASE_URL) && !cfg.SUPABASE_URL.includes('YOUR_') && !cfg.SUPABASE_ANON_KEY.includes('YOUR_'));
window.sb = window.configReady && window.supabase ? window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY) : null;
