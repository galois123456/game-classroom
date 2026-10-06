# 수학 게임 교실 ver1.01
## 첫 번째 완성 게임: 오름차순 게임 ver1.00

교사는 Supabase Auth로 회원가입·로그인하고, 학생은 **회원가입 없이** QR 또는 방 코드로 참가하는 수학 게임 플랫폼입니다.

이 ZIP은 소스와 배포 설정을 포함합니다. **실제 사용하려면 아래 순서대로 본인의 Supabase와 Vercel을 연결해야 합니다.** 서비스 키나 계정 자격 증명은 포함하지 않았습니다. 기존 ver1.00의 학생 화면은 골격이었으며, 이번 버전에서 실제 게임과 서버 검증을 구현했습니다.

- 교사 이메일 사전 승인 + 이메일 인증 + 교사별 데이터 분리
- 학생 학번·이름·개인 비밀번호·방 비밀번호 참가, QR 방 코드 자동 입력
- 방/개인 비밀번호 bcrypt 해시, 학생 세션은 SHA-256 해시로 저장·12시간 만료
- 방 생성/목록/재접속/QR/진행 현황/참가 종료/중도 종료/방 삭제
- 학생 목록·검색·최근 기록·학생 삭제, 교사 게임 기록 JSON 다운로드
- 20칸 뱀 모양 보드, 40장 덱 중 20장 추첨, 카드 확정, 연속 구간 점수, ★, 공동 순위
- 1:1 숫자야구 등 6개 후속 게임은 기존 ‘준비 중’ 메뉴를 유지

---

## 0. 무엇을 어디에 올리나요?

| 서비스 | 역할 | 올리거나 입력할 것 |
|---|---|---|
| Supabase | 교사 인증, 데이터베이스, 학생 API | SQL, Edge Function, 교사 승인 이메일 |
| GitHub | 프로젝트 코드 보관 | ZIP을 푼 **폴더 안의 전체 파일** |
| Vercel | 교사·학생이 여는 웹사이트 | GitHub 저장소 연결, 공개 환경변수 2개 |

**Vercel에 배포해도 SQL과 Edge Function은 자동 배포되지 않습니다.** Supabase 작업은 별도로 진행합니다.

준비물: Supabase/GitHub/Vercel 계정, PC, 최신 Node.js LTS(22 이상). 명령어는 Windows PowerShell에서도 실행할 수 있습니다.

## 1. ZIP 풀기

1. ZIP을 압축 해제합니다.
2. `math-game-classroom-ver1.01` 폴더를 엽니다.
3. 이 폴더 안에 `index.html`, `package.json`, `vercel.json`, `supabase`가 보여야 합니다.
4. 이후 ‘프로젝트 폴더에서 실행’이라는 말은 이 위치에서 터미널을 열라는 뜻입니다.

`index.html`을 더블클릭하는 `file://` 방식은 지원하지 않습니다. ES 모듈·인증·네트워크 요청 때문에 HTTP/HTTPS 주소로 열어야 합니다.

## 2. Supabase 프로젝트 만들기

1. [Supabase](https://supabase.com/dashboard)에 로그인합니다.
2. **New project**를 선택합니다.
3. 조직, 프로젝트 이름(예: `math-game-classroom`), 데이터베이스 비밀번호, 가까운 지역을 선택합니다.
4. 생성이 끝날 때까지 기다립니다. DB 비밀번호는 안전하게 보관합니다.
5. 설정에서 다음 세 가지를 확인합니다.
   - **Project URL**: `https://xxxxxxxx.supabase.co`
   - **Publishable key** (`sb_publishable_...`) 또는 **Legacy anon key**
   - **Project Reference / Project ID**: URL 앞쪽 `xxxxxxxx` 값

설정 메뉴는 화면 버전에 따라 **Connect**, **Settings → API Keys**, **Data API** 등에 표시될 수 있습니다.

**`service_role`, `sb_secret_...`, DB 비밀번호는 HTML, GitHub, Vercel의 공개 환경변수에 넣지 마세요.** 이 프로젝트의 학생 API는 Supabase 서버 안에 제공되는 service role 키를 사용합니다.

## 3. SQL 실행

1. Supabase 왼쪽 **SQL Editor → New query**를 엽니다.
2. `supabase/schema.sql`을 텍스트 편집기로 열고 **전체 내용**을 복사합니다.
3. SQL Editor에 붙여 넣고 **Run**을 누릅니다.
4. 오류 없이 완료되면 테이블이 만들어집니다.

이 SQL은 트랜잭션 안에서 실행되고 다시 실행할 수 있습니다. 기존 테이블은 삭제하지 않고 필요한 열·세션 테이블·권한·함수를 추가/교체합니다. 기본 `pgcrypto` 확장은 `extensions` 스키마를 사용합니다.

**기존 ver1.00을 사용했다면:** 데이터베이스를 먼저 백업하고 이 SQL을 실행합니다. 기존 학생 데이터는 보존됩니다. 기존 4~5자 개인 비밀번호는 재접속용으로 인정하고, 새 개인 비밀번호는 6자 이상을 요구합니다. 기존 진행 중 방은 이전 버전에 카드 배치 기능이 없었으므로 정상 20턴 게임으로 이어갈 수 없습니다. 해당 방을 중도 종료한 뒤 새 방을 만드세요. 예전 가짜 세션은 더 이상 유효하지 않으므로 학생은 한 번 다시 참가해야 합니다.

`reset_dev.sql`은 **운영용 설치·업데이트에 사용하지 않습니다.** 개발용 전체 삭제 파일이며 실수 방지를 위해 기본 실행 차단 장치가 있습니다.

## 4. 교사 이메일 승인하기

누구나 ‘교사’ 버튼을 눌러 학생 데이터를 관리할 수 있으면 안 되므로, 프로젝트 운영자가 이메일을 먼저 등록합니다.

SQL Editor에서 아래 예시의 이메일을 **실제 교사 이메일로 바꿔** 실행하세요.

```sql
insert into public.gamehub_teacher_allowlist(email, enabled)
values (lower('teacher@example.com'), true)
on conflict(email) do update set enabled = true;
```

교사가 여러 명이면 한 명씩 추가합니다. 학교 이메일 도메인 전체를 자동 승인하지 않고 개별 주소를 승인합니다.

권한을 회수할 때:

```sql
update public.gamehub_teacher_allowlist
set enabled = false
where email = lower('teacher@example.com');
```

이 변경은 이미 로그인한 교사의 다음 데이터 요청에도 적용됩니다. 해당 교사의 Auth 계정/과거 데이터 자체를 자동 삭제하지는 않습니다.

## 5. Supabase Auth 설정 — 필수

1. **Authentication → Providers / Sign In**에서 **Email**을 활성화합니다.
2. **Confirm email**을 켭니다. 승인 이메일 소유자임을 확인해야 교사 권한을 얻습니다.
3. 익명 로그인과 사용하지 않는 다른 로그인 제공자는 끕니다.
4. **Authentication → Hooks**에서 **Before User Created**를 추가합니다.
5. **Postgres function**, 스키마 `public`, 함수 **`gamehub_before_user_created`**를 선택하고 저장/활성화합니다.
6. 가입 허용 설정은 켜 둡니다. 실제 가입 가능 여부는 이 Hook이 승인 이메일 목록으로 제한합니다.

**Hook 설정을 생략하면 승인되지 않은 사람도 Auth 계정을 생성할 수는 있습니다.** 이 경우에도 SQL 권한 검사가 교사 기능을 차단하지만, ‘교사만 Auth 가입’이라는 요구를 완성하려면 Hook 설정까지 해야 합니다. Hook을 제공하지 않는 환경에서는 신규 가입을 끄고 Dashboard에서 운영자가 교사 계정을 직접 만드는 방식이 대안이며, 이 경우 웹의 회원가입 버튼은 사용할 수 없습니다.

인증/비밀번호 재설정 메일은 Supabase의 메일 발송 설정을 사용합니다. 기본 발송 서비스는 수신 대상·발송량 제약이 있을 수 있으므로 여러 교사가 사용할 때는 **Authentication → SMTP Settings**에서 본인 SMTP를 연결하고 실제 메일 수신을 확인하세요. 메일 발송 실패를 해결하려고 이메일 인증을 꺼서는 안 됩니다.

## 6. Edge Function 배포

### 권장: CLI로 배포

1. [Node.js](https://nodejs.org/) LTS를 설치합니다.
2. 프로젝트 폴더에서 PowerShell/터미널을 엽니다.
3. 다음을 순서대로 실행합니다.

```bash
node --version
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase functions deploy student-api --no-verify-jwt
```

- `YOUR_PROJECT_REF`를 2단계에서 확인한 프로젝트 ID로 바꿉니다.
- `npx`가 도구 설치 여부를 물으면 진행합니다.
- 브라우저에서 Supabase 로그인 승인을 합니다.
- `link` 중 DB 비밀번호를 물으면 프로젝트 생성 때 지정한 값을 입력합니다.
- 폴더에 이미 `supabase/config.toml`이 있으므로 **`supabase init`은 필요 없습니다.**
- `student-api/index.ts`가 `_shared/student-handler.ts`를 가져옵니다. CLI는 두 파일을 함께 배포합니다.
- 학생은 Auth JWT가 없으므로 이 함수에만 JWT verification을 끕니다. 대신 세션·방·턴·권한은 서버 함수가 검증합니다.

배포 후 Supabase **Edge Functions**에 `student-api`가 표시되는지 확인합니다. 함수의 JWT verification도 꺼져 있어야 합니다.

### Dashboard 편집기로 배포할 때

코드 한 파일만 복사해서는 안 됩니다. `student-api/index.ts`와 `../_shared/student-handler.ts`의 상대 경로가 함께 있어야 합니다. 다중 파일 추가가 불편하면 위 CLI 방식을 사용하세요.

### 서버 환경변수

`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`는 Supabase 호스팅 Edge Function에서 기본 제공되는 서버 값입니다. 프런트엔드로 복사하지 않습니다.

이 구현은 서버의 기본 `SUPABASE_SERVICE_ROLE_KEY`를 사용하므로 프로젝트의 Legacy API keys를 비활성화하지 마세요. 브라우저 공개 키는 새로운 Publishable key를 사용해도 됩니다.

추가로 필요한 값은 `ALLOWED_ORIGINS`입니다. Vercel 주소가 정해지는 9단계에서 등록합니다. 이 값이 없으면 학생 API가 **503**을 반환하도록 의도적으로 막아 두었습니다.

## 7. GitHub 업로드

1. [GitHub](https://github.com/)에서 새 저장소를 만듭니다. 공개/비공개 모두 가능합니다.
2. 저장소에서 **Add file → Upload files**를 선택합니다.
3. 압축 해제한 프로젝트의 **내부 파일과 폴더**를 모두 업로드합니다.
4. 저장소 최상위에 `package.json`, `index.html`, `vercel.json`이 보이도록 합니다.
5. **Commit changes**를 누릅니다.

ZIP 파일 자체만 올리면 배포되지 않습니다. `node_modules`, `dist`, 실제 `.env`, Supabase 개인 액세스 토큰은 올리지 않습니다. 숨김 파일 `.gitignore`도 포함하는 것이 좋습니다.

폴더째 올려 최상위 아래에 `math-game-classroom-ver1.01`이 생겼다면, 다음 Vercel 단계의 **Root Directory**를 그 폴더로 지정하면 됩니다.

## 8. Vercel 배포

1. [Vercel](https://vercel.com/) 로그인 → **Add New → Project**.
2. GitHub 연결 후 방금 만든 저장소를 **Import**합니다.
3. 설정을 확인합니다.

| 항목 | 입력값 |
|---|---|
| Framework Preset | `Other` |
| Root Directory | `package.json`이 있는 폴더; 정상 업로드했다면 저장소 최상위 |
| Build Command | `npm run build` |
| Output Directory | `dist` |
| Install Command | 기본값 |
| Node.js | 22 이상 지원 버전 |

`vercel.json`에 빌드/출력 설정이 들어 있습니다. 기존 Vercel 프로젝트의 수동 Override가 충돌하면 위 값으로 수정하세요.

4. **Environment Variables**에 다음 두 값을 추가합니다.

| Name | Value |
|---|---|
| `PUBLIC_SUPABASE_URL` | `https://xxxxxxxx.supabase.co` |
| `PUBLIC_SUPABASE_ANON_KEY` | Publishable key 또는 legacy anon key |

5. **Deploy**를 누릅니다.
6. 성공하면 `https://프로젝트명.vercel.app` 같은 고정 Production 주소를 복사합니다.

이 환경변수 두 개는 브라우저에 공개되는 설정입니다. 서비스 키는 빌드 단계에서 차단합니다. 별도 환경변수를 사용하지 않으려면 `js/config.js`의 두 값을 직접 수정해도 됩니다. 둘 다 있으면 Vercel 환경변수가 우선합니다.

환경변수를 바꾼 경우 **Redeploy**해야 정적 파일에 반영됩니다. 기본 예시값으로도 빌드는 가능하지만 웹 화면에는 ‘아직 연결 설정이 없습니다’가 표시됩니다.

빌드는 배포에 필요한 HTML/CSS/JS/vendor 파일만 `dist`로 복사합니다. SQL·테스트·문서·설정 파일은 웹에 노출되지 않습니다. 브라우저 라이브러리는 ZIP에 포함되어 CDN 접속 없이 로드됩니다.

## 9. 실제 주소 연결하기 — 반드시 완료

예를 들어 사이트 주소가 `https://math-class.vercel.app`이라고 가정합니다.

### 9-1. Supabase Auth 주소

**Authentication → URL Configuration**:

- **Site URL**: `https://math-class.vercel.app`
- **Redirect URLs**에 `https://math-class.vercel.app/index.html` 추가
- 로컬 테스트할 때만 `http://localhost:5173/index.html`도 추가

Site URL은 기본 인증 후 돌아갈 주소입니다. Redirect URLs는 허용할 인증 복귀 주소 목록입니다.

### 9-2. 학생 API 허용 주소

**Edge Functions → Secrets**에 아래 값을 추가합니다.

- Name: `ALLOWED_ORIGINS`
- Value: `https://math-class.vercel.app`

또는 CLI:

```bash
npx supabase secrets set ALLOWED_ORIGINS="https://math-class.vercel.app"
```

로컬 주소도 필요하면 쉼표로 구분합니다.

```bash
npx supabase secrets set ALLOWED_ORIGINS="https://math-class.vercel.app,http://localhost:5173"
```

**끝에 `/`를 붙이지 않습니다.** 경로 없이 `https://호스트`만 입력합니다. Production 주소와 매번 달라지는 Preview 주소는 다릅니다. 수업에는 고정 Production 주소를 사용하세요. 추가 도메인은 Auth Redirect URLs와 `ALLOWED_ORIGINS` 두 곳 모두에 등록합니다. `*` 허용은 사용하지 않습니다.

## 10. 첫 게임 실행

### 교사

1. Production 주소에서 **교사 회원가입**.
2. 승인된 이메일을 사용하고 메일 인증을 완료한 뒤 로그인.
3. **오름차순 게임 → 방 만들기**. 방 비밀번호는 6자 이상.
4. 화면의 QR/방 코드와 방 비밀번호를 학생에게 안내.
5. 학생 현황에 참가자가 모두 나타나면 **게임 시작**.
6. 첫 카드가 표시됩니다. 모든 학생이 확정하면 **다음 카드 뽑기**.
7. 20번째 카드를 전원이 확정하면 자동 채점·종료. 학생 이름별 순위와 보드는 교사 화면에 표시.

### 학생

1. QR을 찍거나 사이트의 **학생 참가**를 선택.
2. QR에서는 방 코드가 자동 입력됩니다. 잘못된 QR이어도 코드를 수정할 수 있습니다.
3. 학번, 이름, 개인 비밀번호, 방 비밀번호 입력.
4. 처음 참가하면 해당 교사 안에서 학생 데이터가 생성됩니다. Supabase Auth 계정은 생성하지 않습니다.
5. 20칸 중 원하는 빈칸을 선택 → **이 칸에 확정**.
6. 확정한 카드는 이동·취소할 수 없습니다.
7. 새로고침해도 현재 탭의 세션으로 보드가 복구됩니다. 탭을 닫았거나 다른 기기로 바꾸면 같은 정보로 다시 참가합니다.

개인 비밀번호는 ‘방 비밀번호’와 다릅니다. 같은 교사의 다른 게임에서 학생을 식별하기 위한 값입니다. 같은 학번이라도 다른 교사의 학생 계정은 별개입니다. 이름이 달라지면 재접속이 거부됩니다.

## 11. 규칙과 점수

- 덱: 1~30, 11~19만 각 2장, 나머지 각 1장, ★ 1장 → 총 40장.
- 서버가 섞은 덱에서 중복 제거 없이 순서대로 20장을 추첨합니다. 같은 숫자가 나올 수 있으나 덱에 있는 장수 이상은 나오지 않습니다.
- 보드: 4행 × 5열. 1~5번은 오른쪽, 6~10번은 왼쪽, 11~15번은 오른쪽, 16~20번은 왼쪽으로 이어집니다.
- 점수는 화면상의 좌우 방향이 아니라 **칸 번호 1→20 순서**로 계산합니다.
- 앞 숫자보다 같거나 크면 같은 구간. 작아지거나 빈칸이면 구간을 나눕니다.
- ★는 **1~30 중 총점을 최대로 만드는 한 숫자**로 평가합니다. 최적값이 여러 개면 가장 작은 값이 표시됩니다. 배치 후 보드가 바뀌면 최적값도 바뀔 수 있습니다. 예: `30, ★, 1`은 하나의 오름차순 구간이 될 수 없습니다.
- 첨부 원본에는 별 상세 규칙이 없었으므로 위 규칙을 이 구현의 명시적 기준으로 정했습니다.
- 각 구간은 겹치지 않습니다. 20칸 전체가 오름차순이면 300점입니다.

| 연속 칸 수 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| 점수 | 0 | 1 | 3 | 5 | 7 | 9 | 11 | 15 | 20 | 25 |

| 연속 칸 수 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|
| 점수 | 30 | 35 | 40 | 50 | 60 | 70 | 85 | 100 | 150 | 300 |

- 진행 중 점수는 현재 배치 기준이며 빈칸을 채우면 달라집니다.
- 동점은 공동 순위: 예를 들어 1위, 1위, 3위.
- 학생에게는 본인 이름/학번과 다른 학생의 익명 참가 번호·최종 점수만 전달됩니다.
- 시작 후 신규 참가는 차단됩니다. 이미 참가한 학생의 재접속은 허용됩니다.

## 12. 수업 중 관리

- **새로고침/방 복구:** 교사는 방 목록에서 선택. 학생은 같은 정보로 재참가. 보드는 초기화되지 않습니다.
- **접속 끊긴 학생:** 가능하면 재참가하도록 기다립니다. 계속 진행할 수 없으면 교사가 그 학생의 ‘참가 종료’를 선택합니다. 이번 방에 재참가할 수 없고 최종 순위에서 제외됩니다.
- **중도 종료:** 현재 보드로 결과를 저장합니다. 빈칸은 구간을 끊습니다.
- **방 삭제:** 방·참가 보드·세션·해당 방 결과 삭제. 공통 학생 계정은 유지.
- **학생 삭제:** 학생 관리에서 선택. 해당 교사의 학생 계정·세션·모든 게임 참가 기록·결과가 연쇄 삭제됩니다. 다른 교사의 동명 학생은 삭제되지 않습니다.
- **비밀번호 분실:** 원문 조회/복호화는 불가능합니다. 현재 버전에는 별도 초기화 기능이 없으므로 교사가 기존 기록을 필요한 경우 다운로드한 후 학생을 삭제하고 새로 참가시킵니다. 삭제의 영향을 먼저 확인하세요.
- **기록 다운로드:** 교사만 JSON으로 내려받습니다. 이름·학번이 포함되므로 저장 위치를 관리하세요.

한 방은 최대 60명, 교사당 종료하지 않은 방은 최대 10개입니다. 교사 방 목록은 최근 30개, 학생 관리 결과는 최근 100건을 보여 줍니다. 오래된 방 데이터는 자동 삭제하지 않습니다.

## 13. 비용·운영·보안

- 학생은 보호된 API를 약 3.5초 간격으로 조회합니다. 숨겨진 탭에서는 조회를 쉬고, 종료 시 중단합니다.
- 교사는 안전한 변경 알림 테이블을 Realtime 구독하고 5초 간격 조회를 보조로 사용합니다.
- 요청 제한: 방 참가 5분당 방별 240회, 같은 방·학번 12회, 세션 요청 분당 100회. 실패 시도도 누적됩니다.
- 이는 교실 사용을 위한 기본 제한이며 대규모 분산 공격 방어를 보장하지 않습니다. 공개 서비스로 확장할 때는 별도 봇/트래픽 방어와 부하 테스트가 필요합니다.
- 무료 사용량을 보장하지 않습니다. 인원·수업 시간에 따라 Edge Function 호출량과 DB 부하가 증가하므로 Supabase/Vercel 사용량 화면을 확인하세요.
- 하루 한 번 `supabase/maintenance.sql`을 실행하거나 파일 설명대로 Supabase Cron으로 예약하세요. 만료 세션과 오래된 요청 제한 기록만 정리합니다.
- 원문 비밀번호는 HTTPS 요청 처리 중에만 사용하며 테이블·로컬스토리지·URL·앱 로그에 저장하지 않습니다. 학생 토큰 원문은 현재 탭의 sessionStorage에만 저장합니다.
- 저장된 비밀번호 해시도 교사 브라우저에서 직접 읽을 수 없습니다. 운영자는 SQL Editor로 DB를 관리할 수 있으므로 운영자 계정 보안은 별도 관리해야 합니다.
- 삭제는 현재 DB의 관계 데이터에 적용됩니다. 이미 다운로드한 파일·운영자가 만든 백업까지 지워 주는 기능은 아닙니다.

## 14. 자주 생기는 오류

| 증상 | 확인할 사항 |
|---|---|
| 아직 연결 설정이 없습니다 | Vercel 공개 환경변수 2개 입력 후 Redeploy |
| 승인된 교사가 아닙니다 | allowlist 이메일, enabled=true, 이메일 인증 완료 여부 |
| 회원가입 실패/메일이 안 옴 | Auth Hook·가입 허용·Confirm email·SMTP/메일 발송 설정 |
| 학생 API 503 | Supabase `ALLOWED_ORIGINS` 설정 여부 |
| 학생 참가 시 연결/CORS 오류 | 현재 주소와 `ALLOWED_ORIGINS`가 정확히 같은지, 끝 `/` 제거 |
| 401 Invalid JWT가 참가 요청에서 발생 | `student-api`의 JWT verification 끄기, 함수 재배포 |
| `relation does not exist` / 함수 없음 | 올바른 Supabase 프로젝트에 schema.sql 전체 실행했는지 |
| `extensions.gen_salt` 없음 | Database → Extensions에서 pgcrypto의 스키마가 `extensions`인지 확인. 새 프로젝트는 본 SQL로 생성됨. 다른 앱과 공유 중이면 운영자와 확장 위치를 먼저 검토 |
| Too many requests / 429 | 반복 제출을 멈추고 제한 시간 후 다시 시도 |
| 다음 카드 버튼 비활성 | 모든 활성 학생이 현재 카드를 확정했는지 확인 |
| 학생 이름/비밀번호 오류 | 이전에 등록한 학번·이름·개인 비밀번호가 정확한지 확인 |
| 다른 기기 로그인 후 이전 화면 사용 불가 | 재참가 시 이전 세션이 폐기되는 정상 동작 |
| Vercel 404 | Root Directory, Output Directory=`dist`, GitHub에 ZIP만 올리지 않았는지 |
| 브라우저는 바뀌었는데 서버 동작이 예전과 같음 | GitHub/Vercel 배포와 Supabase SQL/Edge 배포는 별개. 둘 다 업데이트 |

## 15. 개발·테스트

기본 검사(별도 npm 패키지 설치 불필요):

```bash
npm run build
npm test
npm run dev
```

브라우저에서 `http://localhost:5173`을 엽니다. 실제 Supabase에 접속하려면 공개 설정과 허용 Origin도 입력해야 합니다.

SQL 통합 검사(운영 Supabase가 아닌 메모리 PostgreSQL/PGlite 사용):

```bash
npm install --no-save @electric-sql/pglite@0.5.8
node tests/database.mjs
```

Node 22에서 TypeScript 직접 로드가 지원되지 않는 이전 패치 버전을 사용하는 경우 최신 Node LTS로 업데이트하세요. 테스트 의존성은 제품 배포에 필요하지 않습니다.

검사 범위와 실제 서비스에서 남은 확인 항목은 `docs/AUDIT.md`, 후속 게임 확장 방법은 `docs/ARCHITECTURE.md`를 읽으세요.

## 16. 공식 안내 참고

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Before User Created Hook](https://supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook)
- [Supabase Edge Function 배포](https://supabase.com/docs/guides/functions/deploy)
- [Supabase Edge 인증/헤더](https://supabase.com/docs/guides/functions/auth-headers)
- [Vercel 빌드/출력 폴더 설정](https://vercel.com/docs/builds/configure-a-build)

made by yoonsungho

### 선택: 브라우저 자동 검사

```bash
npm install --no-save playwright @electric-sql/pglite@0.5.8
npx playwright install chromium
npm run build
node tests/browser.mjs
```

테스트는 로컬 임시 DB와 모의 Supabase 전송 계층을 사용합니다. 실제 프로젝트 데이터에는 접속하지 않습니다.
