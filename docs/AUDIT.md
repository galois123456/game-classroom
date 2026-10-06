# 검토·수정·검증 보고서

대상: 기존 math-game-classroom-ver1.00-fixed 프로젝트와 사용자가 첨부한 숫자야구·연산 챌린지 Apps Script 자료.
결과: 플랫폼 ver1.03. 오름차순 게임과 새 게임 3종은 각각 ver1.00으로 등록했습니다.

## ver1.03 추가 구현

- `baseball1v1_`: 방당 두 명 제한, 각자 비밀 숫자 설정, 동시 라운드 추측, 스트라이크/볼, 홈런·동시 홈런 무승부·최대 라운드 처리.
- `baseballclass_`: 교사 설정 정답, 3~5자리·중복 숫자 제한·0 사용 설정·최대 30회 시도, 아웃/홈런과 학생별 기록.
- `arithmetic_`: 덧셈·뺄셈·곱셈·나눗셈, 제곱·제곱근·세제곱·네제곱·복합 문제, 자릿수, 1~500문항, 다섯 오답 방식, 레벨·점수·시간 보너스.
- 학생 식별·세션·비밀번호 해시는 `gamehub_` 공통 기능을 사용합니다. 게임 데이터는 `streams_`, `baseball1v1_`, `baseballclass_`, `arithmetic_`로 분리됩니다.
- 모든 새 테이블은 RLS 사용, 브라우저 직접 접근 차단, Edge Function의 서비스 역할 RPC를 통해서만 학생 작업을 처리합니다. 교사 RPC는 승인된 인증 계정에서만 실행합니다.
- 오름차순 및 새 일대다수 방은 최대 100명을 허용합니다. 실제 동시 접속 부하 시험은 하지 않았습니다.

## 이번 작업에서 실행한 검사

- `npm test`: Edge/API, 점수 규칙, 정적 파일 검사 통과.
- `npm run build`: 정적 배포 산출물 생성 성공. Supabase 환경변수가 없는 상태라 실제 로그인/네트워크 연결은 확인하지 않았습니다.
- 새 게임의 Edge 라우팅·입력 허용목록·정적 페이지 경로·게임 테이블 접두사는 테스트에 추가했고 통과했습니다.
- Edge Function은 학생 세션 토큰을 URL에 넣지 않고 JSON 본문으로 전달하며, 방 참가와 게임 행동은 서로 다른 제한 키를 사용합니다.

## 아직 실행하지 못한 검사

현재 실행 환경에 `@electric-sql/pglite`와 Playwright가 제공되지 않았고, 패키지 설치도 네트워크 제한으로 완료되지 않았습니다. 따라서 이번 ver1.03의 PostgreSQL 함수 전체를 실제 PGlite/PostgreSQL에서 실행하거나 Chromium으로 새 게임을 끝까지 플레이하는 검사는 수행하지 못했습니다. `tests/database.mjs`에는 새 게임의 비밀 숫자 비노출, 1:1 무승부, 숫자야구 성공, 연산 완주 통합 검사를 추가했습니다. 교사 또는 개발자가 프로젝트에서 테스트 의존성을 설치한 뒤 다음 검사로 실행해야 합니다.

```bash
npm install --no-save @electric-sql/pglite@0.5.8 playwright
node tests/database.mjs
node tests/browser.mjs
```

브라우저 통합 검사는 Chromium 설치도 필요합니다. 실제 Supabase/Vercel 계정, 이메일 가입 Hook, Production CORS, Realtime, 학생 100명 동시 부하는 이 로컬 검사로 검증되지 않습니다.

## 배포 전 확인

1. Supabase SQL Editor에서 최신 `supabase/schema.sql` 전체를 실행합니다. 이 스크립트는 재실행 가능하도록 작성했으며 기존 학생 자료를 삭제하지 않습니다.
2. 최신 `student-api` Edge Function을 `--no-verify-jwt` 옵션으로 재배포하고 `ALLOWED_ORIGINS`에 실제 Production 주소를 등록합니다.
3. GitHub에 프로젝트를 올린 후 Vercel Production 배포를 완료합니다. Vercel Deployment Protection이 학생 주소에 로그인 장벽을 만들지 않도록 Production 도메인을 공개합니다.
4. 교사 계정으로 각 게임 방을 생성해 참가 링크/QR을 확인하고, 최소한 두 기기에서 한 라운드 이상 플레이합니다.
5. 새 게임 SQL 통합 테스트와 브라우저 검사를 실행한 뒤 대회 규모에 따라 100명 모의 참가·반복 polling 부하를 따로 확인합니다.

## 운영 한계

- 사용자 계정에 접근하지 않았으므로 Supabase/Vercel에 직접 배포하거나 실제 메일·Production 참가를 검증하지 않았습니다.
- 100명 방 설정은 코드상 상한입니다. 서버 플랜, Edge 동시 실행·요청 제한, 모바일 네트워크에 따른 안정성을 보장하는 부하 결과는 아닙니다.
- 구구단 RPG, 중등 기초연산, 초등 기초연산은 기존 메뉴와 공통 구조를 유지하며 이후 확장 대상으로 남아 있습니다.
