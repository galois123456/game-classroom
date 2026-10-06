# 수학 게임 교실 ver1.00

교사는 Supabase Auth로 로그인하고 학생은 회원가입 없이 QR/방 코드로 참가하는 공통 게임 플랫폼의 1차 기반입니다.

## 포함
- 교사 회원가입/로그인
- 게임 선택 대시보드
- 학생 관리/삭제
- 공통 학생 계정(학번+이름+개인 비밀번호 해시)
- 오름차순 게임 방 생성
- 방 코드/비밀번호
- QR 참가 URL (방 코드 자동 입력)
- Supabase Realtime 구독
- 게임별 접두사 테이블

## 설치
1. 새 Supabase 프로젝트 생성
2. SQL Editor에서 `supabase/schema.sql` 전체 실행
3. Project Settings > API의 URL/anon key를 `js/supabase.js`에 입력
4. `supabase/functions/student-api/index.ts`를 Edge Function `student-api`로 배포하고 JWT verification을 끔
5. GitHub에 전체 폴더 업로드
6. Vercel에서 해당 저장소를 정적 사이트로 배포
7. 교사 계정을 회원가입 후 로그인

## 보안
- service_role 키는 Edge Function 환경에만 존재하며 HTML에는 넣지 않습니다.
- 학생/방 비밀번호는 bcrypt-compatible pgcrypto crypt 해시로 저장합니다.
- 학생은 Supabase Auth 계정을 만들지 않습니다.
- 교사용 테이블은 RLS로 교사 소유 데이터만 접근합니다.

## 다음 버전
오름차순 게임의 기존 Streams 게임 로직(20칸 보드/★/점수)을 학생 화면에 완전 이식하고, 이후 다른 게임을 같은 공통 계정/방 구조에 연결합니다.
