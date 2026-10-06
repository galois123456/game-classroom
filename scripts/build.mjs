import {cp,mkdir,rm,writeFile,readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {resolvePublicAppUrl} from './public-url.mjs';
await rm('dist',{recursive:true,force:true});await mkdir('dist');
for(const path of ['index.html','student.html','teacher.html','games','css','js','vendor'])await cp(path,'dist/'+path,{recursive:true});
const context={window:{}};vm.runInNewContext(await readFile('js/config.js','utf8'),context);
const config={SUPABASE_URL:process.env.PUBLIC_SUPABASE_URL||context.window.APP_CONFIG.SUPABASE_URL,
 SUPABASE_ANON_KEY:process.env.PUBLIC_SUPABASE_ANON_KEY||context.window.APP_CONFIG.SUPABASE_ANON_KEY,
 PUBLIC_APP_URL:resolvePublicAppUrl(process.env.PUBLIC_APP_URL,process.env.VERCEL_PROJECT_PRODUCTION_URL)};
if(config.SUPABASE_ANON_KEY.startsWith('sb_secret_'))throw new Error('Secret key must NEVER be shipped to a browser. Use publishable or anon key.');
if(config.SUPABASE_ANON_KEY.split('.').length===3){let payload;try{payload=JSON.parse(Buffer.from(config.SUPABASE_ANON_KEY.split('.')[1],'base64url'));}catch{throw new Error('Invalid public JWT key');}if(payload.role!=='anon')throw new Error('Only an anon JWT may be used in the browser.');}
if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(config.SUPABASE_URL)&&!config.SUPABASE_URL.includes('YOUR_PROJECT'))throw new Error('Use your https://PROJECT.supabase.co project URL.');
if(!config.SUPABASE_ANON_KEY.startsWith('sb_publishable_')&&config.SUPABASE_ANON_KEY.split('.').length!==3&&!config.SUPABASE_ANON_KEY.includes('YOUR_'))throw new Error('Use a Supabase publishable or legacy anon key.');
await writeFile('dist/js/config.js','window.APP_CONFIG = '+JSON.stringify(config,null,2)+';\n');
console.log(config.SUPABASE_URL.includes('YOUR_')||config.SUPABASE_ANON_KEY.includes('YOUR_')?'Build OK. CONNECTION NOT CONFIGURED: set the two PUBLIC_SUPABASE_* variables.':'Build OK. Static output: dist/');
if(config.PUBLIC_APP_URL)console.log('QR public site:',config.PUBLIC_APP_URL);
