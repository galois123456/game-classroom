export const $=id=>document.getElementById(id);
export function el(tag,text,cls){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
export function showError(error,target=$('msg')){if(target){target.textContent=error.message||String(error);target.classList.add('error');}}
export function clearMessage(target=$('msg')){if(target){target.textContent='';target.classList.remove('error');}}
export function configured(){if(!window.configReady)throw new Error('아직 연결 설정이 없습니다. README에 따라 Supabase URL과 공개 키를 설정하세요.');}
export async function teacherRequired(){configured();if(!window.sb)throw new Error('로그인 라이브러리를 불러오지 못했습니다. 인터넷 연결을 확인하세요.');const {data:{session}}=await sb.auth.getSession();if(!session){location.href=new URL('../index.html',import.meta.url).href;return null;}const {data,error}=await sb.rpc('gamehub_is_teacher');if(error)throw error;if(!data)throw new Error('승인된 교사 이메일인지, 이메일 인증을 완료했는지 확인하세요.');return session;}
export async function rpc(name,args){const {data,error}=await sb.rpc(name,args);if(error)throw error;return data;}
export async function studentAPI(action,body={}){configured();let response;try{response=await fetch(`${APP_CONFIG.SUPABASE_URL}/functions/v1/student-api`,{method:'POST',headers:{'Content-Type':'application/json',apikey:APP_CONFIG.SUPABASE_ANON_KEY},body:JSON.stringify({action,...body}),signal:AbortSignal.timeout(20000)});}catch{throw new Error(`서버에 연결할 수 없습니다. Supabase Edge Function Secrets의 ALLOWED_ORIGINS에 아래 주소를 등록했는지 확인하세요: ${location.origin} (인터넷 연결도 확인하세요.)`);}const data=await response.json();if(!response.ok){const err=new Error(data.error||'요청에 실패했습니다.');err.code=data.code;err.status=response.status;throw err;}return data;}
export function saveSession(value){sessionStorage.setItem('gamehub_student_session',JSON.stringify(value));}
export function getSession(){try{return JSON.parse(sessionStorage.getItem('gamehub_student_session')||'null');}catch{return null;}}
export function clearSession(){sessionStorage.removeItem('gamehub_student_session');localStorage.removeItem('gamehub_student_session');}
export function poll(fn,delay=3500){let stopped=false,timer;async function tick(){if(stopped)return;try{if(!document.hidden)await fn();}finally{if(!stopped)timer=setTimeout(tick,delay);}}timer=setTimeout(tick,delay);return()=>{stopped=true;clearTimeout(timer);};}
export async function busy(button,fn){if(button.disabled)return;button.disabled=true;try{clearMessage();await fn();}catch(e){showError(e);}finally{button.disabled=false;}}
export function downloadJSON(name,data){const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));const a=el('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
