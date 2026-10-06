import {$,el,busy,showError,clearMessage,configured,rpc} from './common.js';
import {GAMES} from './games/registry.js';
let recovering=location.hash.includes('type=recovery');
async function showDashboard(){
 const {data:{session}}=await sb.auth.getSession();
 if(!session)return;
 if(!await rpc('gamehub_is_teacher'))throw new Error('교사 승인 또는 이메일 인증이 필요합니다. 관리자에게 이메일 등록을 요청하세요.');
 $('auth').classList.add('hidden');$('dash').classList.remove('hidden');$('who').textContent=session.user.email;
 $('games').replaceChildren(...GAMES.map(g=>{const article=el('article',undefined,'card game');article.append(el('span',g.icon,'game-icon'),el('h2',g.title),el('p',g.enabled?`${g.description} · ${g.version}`:'다음 게임을 준비하고 있습니다.','muted small'));const link=el(g.enabled?'a':'button',g.enabled?'게임 열기 →':'준비 중',g.enabled?'button':'secondary');if(g.enabled)link.href=g.teacherUrl;else link.disabled=true;article.append(link);return article;}));
}
$('loginForm').addEventListener('submit',e=>{e.preventDefault();busy($('login'),async()=>{configured();if(!sb)throw new Error('로그인 라이브러리를 불러오지 못했습니다.');const {error}=await sb.auth.signInWithPassword({email:$('email').value.trim(),password:$('pw').value});if(error)throw error;$('pw').value='';await showDashboard();});});
$('signup').addEventListener('click',()=>busy($('signup'),async()=>{if(!$('loginForm').reportValidity())return;configured();const {error}=await sb.auth.signUp({email:$('email').value.trim(),password:$('pw').value,options:{emailRedirectTo:new URL('index.html',location.href).href}});if(error)throw error;$('pw').value='';$('msg').textContent='가입 요청을 처리했습니다. 메일의 인증 링크를 누른 뒤 로그인하세요.';}));
$('logout').addEventListener('click',()=>busy($('logout'),async()=>{await sb.auth.signOut();location.reload();}));
$('resetPassword').addEventListener('click',()=>busy($('resetPassword'),async()=>{configured();if(!$('email').reportValidity()||!$('email').value)return;const {error}=await sb.auth.resetPasswordForEmail($('email').value.trim(),{redirectTo:new URL('index.html',location.href).href});if(error)throw error;$('msg').textContent='비밀번호 재설정 메일을 확인하세요.';}));
$('recoveryForm').addEventListener('submit',e=>{e.preventDefault();busy($('savePassword'),async()=>{const {error}=await sb.auth.updateUser({password:$('newPassword').value});if(error)throw error;$('newPassword').value='';await sb.auth.signOut();location.href='index.html';});});
function recovery(){recovering=true;$('auth').classList.remove('hidden');$('dash').classList.add('hidden');$('loginForm').classList.add('hidden');$('recoveryForm').classList.remove('hidden');}
try{const code=new URLSearchParams(location.search).get('room');if(code){location.replace('student.html?room='+encodeURIComponent(code));}else{configured();if(!sb)throw new Error('로그인 라이브러리를 불러오지 못했습니다. 인터넷 연결을 확인하세요.');sb.auth.onAuthStateChange(event=>{if(event==='PASSWORD_RECOVERY')recovery();});if(recovering)recovery();else await showDashboard();}}catch(e){showError(e);}
