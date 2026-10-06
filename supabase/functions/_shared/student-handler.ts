// No third-party runtime dependency. Types are stripped by Deno / Node 22+.
type Environment = { ALLOWED_ORIGINS?: string; SUPABASE_URL?: string; SUPABASE_SERVICE_ROLE_KEY?: string };
class APIError extends Error { status = 500; }
export function createStudentHandler(env: Environment, fetcher: typeof fetch = fetch) {
  const origins = (env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
  async function rpc(name: string, args: Record<string, unknown>) {
    const response = await fetcher(`${env.SUPABASE_URL}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json',
        apikey: env.SUPABASE_SERVICE_ROLE_KEY!, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
      body: JSON.stringify(args), signal: AbortSignal.timeout(15000)
    });
    const data = await response.json();
    if (!response.ok) {
      const error = new APIError(data.code === 'P0001' ? data.message : '서버 설정 또는 데이터 처리 오류입니다. 교사에게 알려 주세요.');
      error.status = data.message === 'SESSION_EXPIRED' ? 401 : data.code === 'P0001' ? 400 : 500;
      throw error;
    }
    return data;
  }
  async function limit(bucket: string, max: number, seconds: number) {
    if (!await rpc('gamehub_consume_limit', {p_bucket:bucket,p_limit:max,p_seconds:seconds})) {
      const e = new APIError('요청이 많습니다. 잠시 후 다시 시도하세요.'); e.status=429; throw e;
    }
  }
  async function digest(value: string) {
    return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');
  }
  return async function handle(req: Request) {
    const origin=req.headers.get('origin') || '';
    const headers: Record<string,string> = {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',
      'Vary':'Origin','Access-Control-Allow-Headers':'apikey, content-type',
      'Access-Control-Allow-Methods':'POST, OPTIONS','X-Content-Type-Options':'nosniff'};
    const respond=(body: unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
    if (!origins.length || !env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return respond({error:'서버 환경변수 설정이 필요합니다.'},503);
    if (!origins.includes(origin)) return respond({error:'허용되지 않은 접속 주소입니다.'},403);
    headers['Access-Control-Allow-Origin']=origin;
    if(req.method==='OPTIONS') return new Response(null,{status:204,headers});
    if(req.method!=='POST') return respond({error:'POST 요청만 지원합니다.'},405);
    if(!req.headers.get('content-type')?.includes('application/json')) return respond({error:'JSON 요청이 필요합니다.'},415);
    try {
      // Bound actual streamed bytes, not just the untrusted Content-Length header.
      const reader=req.body?.getReader(); const chunks: Uint8Array[]=[]; let size=0;
      if(!reader) return respond({error:'입력값이 없습니다.'},400);
      while(true) { const {done,value}=await reader.read(); if(done)break;
        size+=value.length; if(size>4096){await reader.cancel();return respond({error:'요청이 너무 큽니다.'},413);}chunks.push(value); }
      const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
      let b;try{b=JSON.parse(new TextDecoder().decode(bytes));}catch{return respond({error:'JSON 형식을 확인하세요.'},400);}
      if(!b || typeof b!=='object' || Array.isArray(b)) return respond({error:'입력 형식을 확인하세요.'},400);
      const action=b.action;
      if(action==='join') {
        if(!['roomCode','roomPassword','studentNumber','studentName','studentPassword'].every(k=>typeof b[k]==='string')) return respond({error:'참가 정보를 모두 입력하세요.'},400);
        const code=b.roomCode.trim().toUpperCase(),number=b.studentNumber.trim(),name=b.studentName.trim();
        if(!/^[A-Z0-9]{6,8}$/.test(code)||!/^[-_A-Za-z0-9]{1,24}$/.test(number)||name.length<1||name.length>40||b.studentPassword.length<4||new TextEncoder().encode(b.studentPassword).length>72||new TextEncoder().encode(b.roomPassword).length>72) return respond({error:'학번·이름·비밀번호 형식을 확인하세요. 개인 비밀번호는 6자 이상입니다.'},400);
        // Separate transactions: failed credentials do not roll back attempt counters.
        await limit(`join-room:${code}`,240,300);
        await limit(`join-student:${await digest(code+':'+number)}`,12,300);
        const data=await rpc('streams_join',{p_code:code,p_room_password:b.roomPassword,p_number:number,p_name:name,p_password:b.studentPassword});
        return respond(data);
      }
      if(!['state','place','logout'].includes(action)) return respond({error:'지원하지 않는 요청입니다.'},400);
      if(typeof b.sessionToken!=='string'||!/^[a-f0-9]{64}$/.test(b.sessionToken)) return respond({error:'다시 참가해 주세요.',code:'SESSION_EXPIRED'},401);
      if(action==='place'&&(!Number.isInteger(b.turn)||b.turn<1||b.turn>20||!Number.isInteger(b.slot)||b.slot<0||b.slot>19)) return respond({error:'잘못된 카드 배치입니다.'},400);
      await limit(`session:${await digest(b.sessionToken)}`,100,60);
      return respond(await rpc('streams_student_command',{p_action:action,p_token:b.sessionToken,p_turn:action==='place'?b.turn:null,p_slot:action==='place'?b.slot:null}));
    } catch(e) {
      const status=e instanceof APIError ? e.status : 500;
      return respond({error:status===401?'세션이 만료되었거나 다른 기기에서 다시 참가했습니다.':status===500?'서버 연결 또는 설정을 확인하세요.':(e instanceof Error ? e.message : '요청 실패'),
        ...(status===401?{code:'SESSION_EXPIRED'}:{})},status);
    }
  };
}
