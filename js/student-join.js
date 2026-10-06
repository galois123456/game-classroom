import {$,busy,studentAPI,saveSession,getSession,clearSession} from './common.js';
const code=new URLSearchParams(location.search).get('room');if(code)$('room').value=code.trim().toUpperCase();
if(getSession())$('resume').classList.remove('hidden');
// Remove the old build's unverified persistent token and never put the new token in a URL.
localStorage.removeItem('gamehub_student_session');
$('joinForm').addEventListener('submit',e=>{e.preventDefault();busy($('join'),async()=>{
 const session=await studentAPI('join',{roomCode:$('room').value,studentNumber:$('num').value,studentName:$('studentName').value,studentPassword:$('spw').value,roomPassword:$('rpw').value});
 clearSession();saveSession(session);$('spw').value='';$('rpw').value='';location.href='games/streams-student.html';
});});
