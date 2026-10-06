// Add future games here; keep shared identity/session/data ownership in gamehub_*.
export const GAMES=[
 {key:'streams',icon:'↗',title:'오름차순 게임',description:'20칸에 만드는 나만의 숫자 흐름',version:'ver1.00',teacherUrl:'games/streams.html',studentUrl:'games/streams-student.html',enabled:true},
 {key:'baseball1v1',icon:'⚾',title:'1:1 숫자야구',description:'두 학생이 비밀 숫자를 정하고 동시에 추측 대결',version:'ver1.00',teacherUrl:'games/competition.html?game=baseball1v1',studentUrl:'games/competition-join.html?game=baseball1v1',enabled:true},
 {key:'baseball_class',icon:'◎',title:'일대다수 숫자야구',description:'교사가 정한 정답에 도전하는 학급 숫자야구',version:'ver1.00',teacherUrl:'games/competition.html?game=baseball_class',studentUrl:'games/competition-join.html?game=baseball_class',enabled:true},
 {key:'gugudan_rpg',icon:'⚔',title:'구구단 RPG',enabled:false},
 {key:'arithmetic',icon:'＋',title:'사칙연산 게임',description:'단계별 사칙연산 문제를 풀고 점수 경쟁',version:'ver1.00',teacherUrl:'games/competition.html?game=arithmetic',studentUrl:'games/competition-join.html?game=arithmetic',enabled:true},
 {key:'middle_math',icon:'√',title:'중등수학 기초연산',enabled:false},
 {key:'elementary_math',icon:'123',title:'초등학교 기초연산',enabled:false}
];
