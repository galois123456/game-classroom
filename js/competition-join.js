import {$,busy,studentAPI} from './common.js';
const game=new URLSearchParams(location.search).get('game'),room=new URLSearchParams(location.search).get('room');
const games={baseball1v1:['1:1 숫자야구','두 명이 각자 비밀 숫자를 정하고 상대 숫자를 추측합니다.'],baseball_class:['일대다수 숫자야구','선생님이 정한 숫자를 제한된 횟수 안에 맞혀 보세요.'],arithmetic:['사칙연산 챌린지','사칙연산 문제를 풀고 교실 순위에 도전하세요.']};
if(!games[game])location.replace('../index.html');else{$('title').textContent=games[game][0];$('description').textContent=games[game][1];document.title=games[game][0]+' 참가 · 수학 게임 교실';}
if(room)$('room').value=room.trim().toUpperCase();
$('joinForm').addEventListener('submit',e=>{e.preventDefault();busy($('join'),async()=>{const session=await studentAPI('game_join',{gameKey:game,roomCode:$('room').value.trim().toUpperCase(),studentNumber:$('number').value.trim(),studentName:$('name').value.trim(),studentPassword:$('studentPassword').value,roomPassword:$('roomPassword').value});session.gameKey=game;sessionStorage.setItem(`gamehub_${game}_session`,JSON.stringify(session));$('studentPassword').value='';$('roomPassword').value='';location.href=`competition-play.html?game=${encodeURIComponent(game)}`;});});
