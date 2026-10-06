# 수학 게임 교실 ver1.01

교사는 Supabase Auth로 로그인하고, 학생은 계정 없이 방 코드와 비밀번호로 참가하는 수학 게임 플랫폼입니다. 현재 완성 게임은 **오름차순 게임 ver1.00**입니다. 다음 배포는 `GitHub → Vercel`, 데이터와 인증은 `Supabase`를 사용합니다.

## 필요한 계정과 파일

- GitHub 계정, Supabase 계정, Vercel 계정
- 이 프로젝트 파일 전체
- Supabase 프로젝트의 Project URL과 Publishable key(또는 legacy anon key)
- 교사 계정으로 쓸 이메일 주소

`service_role` 또는 `sb_secret_` 키는 브라우저용이 아닙니다. Vercel 환경변수나 HTML 파일에 넣지 마세요.

## 1. Supabase 프로젝트 만들기와 데이터베이스 준비

1. Supabase에서 새 프로젝트를 만들고 데이터베이스 비밀번호를 안전하게 보관합니다.
2. 왼쪽 메뉴 **SQL Editor → New query**를 엽니다.
3. 이 저장소의 `supabase/schema.sql` 전체를 붙여 넣고 **Run**을 누릅니다.
4. 오류 없이 실행되면 `public` 스키마에 `gamehub_` 공통 테이블과 `streams_` 게임 테이블이 생깁니다. SQL은 기존 행을 지우지 않고 재실행할 수 있게 작성되어 있습니다.

## 2. 교사 이메일 승인과 로그인 설정

학생은 Auth 계정을 만들지 않습니다. 교사만 회원가입할 수 있으며, 가입할 교사 이메일을 먼저 허용 목록에 등록해야 합니다. SQL Editor에서 아래 예시 이메일을 실제 주소로 바꿔 실행하세요.

```sql
insert into public.gamehub_teacher_allowlist(email, enabled)
values ('teacher@school.kr', true)
on conflict (email) do update set enabled = true;
```

가입 허용을 자동으로 적용하려면 Supabase의 **Authentication → Hooks → Before User Created**에서 `public.gamehub_before_user_created` 함수를 연결합니다. 가입 승인용 이메일 목록과 로그인 때의 교사 권한 검사를 모두 사용하므로, 이 Hook을 설정하고 이메일 인증도 켜 두세요. **Authentication → URL Configuration**에서 Site URL과 Redirect URLs에 Production 주소를 등록합니다(예: `https://game-classroom-jade.vercel.app/**`).

SMTP를 따로 설정하지 않았다면 인증 메일 전송 횟수나 수신 주소에 Supabase 기본 제한이 적용될 수 있습니다. 먼저 가입·인증 메일·로그인을 직접 확인하세요.

## 3. 학생 API Edge Function 배포

터미널에서 프로젝트 폴더로 이동한 후, Supabase 프로젝트를 연결하고 함수를 배포합니다. `<PROJECT_REF>`는 Supabase 프로젝트 URL의 `https://<PROJECT_REF>.supabase.co` 부분입니다.

```bash
npx supabase login
npx supabase link --project-ref <PROJECT_REF>
npx supabase functions deploy student-api --no-verify-jwt
```

`--no-verify-jwt`는 학생이 Supabase 계정 없이 호출하는 이 함수에만 사용합니다. 함수 내부에서 방 비밀번호, 개인 비밀번호, 세션, 요청 제한을 검사합니다. 서비스 키는 함수 서버 환경에만 두고 브라우저에 배포하지 않습니다.

## 4. GitHub에 올리기

1. GitHub에서 새 저장소를 만듭니다. 공개 저장소로 올려도 비밀값은 코드에 없고, `.env` 파일은 `.gitignore`에 제외되어야 합니다.
2. 프로젝트 폴더에서 GitHub 안내에 따라 파일을 커밋·푸시합니다. Git 명령을 사용할 경우:

```bash
git init
git add .
git commit -m "수학 게임 교실 배포"
git branch -M main
git remote add origin https://github.com/<계정>/<저장소>.git
git push -u origin main
```

이미 Git 저장소인 프로젝트에서는 `git init`과 `git remote add`를 다시 하지 말고, 수정 파일을 커밋해 푸시하면 됩니다.

## 5. Vercel 배포

1. Vercel에서 **Add New → Project**를 누르고 방금 만든 GitHub 저장소를 가져옵니다.
2. Framework Preset은 **Other**로 둡니다. Build Command는 `npm run build`, Output Directory는 `dist`입니다. 저장소의 `vercel.json`이 이 값을 지정합니다.
3. Project Settings → Environment Variables에서 다음 값을 Production 환경에 추가합니다.

| 이름 | 값 |
|---|---|
| `PUBLIC_SUPABASE_URL` | Supabase Project URL |
| `PUBLIC_SUPABASE_ANON_KEY` | Supabase Publishable key 또는 legacy anon key |
| `PUBLIC_APP_URL` | 선택 사항. 고정된 Production origin, 예: `https://game-classroom-jade.vercel.app` |

`PUBLIC_APP_URL`은 도메인만 입력합니다. `/student.html` 같은 경로를 붙이지 마세요. 입력 후 Deploy하거나 변경사항을 재배포합니다. 학생 페이지(`/student.html`)가 로그인 없이 열리는지 시크릿 창에서 확인합니다.

4. **Deployment Protection**이 켜져 있으면 학생에게 Vercel 로그인을 요구할 수 있습니다. Preview 배포는 보호하고 Production 도메인은 공개하도록 설정하세요. QR에는 Production 주소만 사용합니다.

## 6. Supabase가 Production 사이트를 허용하도록 설정

Supabase Edge Function Secrets에 `ALLOWED_ORIGINS`를 추가해야 QR 참가가 작동합니다. Vercel 주소가 `https://game-classroom-jade.vercel.app`이라면 값도 정확히 그 주소여야 합니다.

Supabase 대시보드에서 **Edge Functions → Secrets**로 이동해 다음을 추가하고 저장합니다.

- Key: `ALLOWED_ORIGINS`
- Value: `https://game-classroom-jade.vercel.app`

주소 끝에 `/student.html`이나 `/`를 붙이지 마세요. 커스텀 도메인도 함께 쓰면 쉼표로 구분합니다. 예: `https://game-classroom-jade.vercel.app,https://math.example.com`.

명령줄에서는 다음과 같이 설정할 수 있습니다.

```bash
npx supabase secrets set ALLOWED_ORIGINS=https://game-classroom-jade.vercel.app --project-ref <PROJECT_REF>
```

이 값은 Supabase의 서버 비밀값입니다. Vercel 환경변수에는 넣지 마세요. 비밀값을 저장하면 보통 함수 재배포 없이 적용됩니다. 새 주소를 사용하도록 교사 페이지도 최신 Production 배포인지 확인하고, 방을 새로 만들어 새 QR을 생성하세요.

## 7. 학생 참가와 게임 시작

1. 교사가 공개 Production 사이트에서 로그인하고 오름차순 게임 방을 만듭니다.
2. 방 비밀번호를 정하고 QR 또는 참가 링크를 학생에게 공유합니다. 비밀번호는 별도로 알려 줍니다.
3. 학생은 QR을 열고 학번, 이름, 본인 비밀번호, 방 비밀번호를 입력합니다. QR 링크에는 방 코드가 자동 입력됩니다.
4. 학생 전원이 참가하면 교사가 게임을 시작합니다. 매 턴 학생은 카드를 보드 빈칸에 한 번 확정하고, 모두 배치한 뒤 교사가 다음 카드를 뽑습니다.
5. 20턴 뒤 점수와 순위가 표시됩니다. 교사는 학생 관리에서 학생 계정과 해당 학생의 기록을 삭제할 수 있습니다.

## 오류 해결: “서버에 연결할 수 없습니다”

학생 화면은 열리지만 참가하기 후 이 오류가 나오면 Edge Function `ALLOWED_ORIGINS` 값이 실제 사이트와 다른지 확인하세요. 이 오류 문구에는 참가를 시도한 정확한 주소가 표시됩니다. 그 주소를 Supabase **Edge Functions → Secrets**의 `ALLOWED_ORIGINS` Value와 일치시켜 저장한 다음 학생 페이지를 새로고침하세요. 이 값은 `https://`를 포함하고 경로와 마지막 `/`는 빼야 합니다.

예를 들어 화면 주소가 `https://game-classroom-jade.vercel.app`이면 허용 목록에도 `https://game-classroom-jade.vercel.app`을 넣습니다. 주소가 바뀌거나 Preview 주소로 참가하면 다시 허용 목록 문제를 만날 수 있으니 Production 링크로 새 QR을 만드세요. 그래도 실패하면 Supabase의 **Edge Functions → student-api → Logs**에서 함수 오류를 확인하고, Vercel 배포 로그에서 빌드가 성공했는지 확인합니다. 서비스 비밀 키를 공유하거나 스크린샷에 노출하지 마세요.

## 개발·테스트

Node.js 22 이상이 필요합니다.

```bash
npm run build
npm test
npm run dev
```

`npm run build`는 `dist/`에 정적 배포 파일을 만듭니다. Supabase 값이 설정되지 않은 로컬 빌드는 안내용 placeholder를 사용하므로 실제 참가·로그인은 되지 않습니다. 브라우저 통합 및 SQL 통합 검사 방법과 한계는 [docs/AUDIT.md](docs/AUDIT.md)를 참고하세요.

## 데이터와 보안 개요

- 교사 계정은 Supabase Auth, 허용 이메일 목록, 이메일 인증과 교사 RPC 권한으로 제한합니다.
- 학생은 회원가입하지 않습니다. 개인 비밀번호와 방 비밀번호의 평문은 DB에 저장하지 않습니다.
- 학생 API는 Supabase Edge Function을 거치며, 데이터 변경은 서버 RPC에서 방·턴·세션을 다시 검증합니다.
- 공통 데이터는 `gamehub_`, 오름차순 게임 전용 데이터는 `streams_` 접두사를 사용합니다.
- 점수는 20칸 보드의 끊기지 않은 비감소 연속 구간 점수 합으로 계산합니다. ★는 1~30 중 점수가 가장 커지는 값으로 판정합니다.
- 후속 게임 메뉴와 공통 게임 레지스트리는 유지되어 있으며, 다른 게임의 실제 플레이는 아직 구현되지 않았습니다.
