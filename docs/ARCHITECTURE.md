# 공통 모듈과 후속 게임 확장

## 요청 경로

교사: 브라우저 → Supabase Auth → 사용자 JWT + RLS / 교사 RPC → 소유 데이터.
학생: 브라우저 → student-api Edge Function → 요청 제한 → service-role 전용 RPC → 해시 세션·방·턴 검증 → 허용된 응답.

학생 API가 service_role을 사용하기 때문에 RLS만 믿으면 안 됩니다. 학생 RPC에서 세션을 찾고 서버가 정한 student_id/room_id만 사용합니다. 브라우저의 studentId, roomId, card, score는 배치에 사용하지 않습니다.

## 테이블

| 접두사/테이블 | 목적 |
|---|---|
| gamehub_teacher_allowlist | 운영자만 수정하는 교사 승인 이메일 목록 |
| gamehub_teachers | 기존 교사 프로필 테이블 유지; 권한의 근거로 사용하지 않음 |
| gamehub_students | 교사별 공통 학생 신원과 개인 비밀번호 해시 |
| gamehub_games | 게임 카탈로그 |
| gamehub_sessions | game_key/room_id 범위에 묶인 공통 학생 세션, 해시·만료 |
| gamehub_results | 공통 결과, game_key + source_id로 게임별 원본 식별 |
| gamehub_rate_limits | 영속 요청 제한 카운터 |
| streams_rooms | 오름차순 게임 방, 비밀번호 해시, 숨겨진 덱, 현재 턴 |
| streams_players | 방별 보드, 배치 여부, 마지막 배치 턴/칸, 참가 상태 |
| streams_room_events | 교사용 Realtime 변경 번호; 비밀번호·덱·학생 개인정보 없음 |

공통 세션의 room_id는 여러 게임의 UUID를 담을 수 있도록 특정 게임 테이블에 외래 키를 걸지 않았습니다. 따라서 **각 게임 방 삭제 RPC에서 해당 game_key/room_id의 세션과 공통 결과도 명시적으로 삭제**해야 합니다. 학생 삭제는 student_id 외래 키의 ON DELETE CASCADE로 처리합니다.

## 프런트엔드

- `js/config.js`, `js/supabase.js`: 공개 설정·교사 Auth 클라이언트.
- `js/common.js`: DOM 안전 출력, 교사 권한 검사, RPC, 학생 API, 탭 세션, 조회 주기.
- `js/games/registry.js`: 7개 게임 목록과 경로. 미완성 게임은 enabled=false.
- `js/games/streams-rules.js`: 점수표·뱀 좌표·점수 참고 구현. **서버 결과가 최종값**.
- `js/streams-view.js`: 보드와 점수표 렌더링.
- 교사/학생 게임 스크립트 분리. 같은 학생 계정 모듈을 후속 게임에 재사용.

## 오름차순 상태 전이

WAITING → 교사 start → PLAYING(1턴) → 전원 배치 → 교사 next → … → 20턴 전원 배치 → ENDED.

교사 end는 WAITING/PLAYING에서도 현재 보드로 종료합니다. 서버는 방을 먼저 잠그고 플레이어를 잠급니다. 종료와 배치, 다음 카드가 같은 방 잠금을 사용하므로 트랜잭션 경계가 유지됩니다. 재시도 요청은 마지막 placed_turn/last_slot이 정확히 같을 때만 성공으로 돌려줍니다.

새 참가자는 WAITING에만 등록. 기존 참가자는 종료 후에도 만료/폐기된 세션을 비밀번호로 재발급하여 결과를 볼 수 있습니다. ‘참가 종료’ 학생은 재발급이 거부됩니다.

## 후속 게임 추가 순서

1. `baseball1v1_rooms`, `baseball1v1_players`, `baseball1v1_turns`처럼 게임 이름 접두사로 테이블을 만듭니다.
2. RLS를 켜고 기본 테이블 쓰기·내부 함수 실행을 anon/authenticated에서 제거합니다.
3. 교사 RPC는 `gamehub_is_teacher()`와 teacher_id=auth.uid()를 모두 확인합니다.
4. 학생 RPC는 gamehub_sessions의 game_key까지 검사하고, 세션의 student_id/room_id로만 실행합니다.
5. 새 게임 참가 시 gamehub_students의 기존 계정을 검증하여 재사용합니다. 복제 테이블을 만들지 않습니다.
6. Edge `_shared`에 공통 검증을 유지하고 명시적인 게임별 라우터를 추가합니다. 클라이언트가 RPC 이름을 임의 지정하게 만들지 않습니다.
7. 공통 결과에 game_key/source_id/score/detail을 기록합니다. 같은 결과 중복 저장을 막는 고유 키를 사용합니다.
8. 방 삭제·학생 삭제·세션 만료·재접속·동시 요청·다른 교사의 접근 차단 테스트를 추가합니다.
9. HTML 화면을 만든 뒤 DB gamehub_games와 프런트엔드 registry의 enabled를 함께 켭니다.

현재 Edge는 완성된 streams만 처리합니다. 나머지 게임이 이미 작동하는 것처럼 표시하지 않습니다.
