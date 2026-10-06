// Browser + actual Edge handler + actual PostgreSQL/PGlite. Supabase transport is emulated.
// Optional deps: npm install --no-save playwright @electric-sql/pglite@0.5.8
import {readFile} from 'node:fs/promises';import http from 'node:http';import path from 'node:path';import assert from 'node:assert/strict';
import {createStudentHandler} from '../supabase/functions/_shared/student-handler.ts';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE||'playwright');
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const {pgcrypto}=await import(process.env.PGLITE_CRYPTO_MODULE||'@electric-sql/pglite/contrib/pgcrypto');
const db=new PGlite({extensions:{pgcrypto}});
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create role supabase_auth_admin;create schema auth;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema public,auth to anon,authenticated,service_role;grant execute on function auth.uid() to anon,authenticated,service_role;
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;create publication supabase_realtime;`);
await db.exec(await readFile(new URL('../supabase/schema.sql',import.meta.url),'utf8'));
const teacherId='11111111-1111-4111-8111-111111111111';
await db.exec(`insert into auth.users values('${teacherId}','a@school.test',now());insert into gamehub_teacher_allowlist values('a@school.test',true);`);
let queue=Promise.resolve();function serial(fn){const task=queue.then(fn);queue=task.catch(()=>{});return task;}
async function dbRPC(name,args,role){return serial(async()=>{try{await db.exec(`reset role;set role ${role};select set_config('request.jwt.claim.sub','${role==='authenticated'?teacherId:''}',false)`);if(!/^(streams_|gamehub_)\w+$/.test(name))throw Error('Bad RPC');const keys=Object.keys(args);const result=await db.query(`select public.${name}(${keys.map((k,i)=>k+'=>$'+(i+1)).join(',')}) as data`,keys.map(k=>args[k]));return Response.json(result.rows[0].data);}catch(e){return Response.json({code:e.code||'XX000',message:e.message},{status:400});}});}
const root=path.resolve('dist'),config=JSON.parse(await readFile('vercel.json','utf8')),security=Object.fromEntries(config.headers[0].headers.map(h=>[h.key,h.value]));
const server=http.createServer(async(req,res)=>{try{let p=new URL(req.url,'http://localhost').pathname;if(p.endsWith('/'))p+='index.html';const file=path.resolve(root,'.'+p);if(!file.startsWith(root+path.sep))throw Error();const data=await readFile(file);res.writeHead(200,{...security,'Content-Type':{'.html':'text/html','.js':'text/javascript','.css':'text/css'}[path.extname(file)]||'text/plain'});res.end(data);}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
const encode=o=>Buffer.from(JSON.stringify(o)).toString('base64url'),token=encode({alg:'HS256',typ:'JWT'})+'.'+encode({sub:teacherId,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600})+'.test';
const edge=createStudentHandler({ALLOWED_ORIGINS:origin,SUPABASE_URL:'https://classroomtest.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test'},async(url,init)=>dbRPC(url.split('/').pop(),JSON.parse(init.body),'service_role'));
const browser=await chromium.launch({headless:true,...(process.env.CHROME_EXECUTABLE?{executablePath:process.env.CHROME_EXECUTABLE}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--disable-gpu']});const errors=[];
async function context(isTeacher=false,viewport={width:1360,height:1000}){
 const ctx=await browser.newContext({viewport});await ctx.routeWebSocket('**',ws=>ws.close());
 if(isTeacher)await ctx.addInitScript(({token,teacherId})=>{if(location.protocol!=='http:')return;localStorage.setItem('sb-classroomtest-auth-token',JSON.stringify({access_token:token,refresh_token:'test',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:teacherId,email:'a@school.test',aud:'authenticated',role:'authenticated'}}));},{token,teacherId});
 await ctx.route('**/js/config.js',route=>route.fulfill({contentType:'text/javascript',body:"window.APP_CONFIG={SUPABASE_URL:'https://classroomtest.supabase.co',SUPABASE_ANON_KEY:'sb_publishable_test'};"}));
 await ctx.route('https://classroomtest.supabase.co/**',async route=>{
  const request=route.request(),url=new URL(request.url()),headers={'access-control-allow-origin':origin,'content-type':'application/json'};
  if(request.method()==='OPTIONS'){await route.fulfill({status:204,headers:{...headers,'access-control-allow-headers':'apikey, authorization, content-type, x-client-info, range, range-unit','access-control-allow-methods':'GET, POST, OPTIONS'}});return;}
  if(url.pathname.includes('/functions/v1/student-api')){const response=await edge(new Request(request.url(),{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:request.postData()}));await route.fulfill({status:response.status,headers:Object.fromEntries(response.headers),body:await response.text()});return;}
  if(url.pathname.includes('/rest/v1/rpc/')){const response=await dbRPC(url.pathname.split('/').pop(),JSON.parse(request.postData()||'{}'),'authenticated');await route.fulfill({status:response.status,headers,body:await response.text()});return;}
  if(url.pathname.includes('/rest/v1/')){const table=url.pathname.split('/').pop();const result=await serial(async()=>{await db.exec(`reset role;set role authenticated;select set_config('request.jwt.claim.sub','${teacherId}',false)`);let sql=`select ${url.searchParams.get('select')||'*'} from public.${table}`;const order=url.searchParams.get('order');if(order)sql+=' order by '+order.replace('.desc',' desc').replace('.asc',' asc');if(url.searchParams.get('limit'))sql+=' limit '+Number(url.searchParams.get('limit'));return (await db.query(sql)).rows;});await route.fulfill({status:200,headers,body:JSON.stringify(result)});return;}
  await route.fulfill({status:200,headers,body:JSON.stringify({id:teacherId,email:'a@school.test'})});
 });ctx.on('page',page=>{page.on('pageerror',e=>errors.push(e.message));page.on('dialog',dialog=>dialog.accept());});return ctx;
}
try{
 const tc=await context(true),sc=await context(false,{width:390,height:844});const t=await tc.newPage(),s=await sc.newPage();
 await t.goto(origin+'/index.html');await t.locator('#dash').waitFor({state:'visible'});assert.equal(await t.locator('#games article').count(),7);
 await t.goto(origin+'/games/streams.html');await t.locator('#roomPassword').fill('room1234');await t.locator('#create').click();await t.locator('#game').waitFor({state:'visible'});
 const code=(await t.locator('#roomCode').textContent()).trim(),joinURL=await t.locator('#joinUrl').inputValue();assert.equal(new URL(joinURL).searchParams.get('room'),code);assert(await t.locator('#qr canvas').count()+await t.locator('#qr img').count()>0);
 await s.goto(joinURL);assert.equal(await s.locator('#room').inputValue(),code);await s.locator('#num').fill('10101');await s.locator('#studentName').fill('<img src=x onerror=alert(1)>');await s.locator('#spw').fill('personal123');await s.locator('#rpw').fill('room1234');await s.locator('#join').click();await s.waitForURL('**/games/streams-student.html');await s.locator('#board .cell').first().waitFor();assert.equal(await s.locator('#board .cell').count(),20);assert(!s.url().includes('token'));
 await serial(async()=>{await db.exec('reset role');await db.query('update streams_rooms set deck=$1 where room_code=$2',[JSON.stringify(['★',...Array.from({length:30},(_,i)=>String(i+1)),...Array.from({length:9},(_,i)=>String(i+11))]),code]);});
 await t.reload();await t.locator('#start:not([disabled])').waitFor();assert.equal(await t.locator('#players img').count(),0);await t.locator('#start').click();
 for(let turn=1;turn<=20;turn++){
  await s.reload();await s.waitForFunction(n=>document.getElementById('turn')?.textContent===String(n),turn);await s.locator('#board .cell').nth(turn-1).click();await s.locator('#confirm').click();await s.waitForFunction(i=>document.querySelectorAll('#board .cell')[i]?.classList.contains('filled'),turn-1);
  await t.reload();if(turn<20){await t.locator('#next:not([disabled])').waitFor();await t.locator('#next').click();await t.waitForFunction(n=>document.getElementById('turn')?.textContent===String(n),turn+1);}if(turn%5===0)console.log('UI turn',turn,'passed');
 }
 await s.reload();await s.locator('#rankingBox').waitFor({state:'visible'});assert.equal(await s.locator('#score').textContent(),'300');await t.locator('#playersTitle').filter({hasText:'최종 순위'}).waitFor();
 assert(await s.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert(await t.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await s.screenshot({path:process.env.SCREENSHOT_DIR?process.env.SCREENSHOT_DIR+'/student-mobile.png':'/tmp/gamehub-student-mobile.png',fullPage:true});await t.screenshot({path:process.env.SCREENSHOT_DIR?process.env.SCREENSHOT_DIR+'/teacher-desktop.png':'/tmp/gamehub-teacher-desktop.png',fullPage:true});
 await t.goto(origin+'/teacher.html');await t.locator('#rows tr').waitFor();assert.equal(await t.locator('#rows img').count(),0);await t.locator('#rows button').click();await t.waitForFunction(()=>document.getElementById('rows')?.textContent.includes('학생이 없습니다'));await s.reload();await s.locator('#rejoin').waitFor({state:'visible'});
 assert.deepEqual(errors,[]);console.log('PASS browser: dashboard, QR, mobile join, XSS text safety, 20 placements, refresh recovery, star scoring, ranking, student deletion, no horizontal overflow, no page errors.');
}finally{await browser.close();server.close();await db.close();}
