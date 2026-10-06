export const POINTS=[0,0,1,3,5,7,9,11,15,20,25,30,35,40,50,60,70,85,100,150,300];
export function createDeck(){return [...Array.from({length:30},(_,i)=>String(i+1)),...Array.from({length:9},(_,i)=>String(i+11)),'★'];}
export function evaluate(board){
 if(!Array.isArray(board)||board.length!==20)throw new Error('20칸 보드가 필요합니다.');
 if(board.some(v=>v!==null&&v!=='★'&&!/^([1-9]|[12][0-9]|30)$/.test(String(v))))throw new Error('잘못된 카드');
 if(board.filter(v=>v==='★').length>1)throw new Error('별 카드는 한 장입니다.');
 const hasStar=board.includes('★');let best={score:-1,runs:[],starValue:null};
 for(let star=1;star<=(hasStar?30:1);star++){
  let runs=[],start=0,run=0,prev=null;
  for(let i=0;i<=20;i++){
   const value=i===20||board[i]===null?null:board[i]==='★'?star:Number(board[i]);
   if(run&&(value===null||value<prev)){runs.push({start,end:i-1,length:run,score:POINTS[run]});run=0;}
   if(value!==null){if(!run)start=i;run++;prev=value;}else prev=null;
  }
  const score=runs.reduce((sum,r)=>sum+r.score,0);if(score>best.score)best={score,runs,starValue:hasStar?star:null};
 }
 return best;
}
export function snakePosition(index){const row=Math.floor(index/5),col=index%5;return {row:row+1,col:row%2?5-col:col+1};}
export function competitionRanks(players){const sorted=[...players].sort((a,b)=>b.score-a.score);let previous,rank=0;return sorted.map((p,i)=>{if(p.score!==previous)rank=i+1;previous=p.score;return {...p,rank};});}
