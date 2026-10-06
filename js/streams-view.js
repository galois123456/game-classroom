import {$,el} from './common.js';
import {POINTS,snakePosition} from './games/streams-rules.js';
export function rules(){const target=$('scoreTable');if(target)target.replaceChildren(...POINTS.slice(1).map((p,i)=>{const n=el('div',`${i+1}칸`);n.append(el('b',p+'점'));return n;}));}
export function boardView(board,{selected=-1,enabled=false,onSelect=()=>{},evaluation=null,mini=false}={}){
 return board.map((value,index)=>{const pos=snakePosition(index);const n=el(mini?'div':'button',undefined,'cell'+(value!==null?' filled':'')+(selected===index?' selected':'')+(value==='★'?' star':''));n.style.gridRow=pos.row;n.style.gridColumn=pos.col;n.append(el('small',index+1),el('span',value??''));n.setAttribute('aria-label',`${index+1}번 칸: ${value??'빈칸'}`);if(!mini){n.type='button';n.disabled=!enabled||value!==null;n.setAttribute('aria-pressed',String(selected===index));n.addEventListener('click',()=>onSelect(index));if(index<19)n.append(el('span',index%5===4?'↓':Math.floor(index/5)%2?'←':'→','flow'+(index%5===4?' down':'')));}if(evaluation){const run=evaluation.runs.findIndex(r=>index>=r.start&&index<=r.end);if(run>=0){n.style.borderBottomColor=['#278564','#c99e3b','#6489af','#a278a4','#cd8670'][run%5];n.style.borderBottomWidth='4px';}}return n;});
}
export function history(cards){$('history').replaceChildren(...cards.map((c,i)=>{const n=el('span',c);n.title=`${i+1}번째 카드`;return n;}));}
export const statusLabel=s=>({WAITING:'입장 대기',PLAYING:'게임 진행 중',ENDED:'게임 종료'}[s]||s);
