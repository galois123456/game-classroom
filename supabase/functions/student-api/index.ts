// Supabase Edge Function: student-api
// Deploy with JWT verification OFF because students do not log in.
// IMPORTANT: room/student passwords are checked only here; service-role key never goes to browser.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS') return new Response('ok',{headers:cors})
 try{
  const b=await req.json()
  const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  if(b.action!=='join') throw new Error('지원하지 않는 요청입니다.')
  const code=String(b.roomCode||'').trim().toUpperCase()
  const {data:room,error:re}=await admin.from('streams_rooms').select('id,teacher_id,room_code,password_hash,status').eq('room_code',code).single()
  if(re||!room||room.status==='ENDED') throw new Error('유효한 방이 아닙니다.')
  const {data:ok}=await admin.rpc('gamehub_verify_password',{plain_text:String(b.roomPassword||''),password_hash:room.password_hash})
  if(!ok) throw new Error('방 비밀번호가 틀렸습니다.')
  const sn=String(b.studentNumber||'').trim(), name=String(b.studentName||'').trim(), pw=String(b.studentPassword||'')
  if(!sn||!name||pw.length<4) throw new Error('학번, 이름, 4자 이상 개인 비밀번호를 입력하세요.')
  let {data:stu}=await admin.from('gamehub_students').select('*').eq('teacher_id',room.teacher_id).eq('student_number',sn).maybeSingle()
  if(stu){
    const {data:pok}=await admin.rpc('gamehub_verify_password',{plain_text:pw,password_hash:stu.password_hash})
    if(!pok) throw new Error('학생 개인 비밀번호가 틀렸습니다.')
    await admin.from('gamehub_students').update({student_name:name,last_seen_at:new Date().toISOString()}).eq('id',stu.id)
  }else{
    const {data:hash}=await admin.rpc('gamehub_hash_password',{plain_text:pw})
    const ins=await admin.from('gamehub_students').insert({teacher_id:room.teacher_id,student_number:sn,student_name:name,password_hash:hash}).select().single()
    if(ins.error) throw ins.error; stu=ins.data
  }
  await admin.from('streams_players').upsert({room_id:room.id,student_id:stu.id,student_number:sn,student_name:name},{onConflict:'room_id,student_id'})
  const token=crypto.randomUUID()
  // ver1.00 token is an opaque client resume token; production expansion should persist/expire hashed sessions.
  return new Response(JSON.stringify({roomCode:code,studentId:stu.id,sessionToken:token,gameUrl:'games/streams-student.html'}),{headers:{...cors,'Content-Type':'application/json'}})
 }catch(e){return new Response(JSON.stringify({error:e.message}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}
})
