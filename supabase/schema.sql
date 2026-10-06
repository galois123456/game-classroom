-- 수학 게임 교실 ver1.01 / 오름차순 게임 ver1.00
-- 기존 데이터 유지. 전체를 한 번에 실행. 다시 실행 가능.
begin;
-- 새 Supabase 프로젝트의 SQL Editor에서 전체 실행하세요.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.gamehub_teachers(
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);
create table if not exists public.gamehub_students(
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id) on delete cascade,
  student_number text not null,
  student_name text not null,
  password_hash text not null,
  last_seen_at timestamptz default now(),
  created_at timestamptz not null default now(),
  unique(teacher_id,student_number)
);
create table if not exists public.gamehub_games(
  game_key text primary key, title text not null, game_url text not null, enabled boolean not null default true
);
insert into public.gamehub_games values
('streams','오름차순 게임','games/streams-student.html',true),
('baseball1v1','1:1 숫자야구','games/baseball-1v1.html',false),
('baseball_class','일대다수 숫자야구','games/baseball-class.html',false),
('gugudan_rpg','구구단 RPG','games/gugudan-rpg.html',false),
('arithmetic','사칙연산 게임','games/arithmetic.html',false),
('middle_math','중등수학 기초연산','games/middle-math.html',false),
('elementary_math','초등학교 기초연산','games/elementary-math.html',false)
on conflict(game_key) do update set title=excluded.title,game_url=excluded.game_url;

create table if not exists public.gamehub_results(
 id bigint generated always as identity primary key,
 teacher_id uuid not null references auth.users(id) on delete cascade,
 student_id uuid references public.gamehub_students(id) on delete cascade,
 game_key text not null references public.gamehub_games(game_key),
 score integer default 0, detail jsonb default '{}'::jsonb, created_at timestamptz default now()
);

create table if not exists public.streams_rooms(
 id uuid primary key default gen_random_uuid(),
 teacher_id uuid not null references auth.users(id) on delete cascade,
 room_code text not null unique,
 password_hash text not null,
 status text not null default 'WAITING',
 deck jsonb not null default '[]'::jsonb,
 current_turn integer not null default 0,
 current_card text,
 history jsonb not null default '[]'::jsonb,
 created_at timestamptz default now(), ended_at timestamptz
);
create table if not exists public.streams_players(
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.streams_rooms(id) on delete cascade,
 student_id uuid not null references public.gamehub_students(id) on delete cascade,
 student_number text not null, student_name text not null,
 board jsonb not null default '[null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]'::jsonb,
 has_placed boolean not null default false, score integer not null default 0,
 joined_at timestamptz default now(), unique(room_id,student_id)
);


-- Additive migration from the attached ver1.00 schema.
create table if not exists public.gamehub_teacher_allowlist(
 email text primary key check(email=lower(trim(email))), enabled boolean not null default true
);
create table if not exists public.gamehub_sessions(
 token_hash text primary key, student_id uuid not null references public.gamehub_students(id) on delete cascade,
 game_key text not null references public.gamehub_games(game_key), room_id uuid not null,
 expires_at timestamptz not null default now()+interval '12 hours', created_at timestamptz not null default now()
);
create index if not exists gamehub_sessions_student_idx on public.gamehub_sessions(student_id);
create index if not exists gamehub_sessions_expiry_idx on public.gamehub_sessions(expires_at);
create table if not exists public.gamehub_rate_limits(
 bucket text primary key, window_start timestamptz not null, hits int not null
);
create table if not exists public.streams_room_events(
 room_id uuid primary key references public.streams_rooms(id) on delete cascade,
 teacher_id uuid not null references auth.users(id) on delete cascade,
 revision bigint not null default 0
);
alter table public.streams_players add column if not exists placed_turn integer not null default 0;
alter table public.streams_players add column if not exists last_slot integer;
alter table public.streams_players add column if not exists is_active boolean not null default true;
alter table public.gamehub_results add column if not exists source_id uuid;
create unique index if not exists gamehub_results_source_idx on public.gamehub_results(student_id,game_key,source_id);
create index if not exists streams_rooms_teacher_idx on public.streams_rooms(teacher_id);
create index if not exists streams_players_student_idx on public.streams_players(student_id);
create index if not exists gamehub_results_teacher_idx on public.gamehub_results(teacher_id);

create or replace function public.gamehub_is_teacher()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u join public.gamehub_teacher_allowlist a on a.email=lower(u.email)
 where u.id=auth.uid() and u.email_confirmed_at is not null and a.enabled);
$$;
create or replace function public.gamehub_before_user_created(event jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if coalesce((event->'user'->>'is_anonymous')::boolean,false) or not exists(
 select 1 from public.gamehub_teacher_allowlist where email=lower(event->'user'->>'email') and enabled) then
 return '{"error":{"http_code":403,"message":"승인된 교사 이메일만 가입할 수 있습니다."}}'::jsonb;
 end if;
 return '{}'::jsonb;
end$$;

-- Remove the original broad policies, including on re-runs. Only this app's tables.
do $$ declare t text; pol record; begin
 foreach t in array array['gamehub_teachers','gamehub_students','gamehub_games','gamehub_results',
 'gamehub_teacher_allowlist','gamehub_sessions','gamehub_rate_limits','streams_rooms','streams_players','streams_room_events'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on table public.%I from anon, authenticated',t);
 for pol in select policyname from pg_policies where schemaname='public' and tablename=t loop
 execute format('drop policy %I on public.%I',pol.policyname,t); end loop;
 end loop;
end$$;
create policy teacher_profile on public.gamehub_teachers for select to authenticated using(user_id=auth.uid() and public.gamehub_is_teacher());
create policy teacher_students on public.gamehub_students for select to authenticated using(teacher_id=auth.uid() and public.gamehub_is_teacher());
create policy teacher_results on public.gamehub_results for select to authenticated using(teacher_id=auth.uid() and public.gamehub_is_teacher());
create policy games_read on public.gamehub_games for select to anon,authenticated using(true);
create policy teacher_rooms on public.streams_rooms for select to authenticated using(teacher_id=auth.uid() and public.gamehub_is_teacher());
create policy teacher_players on public.streams_players for select to authenticated using(public.gamehub_is_teacher() and exists(select 1 from public.streams_rooms r where r.id=room_id and r.teacher_id=auth.uid()));
create policy teacher_events on public.streams_room_events for select to authenticated using(teacher_id=auth.uid() and public.gamehub_is_teacher());
grant select on public.gamehub_games to anon,authenticated;
grant select on public.gamehub_teachers,public.gamehub_results,public.streams_players,public.streams_room_events to authenticated;
grant select(id,teacher_id,student_number,student_name,last_seen_at,created_at) on public.gamehub_students to authenticated;
grant select(id,teacher_id,room_code,status,current_turn,current_card,history,created_at,ended_at) on public.streams_rooms to authenticated;

create or replace function public.gamehub_hash_password(plain_text text)
returns text language plpgsql security definer set search_path='' as $$
begin
 if plain_text is null or char_length(plain_text)<6 or octet_length(plain_text)>72 then
 raise exception '비밀번호는 6자 이상, UTF-8 72바이트 이하여야 합니다.'; end if;
 return extensions.crypt(plain_text,extensions.gen_salt('bf',10));
end$$;
create or replace function public.gamehub_verify_password(plain_text text,password_hash text)
returns boolean language sql security definer set search_path='' as $$
 select coalesce(octet_length(plain_text)<=72 and extensions.crypt(plain_text,password_hash)=password_hash,false);
$$;
create or replace function public.gamehub_consume_limit(p_bucket text,p_limit int,p_seconds int)
returns boolean language plpgsql security definer set search_path='' as $$
declare n int; begin
 insert into public.gamehub_rate_limits(bucket,window_start,hits) values(p_bucket,clock_timestamp(),1)
 on conflict(bucket) do update set
 hits=case when gamehub_rate_limits.window_start<clock_timestamp()-make_interval(secs=>p_seconds) then 1 else gamehub_rate_limits.hits+1 end,
 window_start=case when gamehub_rate_limits.window_start<clock_timestamp()-make_interval(secs=>p_seconds) then clock_timestamp() else gamehub_rate_limits.window_start end
 returning hits into n;
 return n<=p_limit;
end$$;

-- A star resolves to one integer 1..30 that maximizes the sum of disjoint non-decreasing runs.
create or replace function public.streams_evaluate(p_board jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare points int[]:=array[0,1,3,5,7,9,11,15,20,25,30,35,40,50,60,70,85,100,150,300];
 star int; candidate int; value int; prev int; run int; start_at int; total int; best int:=-1;
 i int; item text; runs jsonb; best_runs jsonb; best_star int;
begin
 if jsonb_typeof(p_board)<>'array' or jsonb_array_length(p_board)<>20 then raise exception '20칸 보드가 필요합니다.'; end if;
 if (select count(*) from jsonb_array_elements_text(p_board) v where v='★')>1 then raise exception '별 카드는 한 장입니다.'; end if;
 for candidate in 1..30 loop
 total:=0; run:=0; prev:=null; runs:='[]'::jsonb; star:=null;
 for i in 0..20 loop
 item:=case when i<20 then p_board->>i else null end;
 value:=null;
 if item='★' then value:=candidate; star:=candidate;
 elsif item is not null then
 if item !~ '^([1-9]|[12][0-9]|30)$' then raise exception '잘못된 카드입니다.'; end if;
 value:=item::int; end if;
 if run>0 and (value is null or value<prev) then
 total:=total+points[run];
 runs:=runs||jsonb_build_array(jsonb_build_object('start',start_at,'end',i-1,'length',run,'score',points[run])); run:=0;
 end if;
 if value is not null then
 if run=0 then start_at:=i; end if;
 run:=run+1; prev:=value;
 else prev:=null; end if;
 end loop;
 if total>best then best:=total;best_runs:=runs;best_star:=star;end if;
 if star is null then exit; end if;
 end loop;
 return jsonb_build_object('score',best,'runs',best_runs,'starValue',best_star);
end$$;

create or replace function public.streams_notify(p_room uuid)
returns void language sql security definer set search_path='' as $$
 insert into public.streams_room_events(room_id,teacher_id,revision)
 select id,teacher_id,1 from public.streams_rooms where id=p_room
 on conflict(room_id) do update set revision=streams_room_events.revision+1;
$$;
create or replace function public.streams_finish(p_room uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 update public.streams_players set score=(public.streams_evaluate(board)->>'score')::int where room_id=p_room;
 update public.streams_rooms set status='ENDED',ended_at=now() where id=p_room;
 insert into public.gamehub_results(teacher_id,student_id,game_key,score,detail,source_id)
 select r.teacher_id,p.student_id,'streams',p.score,
 jsonb_build_object('board',p.board,'evaluation',public.streams_evaluate(p.board),'turns',r.current_turn),r.id
 from public.streams_players p join public.streams_rooms r on r.id=p.room_id where r.id=p_room and p.is_active
 on conflict(student_id,game_key,source_id) do update set score=excluded.score,detail=excluded.detail;
 perform public.streams_notify(p_room);
end$$;

create or replace function public.streams_snapshot(p_room uuid,p_student uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.streams_rooms; players jsonb; me jsonb; ranks jsonb; begin
 select * into r from public.streams_rooms where id=p_room;
 if not found then raise exception '방을 찾을 수 없습니다.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('rank',x.rank,'label','참가자 '||x.seat,'score',x.score,'isMe',x.student_id=p_student)
 order by x.rank,x.seat),'[]'::jsonb) into ranks from
 (select student_id,score,rank() over(order by score desc) rank,row_number() over(order by joined_at,id) seat
 from public.streams_players where room_id=p_room and is_active)x;
 if p_student is null then
 select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('evaluation',public.streams_evaluate(p.board)) order by p.student_number),'[]'::jsonb)
 into players from public.streams_players p where p.room_id=p_room;
 else
 select to_jsonb(p)||jsonb_build_object('evaluation',public.streams_evaluate(p.board)) into me
 from public.streams_players p where p.room_id=p_room and p.student_id=p_student;
 end if;
 return jsonb_build_object('room',jsonb_build_object('id',r.id,'room_code',r.room_code,'status',r.status,
 'current_turn',r.current_turn,'current_card',r.current_card,'history',r.history),
 'me',me,'players',players,'ranking',case when r.status='ENDED' then ranks else '[]'::jsonb end,
 'total',(select count(*) from public.streams_players where room_id=p_room and is_active),
 'placed',(select count(*) from public.streams_players where room_id=p_room and is_active and has_placed));
end$$;

-- Drop only the three old function signatures, whose return types change. No table/data reset.
drop function if exists public.streams_create_room(text);
drop function if exists public.streams_draw_card(uuid);
drop function if exists public.streams_end_room(uuid);
create or replace function public.streams_teacher_command(p_action text,p_room uuid default null,p_password text default null,p_player uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.streams_rooms; d jsonb; c text; i int; h text; begin
 if not public.gamehub_is_teacher() then raise exception '승인된 교사 로그인이 필요합니다.'; end if;
 if p_action='create' then
 if (select count(*) from public.streams_rooms where teacher_id=auth.uid() and status<>'ENDED')>=10 then raise exception '진행 중인 방을 먼저 종료하세요. (최대 10개)'; end if;
 h:=public.gamehub_hash_password(p_password);
 select jsonb_agg(v order by random()) into d from (select n::text v from generate_series(1,30)n union all select n::text from generate_series(11,19)n union all select '★')x;
 for i in 1..10 loop
 c:=upper(encode(extensions.gen_random_bytes(4),'hex'));
 begin
 insert into public.streams_rooms(teacher_id,room_code,password_hash,status,deck)
 values(auth.uid(),c,h,'WAITING',d) returning * into r;
 exit;
 exception when unique_violation then if i=10 then raise; end if; end;
 end loop;
 else
 select * into r from public.streams_rooms where id=p_room and teacher_id=auth.uid() for update;
 if not found then raise exception '방을 찾을 수 없습니다.'; end if;
 if p_action='start' then
 if r.status<>'WAITING' then raise exception '이미 시작된 방입니다.'; end if;
 if not exists(select 1 from public.streams_players where room_id=r.id and is_active) then raise exception '학생이 참가한 뒤 시작하세요.'; end if;
 update public.streams_rooms set status='PLAYING',current_turn=1,current_card=deck->>0,history=jsonb_build_array(deck->>0) where id=r.id;
 elsif p_action='next' then
 if r.status<>'PLAYING' or r.current_turn>=20 then raise exception '다음 카드를 뽑을 수 없습니다.'; end if;
 if exists(select 1 from public.streams_players where room_id=r.id and is_active and not has_placed) then raise exception '모든 학생의 배치를 기다려 주세요.'; end if;
 update public.streams_rooms set current_turn=current_turn+1,current_card=deck->>current_turn,history=history||jsonb_build_array(deck->>current_turn) where id=r.id;
 update public.streams_players set has_placed=false where room_id=r.id and is_active;
 elsif p_action='end' then
 if r.status<>'ENDED' then perform public.streams_finish(r.id); end if;
 elsif p_action='kick' then
 if r.status='ENDED' then raise exception '종료된 게임입니다.'; end if;
 update public.streams_players set is_active=false where id=p_player and room_id=r.id;
 delete from public.gamehub_sessions where room_id=r.id and student_id in(select student_id from public.streams_players where id=p_player and room_id=r.id);
 if r.current_turn=20 and not exists(select 1 from public.streams_players where room_id=r.id and is_active and not has_placed) then perform public.streams_finish(r.id); end if;
 elsif p_action='delete' then
 delete from public.gamehub_results where teacher_id=auth.uid() and game_key='streams' and source_id=r.id;
 delete from public.gamehub_sessions where game_key='streams' and room_id=r.id;
 delete from public.streams_rooms where id=r.id;
 return '{"deleted":true}'::jsonb;
 elsif p_action<>'state' then raise exception '지원하지 않는 요청입니다.'; end if;
 end if;
 if p_action<>'state' then perform public.streams_notify(r.id); end if;
 return public.streams_snapshot(r.id);
end$$;
create function public.streams_create_room(p_password text) returns jsonb language sql security invoker set search_path='' as $$ select public.streams_teacher_command('create',null,p_password); $$;
create function public.streams_draw_card(p_room_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select public.streams_teacher_command('next',p_room_id); $$;
create function public.streams_end_room(p_room_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select public.streams_teacher_command('end',p_room_id); $$;

create or replace function public.streams_join(p_code text,p_room_password text,p_number text,p_name text,p_password text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.streams_rooms; s public.gamehub_students; p public.streams_players; token text; begin
 if p_code is null or p_number is null or p_name is null or p_password is null or p_room_password is null
 or p_code !~ '^[A-Z0-9]{6,8}$' or p_number !~ '^[A-Za-z0-9_-]{1,24}$'
 or char_length(trim(p_name)) not between 1 and 40 or char_length(p_password)<4 or octet_length(p_password)>72
 then raise exception '입력 형식을 확인하세요. 개인 비밀번호는 6자 이상입니다.'; end if;
 select * into r from public.streams_rooms where room_code=p_code for update;
 if not found then raise exception '방 코드 또는 인증 정보를 확인하세요.'; end if;
 if not public.gamehub_verify_password(p_room_password,r.password_hash) then raise exception '방 코드 또는 인증 정보를 확인하세요.'; end if;
 -- Also serialize a student's first registration across different rooms of the same teacher.
 perform pg_advisory_xact_lock(hashtextextended(r.teacher_id::text||':'||p_number,0));
 select * into s from public.gamehub_students where teacher_id=r.teacher_id and student_number=p_number for update;
 if found then
 if not public.gamehub_verify_password(p_password,s.password_hash) or s.student_name<>trim(p_name) then raise exception '학번·이름·개인 비밀번호를 확인하세요.'; end if;
 else
 if r.status<>'WAITING' then raise exception '시작된 방에는 새로 참가할 수 없습니다.'; end if;
 insert into public.gamehub_students(teacher_id,student_number,student_name,password_hash)
 values(r.teacher_id,p_number,trim(p_name),public.gamehub_hash_password(p_password)) returning * into s;
 end if;
 select * into p from public.streams_players where room_id=r.id and student_id=s.id;
 if found then
 if not p.is_active then raise exception '교사가 참가를 종료한 학생입니다.'; end if;
 else
 if r.status<>'WAITING' then raise exception '시작된 방에는 새로 참가할 수 없습니다.'; end if;
 if (select count(*) from public.streams_players where room_id=r.id)>=60 then raise exception '한 방에는 60명까지 참가할 수 있습니다.'; end if;
 insert into public.streams_players(room_id,student_id,student_number,student_name) values(r.id,s.id,p_number,s.student_name);
 end if;
 update public.gamehub_students set last_seen_at=now() where id=s.id;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 -- One live session per student per game room. Rejoin rotates it without resetting the board.
 delete from public.gamehub_sessions where student_id=s.id and game_key='streams' and room_id=r.id;
 insert into public.gamehub_sessions(token_hash,student_id,game_key,room_id)
 values(encode(extensions.digest(token,'sha256'),'hex'),s.id,'streams',r.id);
 perform public.streams_notify(r.id);
 return jsonb_build_object('sessionToken',token,'roomCode',r.room_code,'gameKey','streams','expiresAt',now()+interval '12 hours');
end$$;

create or replace function public.streams_student_command(p_action text,p_token text,p_turn int default null,p_slot int default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.gamehub_sessions; r public.streams_rooms; p public.streams_players; begin
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'SESSION_EXPIRED'; end if;
 select * into sess from public.gamehub_sessions where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and game_key='streams' and expires_at>now();
 if not found then raise exception 'SESSION_EXPIRED'; end if;
 -- Same lock order as host: room -> player. State is also a consistent snapshot.
 select * into r from public.streams_rooms where id=sess.room_id for update;
 if not found then raise exception 'SESSION_EXPIRED'; end if;
 if not exists(select 1 from public.gamehub_sessions where token_hash=sess.token_hash and expires_at>now()) then raise exception 'SESSION_EXPIRED'; end if;
 select * into p from public.streams_players where room_id=r.id and student_id=sess.student_id for update;
 if not found or not p.is_active then raise exception 'SESSION_EXPIRED'; end if;
 if p_action='logout' then
 delete from public.gamehub_sessions where token_hash=sess.token_hash;
 return '{"ok":true}'::jsonb;
 elsif p_action='place' then
 if p_turn is null or p_slot is null or p_slot not between 0 and 19 then raise exception '잘못된 배치입니다.'; end if;
 -- Exact retry is idempotent, including the automatically ended last turn.
 if p.placed_turn=p_turn and p.last_slot=p_slot then return public.streams_snapshot(r.id,sess.student_id); end if;
 if r.status<>'PLAYING' or r.current_turn<>p_turn then raise exception '턴이 변경되었습니다. 화면을 새로 고쳐 주세요.'; end if;
 if p.has_placed or p.placed_turn>=p_turn then raise exception '이번 카드는 이미 배치했습니다.'; end if;
 if p.board->p_slot<>'null'::jsonb then raise exception '빈칸을 선택하세요.'; end if;
 update public.streams_players set board=jsonb_set(board,array[p_slot::text],to_jsonb(r.current_card)),has_placed=true,placed_turn=p_turn,last_slot=p_slot where id=p.id;
 update public.streams_players set score=(public.streams_evaluate(board)->>'score')::int where id=p.id;
 if r.current_turn=20 and not exists(select 1 from public.streams_players where room_id=r.id and is_active and not has_placed) then perform public.streams_finish(r.id); end if;
 perform public.streams_notify(r.id);
 elsif p_action<>'state' then raise exception '지원하지 않는 요청입니다.'; end if;
 return public.streams_snapshot(r.id,sess.student_id);
end$$;

create or replace function public.gamehub_delete_student(p_student uuid)
returns void language plpgsql security definer set search_path='' as $$
declare r record; begin
 if not public.gamehub_is_teacher() then raise exception '승인된 교사 로그인이 필요합니다.'; end if;
 -- Lock rooms first so deletion cannot race with place/next/join.
 for r in select id from public.streams_rooms where teacher_id=auth.uid() order by id for update loop
 perform public.streams_notify(r.id);
 end loop;
 delete from public.gamehub_students where id=p_student and teacher_id=auth.uid();
 for r in select id from public.streams_rooms where teacher_id=auth.uid() and status='PLAYING' and current_turn=20 loop
 if not exists(select 1 from public.streams_players where room_id=r.id and is_active and not has_placed) then perform public.streams_finish(r.id); end if;
 end loop;
end$$;

create or replace function public.gamehub_cleanup()
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from public.gamehub_sessions where expires_at<now();
 delete from public.gamehub_rate_limits where window_start<now()-interval '1 day';
end$$;

-- SECURITY DEFINER functions have PUBLIC execute by default: explicitly revoke every app function.
do $$ declare f record; begin
 for f in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and (proname like 'gamehub\_%' escape '\' or proname like 'streams\_%' escape '\') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end$$;
grant execute on function public.gamehub_is_teacher() to authenticated;
grant execute on function public.gamehub_before_user_created(jsonb) to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.streams_teacher_command(text,uuid,text,uuid),public.streams_create_room(text),public.streams_draw_card(uuid),public.streams_end_room(uuid),public.gamehub_delete_student(uuid) to authenticated;

-- Broadcast only an invalidation counter, never passwords/decks/player records.
do $$ declare t text; begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
 foreach t in array array['streams_rooms','streams_players'] loop
 if exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then execute format('alter publication supabase_realtime drop table public.%I',t); end if;
 end loop;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='streams_room_events') then alter publication supabase_realtime add table public.streams_room_events; end if;
 end if;
end$$;
commit;
