-- 수학 게임 교실 ver1.03 / 오름차순 게임 ver1.00
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
 if (select count(*) from public.streams_players where room_id=r.id)>=100 then raise exception '한 방에는 100명까지 참가할 수 있습니다.'; end if;
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

-- ver1.03 additive games: 1:1 baseball, class baseball, arithmetic challenge.
begin;

create table if not exists public.baseball1v1_rooms(
 id uuid primary key default gen_random_uuid(), teacher_id uuid not null references auth.users(id) on delete cascade,
 room_code text not null unique, room_password_hash text not null, digit_length int not null check(digit_length in (3,4,5)),
 allow_zero boolean not null default true, max_rounds int not null check(max_rounds between 1 and 50),
 status text not null default 'WAITING' check(status in ('WAITING','SETTING_SECRET','PLAYING','ENDED')),
 current_round int not null default 1, winner_player_id uuid, result_text text default '', created_at timestamptz not null default now(), ended_at timestamptz
);
create table if not exists public.baseball1v1_players(
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.baseball1v1_rooms(id) on delete cascade,
 student_id uuid not null references public.gamehub_students(id) on delete cascade, nickname text not null,
 secret_number text, is_active boolean not null default true, joined_at timestamptz not null default now(), unique(room_id,student_id)
);
alter table public.baseball1v1_rooms drop constraint if exists baseball1v1_rooms_winner_player_id_fkey;
alter table public.baseball1v1_rooms add constraint baseball1v1_rooms_winner_player_id_fkey foreign key(winner_player_id) references public.baseball1v1_players(id) on delete set null;
create table if not exists public.baseball1v1_guesses(
 id bigint generated always as identity primary key, room_id uuid not null references public.baseball1v1_rooms(id) on delete cascade,
 player_id uuid not null references public.baseball1v1_players(id) on delete cascade, target_player_id uuid not null references public.baseball1v1_players(id) on delete cascade,
 round_number int not null, guess_number text not null, strikes int not null, balls int not null, is_home_run boolean not null, created_at timestamptz not null default now(), unique(player_id,round_number)
);
create index if not exists baseball1v1_guesses_room_round_idx on public.baseball1v1_guesses(room_id,round_number);

create table if not exists public.baseballclass_rooms(
 id uuid primary key default gen_random_uuid(), teacher_id uuid not null references auth.users(id) on delete cascade,
 room_code text not null unique, room_password_hash text not null, answer_number text not null,
 digit_length int not null check(digit_length in (3,4,5)), allow_zero boolean not null default true,
 max_rounds int not null check(max_rounds between 1 and 30), status text not null default 'WAITING' check(status in ('WAITING','PLAYING','ENDED')),
 created_at timestamptz not null default now(), started_at timestamptz, ended_at timestamptz
);
create table if not exists public.baseballclass_players(
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.baseballclass_rooms(id) on delete cascade,
 student_id uuid not null references public.gamehub_students(id) on delete cascade, nickname text not null,
 status text not null default 'WAITING' check(status in ('WAITING','PLAYING','SUCCESS','FAILED','LEFT')),
 joined_at timestamptz not null default now(), ended_at timestamptz, unique(room_id,student_id)
);
create table if not exists public.baseballclass_guesses(
 id bigint generated always as identity primary key, room_id uuid not null references public.baseballclass_rooms(id) on delete cascade,
 player_id uuid not null references public.baseballclass_players(id) on delete cascade,
 attempt_number int not null, guess_number text not null, strikes int not null, balls int not null, is_out boolean not null, is_home_run boolean not null,
 created_at timestamptz not null default now(), unique(player_id,attempt_number)
);
create index if not exists baseballclass_guesses_room_idx on public.baseballclass_guesses(room_id,player_id,attempt_number);

create table if not exists public.arithmetic_rooms(
 id uuid primary key default gen_random_uuid(), teacher_id uuid not null references auth.users(id) on delete cascade,
 room_code text not null unique, room_password_hash text not null, selected_operations jsonb not null,
 digit_settings jsonb not null, total_questions int not null check(total_questions between 1 and 500),
 wrong_answer_mode text not null check(wrong_answer_mode in ('gameover','reset_zero','minus1','minus2','continue')),
 status text not null default 'WAITING' check(status in ('WAITING','PLAYING','ENDED')),
 created_at timestamptz not null default now(), started_at timestamptz, ended_at timestamptz
);
create table if not exists public.arithmetic_players(
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.arithmetic_rooms(id) on delete cascade,
 student_id uuid not null references public.gamehub_students(id) on delete cascade, nickname text not null,
 status text not null default 'WAITING' check(status in ('WAITING','PLAYING','FINISHED','FAILED','LEFT')),
 correct_count int not null default 0, wrong_count int not null default 0, score int not null default 0,
 level int not null default 1, question_number int not null default 1, current_question jsonb,
 started_at timestamptz, ended_at timestamptz, elapsed_seconds int not null default 0, updated_at timestamptz not null default now(),
 unique(room_id,student_id)
);

alter table public.baseball1v1_rooms enable row level security;
alter table public.baseball1v1_players enable row level security;
alter table public.baseball1v1_guesses enable row level security;
alter table public.baseballclass_rooms enable row level security;
alter table public.baseballclass_players enable row level security;
alter table public.baseballclass_guesses enable row level security;
alter table public.arithmetic_rooms enable row level security;
alter table public.arithmetic_players enable row level security;
revoke all on public.baseball1v1_rooms,public.baseball1v1_players,public.baseball1v1_guesses,
 public.baseballclass_rooms,public.baseballclass_players,public.baseballclass_guesses,
 public.arithmetic_rooms,public.arithmetic_players from anon,authenticated;

create or replace function public.gamehub_join_game(p_game text,p_code text,p_room_password text,p_number text,p_name text,p_password text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r record; s public.gamehub_students; token text; active_count int; player_id uuid; active_player boolean; player_status text; begin
 if p_game not in ('baseball1v1','baseball_class','arithmetic') then raise exception '지원하지 않는 게임입니다.'; end if;
 if p_code !~ '^[A-Z0-9]{6,8}$' or p_number !~ '^[-_A-Za-z0-9]{1,24}$' or char_length(trim(p_name)) not between 1 and 40
 or length(p_password)<4 or octet_length(p_password)>72 or octet_length(p_room_password)>72 then raise exception '참가 정보를 확인하세요.'; end if;
 if p_game='baseball1v1' then
  select * into r from public.baseball1v1_rooms where room_code=p_code for update;
 elsif p_game='baseball_class' then
  select * into r from public.baseballclass_rooms where room_code=p_code for update;
 else
  select * into r from public.arithmetic_rooms where room_code=p_code for update;
 end if;
 if not found then raise exception '방 코드 또는 비밀번호를 확인하세요.'; end if;
 if not public.gamehub_verify_password(p_room_password,r.room_password_hash) then raise exception '방 코드 또는 비밀번호를 확인하세요.'; end if;
 if r.status='ENDED' then raise exception '이미 종료된 방입니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(r.teacher_id::text||':'||p_number,0));
 select * into s from public.gamehub_students where teacher_id=r.teacher_id and student_number=p_number for update;
 if found then
  if s.student_name<>trim(p_name) or not public.gamehub_verify_password(p_password,s.password_hash) then raise exception '학번·이름·개인 비밀번호를 확인하세요.'; end if;
 else
  insert into public.gamehub_students(teacher_id,student_number,student_name,password_hash)
  values(r.teacher_id,p_number,trim(p_name),public.gamehub_hash_password(p_password)) returning * into s;
 end if;
 if p_game='baseball1v1' then
  select id into player_id from public.baseball1v1_players where room_id=r.id and student_id=s.id;
  if player_id is not null then select is_active into active_player from public.baseball1v1_players where id=player_id; if not active_player then raise exception '이미 참가를 종료한 학생입니다.'; end if; end if;
  if player_id is null then
   select count(*) into active_count from public.baseball1v1_players where room_id=r.id and is_active;
   if active_count>=2 or r.status<>'WAITING' then raise exception '1:1 방은 두 명만 참가할 수 있습니다.'; end if;
   insert into public.baseball1v1_players(room_id,student_id,nickname) values(r.id,s.id,trim(p_name)) returning id into player_id;
   if active_count+1=2 then update public.baseball1v1_rooms set status='SETTING_SECRET' where id=r.id; end if;
  end if;
 elsif p_game='baseball_class' then
  select id into player_id from public.baseballclass_players where room_id=r.id and student_id=s.id;
  if player_id is not null then select status into player_status from public.baseballclass_players where id=player_id; if player_status='LEFT' then raise exception '이미 게임에서 나간 학생입니다.'; end if; end if;
  if player_id is null then
   if r.status<>'WAITING' then raise exception '시작된 방에는 새로 참가할 수 없습니다.'; end if;
   select count(*) into active_count from public.baseballclass_players where room_id=r.id;
   if active_count>=100 then raise exception '한 방에는 100명까지 참가할 수 있습니다.'; end if;
   insert into public.baseballclass_players(room_id,student_id,nickname) values(r.id,s.id,trim(p_name)) returning id into player_id;
  end if;
 else
  select id into player_id from public.arithmetic_players where room_id=r.id and student_id=s.id;
  if player_id is not null then select status into player_status from public.arithmetic_players where id=player_id; if player_status='LEFT' then raise exception '이미 게임에서 나간 학생입니다.'; end if; end if;
  if player_id is null then
   if r.status<>'WAITING' then raise exception '시작된 방에는 새로 참가할 수 없습니다.'; end if;
   select count(*) into active_count from public.arithmetic_players where room_id=r.id;
   if active_count>=100 then raise exception '한 방에는 100명까지 참가할 수 있습니다.'; end if;
   insert into public.arithmetic_players(room_id,student_id,nickname) values(r.id,s.id,trim(p_name)) returning id into player_id;
  end if;
 end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 delete from public.gamehub_sessions where student_id=s.id and game_key=p_game and room_id=r.id;
 insert into public.gamehub_sessions(token_hash,student_id,game_key,room_id)
 values(encode(extensions.digest(token,'sha256'),'hex'),s.id,p_game,r.id);
 update public.gamehub_students set last_seen_at=now() where id=s.id;
 return jsonb_build_object('sessionToken',token,'roomCode',p_code,'gameKey',p_game,'expiresAt',now()+interval '12 hours');
end$$;

create or replace function public.arithmetic_make_question(p_ops jsonb,p_digits jsonb,p_level int)
returns jsonb language plpgsql volatile set search_path='' as $$
declare op text; maxv int; a int; b int; ans int; label text; cfg text; t int; c int; begin
 if jsonb_typeof(p_ops)<>'array' or jsonb_array_length(p_ops)=0 then raise exception '연산 설정이 없습니다.'; end if;
 op:=p_ops->>((floor(random()*jsonb_array_length(p_ops)))::int);
 if op='mixed' and (not (p_ops ?| array['add','sub','mul','div']) or (p_level>=10 and random()<0.35)) then
  t:=1+floor(random()*8)::int;
  if t=1 then a:=1+floor(random()*10)::int; b:=1+floor(random()*10)::int; ans:=a*a+b*b; label:=format('%s² + %s²',a,b);
  elsif t=2 then a:=1+floor(random()*12)::int; b:=1+floor(random()*12)::int; ans:=a*a-b*b; label:=format('%s² - %s²',a,b);
  elsif t=3 then a:=1+floor(random()*5)::int; b:=1+floor(random()*10)::int; ans:=a*a*a+b*b; label:=format('%s³ + %s²',a,b);
  elsif t=4 then a:=1+floor(random()*4)::int; b:=1+floor(random()*10)::int; ans:=a*a*a*a-b*b; label:=format('%s⁴ - %s²',a,b);
  elsif t=5 then a:=1+floor(random()*10)::int; b:=1+floor(random()*10)::int; ans:=a+b*b; label:=format('√%s + %s²',a*a,b);
  elsif t=6 then a:=1+floor(random()*5)::int; b:=1+floor(random()*10)::int; ans:=a*a*a-b; label:=format('%s³ - √%s',a,b*b);
  elsif t=7 then a:=1+floor(random()*10)::int; b:=1+floor(random()*10)::int; c:=1+floor(random()*10)::int; ans:=a*a+b*b-c; label:=format('%s² + %s² - %s',a,b,c);
  else a:=1+floor(random()*5)::int; b:=1+floor(random()*5)::int; c:=1+floor(random()*10)::int; ans:=a*a*a+b*b*b-c; label:=format('%s³ + %s³ - %s',a,b,c); end if;
  return jsonb_build_object('text',label,'answer',ans,'operation','mixed');
 end if;
 if op='mixed' then select x into op from jsonb_array_elements_text(p_ops) x where x in ('add','sub','mul','div') order by random() limit 1; end if;
 cfg:=coalesce(p_digits->>op,'auto');
 if cfg='auto' then
  if op in ('add','sub') then maxv:=10+greatest(1,p_level)*10; else maxv:=least(12+greatest(1,p_level),25); end if;
 else maxv:=power(10,least(3,greatest(1,cfg::int)))::int-1; end if;
 a:=1+floor(random()*greatest(1,maxv))::int; if random()>=0.7 then a:=-a; end if;
 b:=1+floor(random()*greatest(1,maxv))::int; if random()>=0.7 then b:=-b; end if;
 if op='add' then ans:=a+b; label:=format('%s + %s',case when a<0 then '('||a||')' else a::text end,case when b<0 then '('||b||')' else b::text end);
 elsif op='sub' then ans:=a-b; label:=format('%s - %s',case when a<0 then '('||a||')' else a::text end,case when b<0 then '('||b||')' else b::text end);
 elsif op='mul' then ans:=a*b; label:=format('%s × %s',case when a<0 then '('||a||')' else a::text end,case when b<0 then '('||b||')' else b::text end);
 elsif op='div' then
  b:=1+floor(random()*greatest(1,maxv))::int; if random()>=0.7 then b:=-b; end if;
  a:=(1+floor(random()*greatest(1,maxv))::int)*b; if random()>=0.7 then a:=-a; end if; ans:=a/b;
  label:=format('%s ÷ %s',case when a<0 then '('||a||')' else a::text end,case when b<0 then '('||b||')' else b::text end);
 elsif op in ('square','sqrt','cube','fourth') then
  if op='square' then maxv:=least(12+greatest(1,p_level),25); a:=1+floor(random()*maxv)::int; if random()>=0.7 then a:=-a; end if; ans:=a*a; label:=case when a<0 then '('||a||')²' else a||'²' end;
  elsif op='sqrt' then maxv:=least(12+greatest(1,p_level),25); ans:=1+floor(random()*maxv)::int; a:=ans*ans; label:='√'||a;
  elsif op='cube' then maxv:=least(3+greatest(1,p_level)/3,6); a:=1+floor(random()*maxv)::int; if random()>=0.7 then a:=-a; end if; ans:=a*a*a; label:=case when a<0 then '('||a||')³' else a||'³' end;
  else maxv:=least(2+greatest(1,p_level)/4,4); a:=1+floor(random()*maxv)::int; if random()>=0.7 then a:=-a; end if; ans:=a*a*a*a; label:=case when a<0 then '('||a||')⁴' else a||'⁴' end; end if;
 else raise exception '지원하지 않는 연산입니다.'; end if;
 return jsonb_build_object('text',label,'answer',ans,'operation',op);
end$$;

create or replace function public.gamehub_teacher_game_command(p_game text,p_action text,p_room uuid default null,p_settings jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r record; code text; new_id uuid; answer text; digits int; max_rounds int; zero_ok boolean; ops jsonb; dset jsonb; q text; begin
 if not public.gamehub_is_teacher() then raise exception '승인된 교사 로그인이 필요합니다.'; end if;
 if p_game not in ('baseball1v1','baseball_class','arithmetic') then raise exception '지원하지 않는 게임입니다.'; end if;
 if p_action='create' then
  if length(coalesce(p_settings->>'roomPassword',''))<1 or octet_length(p_settings->>'roomPassword')>72 then raise exception '방 비밀번호를 입력하세요.'; end if;
  code:=upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,8));
  if p_game='baseball1v1' then
   digits:=coalesce((p_settings->>'digitLength')::int,4); max_rounds:=coalesce((p_settings->>'maxRounds')::int,9); zero_ok:=coalesce((p_settings->>'allowZero')::boolean,true);
   if digits not in (3,4,5) or max_rounds not between 1 and 50 then raise exception '자리수 또는 라운드 설정을 확인하세요.'; end if;
   insert into public.baseball1v1_rooms(teacher_id,room_code,room_password_hash,digit_length,allow_zero,max_rounds)
   values(auth.uid(),code,public.gamehub_hash_password(p_settings->>'roomPassword'),digits,zero_ok,max_rounds) returning id into new_id;
  elsif p_game='baseball_class' then
   digits:=coalesce((p_settings->>'digitLength')::int,4); max_rounds:=coalesce((p_settings->>'maxRounds')::int,9); zero_ok:=coalesce((p_settings->>'allowZero')::boolean,true); answer:=coalesce(p_settings->>'answerNumber','');
   if digits not in (3,4,5) or max_rounds not between 1 and 30 or length(answer)<>digits or answer !~ '^[0-9]+$' or (not zero_ok and position('0' in answer)>0) or answer ~ '([0-9]).*\1' then raise exception '정답 숫자, 자리수 또는 라운드 설정을 확인하세요. 중복 숫자는 사용할 수 없습니다.'; end if;
   insert into public.baseballclass_rooms(teacher_id,room_code,room_password_hash,answer_number,digit_length,allow_zero,max_rounds)
   values(auth.uid(),code,public.gamehub_hash_password(p_settings->>'roomPassword'),answer,digits,zero_ok,max_rounds) returning id into new_id;
  else
   ops:=p_settings->'selectedOperations'; if jsonb_typeof(ops)<>'array' or jsonb_array_length(ops)=0 then raise exception '연산을 하나 이상 선택하세요.'; end if;
   if exists(select 1 from jsonb_array_elements_text(ops) x where x not in ('add','sub','mul','div','square','sqrt','cube','fourth','mixed')) then raise exception '연산 설정을 확인하세요.'; end if;
   if (select count(distinct x) from jsonb_array_elements_text(ops) x)<>jsonb_array_length(ops) then raise exception '같은 연산을 중복 선택할 수 없습니다.'; end if;
   max_rounds:=coalesce((p_settings->>'totalQuestions')::int,100); if max_rounds not between 1 and 500 then raise exception '문제 수는 1~500 사이여야 합니다.'; end if;
   dset:=coalesce(p_settings->'digitSettings','{"add":"auto","sub":"auto","mul":"auto","div":"auto"}'::jsonb);
   if dset->>'add' not in ('auto','1','2','3') or dset->>'sub' not in ('auto','1','2','3') or dset->>'mul' not in ('auto','1','2','3') or dset->>'div' not in ('auto','1','2','3') then raise exception '자릿수 설정을 확인하세요.'; end if;
   q:=coalesce(p_settings->>'wrongAnswerMode','gameover'); if q not in ('gameover','reset_zero','minus1','minus2','continue') then raise exception '오답 처리 방식을 확인하세요.'; end if;
   insert into public.arithmetic_rooms(teacher_id,room_code,room_password_hash,selected_operations,digit_settings,total_questions,wrong_answer_mode)
   values(auth.uid(),code,public.gamehub_hash_password(p_settings->>'roomPassword'),ops,dset,max_rounds,q) returning id into new_id;
  end if;
  return jsonb_build_object('id',new_id,'room_code',code,'status','WAITING');
 end if;
 if p_action='list' then
  if p_game='baseball1v1' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'room_code',room_code,'status',status,'created_at',created_at) order by created_at desc) from public.baseball1v1_rooms where teacher_id=auth.uid()),'[]'::jsonb);
  elsif p_game='baseball_class' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'room_code',room_code,'status',status,'created_at',created_at) order by created_at desc) from public.baseballclass_rooms where teacher_id=auth.uid()),'[]'::jsonb);
  else return coalesce((select jsonb_agg(jsonb_build_object('id',id,'room_code',room_code,'status',status,'created_at',created_at) order by created_at desc) from public.arithmetic_rooms where teacher_id=auth.uid()),'[]'::jsonb); end if;
 end if;
 if p_room is null then raise exception '방을 선택하세요.'; end if;
 if p_game='baseball1v1' then select * into r from public.baseball1v1_rooms where id=p_room and teacher_id=auth.uid() for update;
 elsif p_game='baseball_class' then select * into r from public.baseballclass_rooms where id=p_room and teacher_id=auth.uid() for update;
 else select * into r from public.arithmetic_rooms where id=p_room and teacher_id=auth.uid() for update; end if;
 if not found then raise exception '방을 찾을 수 없습니다.'; end if;
 if p_action='delete' then
  if p_game='baseball1v1' then delete from public.baseball1v1_rooms where id=p_room; elsif p_game='baseball_class' then delete from public.baseballclass_rooms where id=p_room; else delete from public.arithmetic_rooms where id=p_room; end if;
  delete from public.gamehub_sessions where room_id=p_room and game_key=p_game; return '{"deleted":true}'::jsonb;
 elsif p_action='start' then
  if r.status<>'WAITING' then raise exception '시작 대기 중인 방이 아닙니다.'; end if;
  if p_game='baseball1v1' then raise exception '두 학생이 입장한 뒤 각자 비밀 숫자를 입력하면 시작됩니다.';
  elsif p_game='baseball_class' then
   if not exists(select 1 from public.baseballclass_players where room_id=p_room) then raise exception '학생이 참가한 뒤 시작하세요.'; end if;
   update public.baseballclass_rooms set status='PLAYING',started_at=now() where id=p_room;
   update public.baseballclass_players set status='PLAYING' where room_id=p_room;
  else
   if not exists(select 1 from public.arithmetic_players where room_id=p_room) then raise exception '학생이 참가한 뒤 시작하세요.'; end if;
   update public.arithmetic_rooms set status='PLAYING',started_at=now() where id=p_room;
   for r in select * from public.arithmetic_players where room_id=p_room loop
    update public.arithmetic_players set status='PLAYING',started_at=now(),current_question=public.arithmetic_make_question((select selected_operations from public.arithmetic_rooms where id=p_room),(select digit_settings from public.arithmetic_rooms where id=p_room),1) where id=r.id;
   end loop;
  end if;
 elsif p_action='end' then
  if p_game='baseball1v1' then update public.baseball1v1_rooms set status='ENDED',ended_at=now(),result_text='교사가 게임을 종료했습니다.' where id=p_room;
  elsif p_game='baseball_class' then update public.baseballclass_rooms set status='ENDED',ended_at=now() where id=p_room;
  else update public.arithmetic_rooms set status='ENDED',ended_at=now() where id=p_room; update public.arithmetic_players set status=case when status='PLAYING' then 'FAILED' else status end,ended_at=coalesce(ended_at,now()) where room_id=p_room; end if;
 elsif p_action<>'state' then raise exception '지원하지 않는 작업입니다.'; end if;
 if p_game='baseball1v1' then
  select * into r from public.baseball1v1_rooms where id=p_room;
  return jsonb_build_object('room',jsonb_build_object('id',r.id,'room_code',r.room_code,'status',r.status,'digit_length',r.digit_length,'allow_zero',r.allow_zero,'max_rounds',r.max_rounds,'current_round',r.current_round,'result_text',r.result_text),
   'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'nickname',p.nickname,'has_secret',p.secret_number is not null,'is_active',p.is_active) order by p.joined_at) from public.baseball1v1_players p where p.room_id=p_room),'[]'::jsonb),
   'guesses',coalesce((select jsonb_agg(jsonb_build_object('round',g.round_number,'nickname',p.nickname,'guess',g.guess_number,'strikes',g.strikes,'balls',g.balls) order by g.round_number,p.joined_at) from public.baseball1v1_guesses g join public.baseball1v1_players p on p.id=g.player_id where g.room_id=p_room and (r.status='ENDED' or exists(select 1 from public.baseball1v1_guesses o where o.room_id=p_room and o.round_number=g.round_number and o.player_id<>g.player_id))),'[]'::jsonb));
 elsif p_game='baseball_class' then
  select * into r from public.baseballclass_rooms where id=p_room;
  return jsonb_build_object('room',jsonb_build_object('id',r.id,'room_code',r.room_code,'status',r.status,'digit_length',r.digit_length,'allow_zero',r.allow_zero,'max_rounds',r.max_rounds,'answer_number',r.answer_number),
   'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'student_id',p.student_id,'nickname',p.nickname,'status',p.status,'attempts',(select count(*) from public.baseballclass_guesses g where g.player_id=p.id),'last_guess',(select guess_number from public.baseballclass_guesses g where g.player_id=p.id order by attempt_number desc limit 1),'last_result',(select jsonb_build_object('strikes',strikes,'balls',balls,'is_out',is_out,'is_home_run',is_home_run) from public.baseballclass_guesses g where g.player_id=p.id order by attempt_number desc limit 1)) order by p.joined_at) from public.baseballclass_players p where p.room_id=p_room),'[]'::jsonb));
 else
  select * into r from public.arithmetic_rooms where id=p_room;
  return jsonb_build_object('room',jsonb_build_object('id',r.id,'room_code',r.room_code,'status',r.status,'selected_operations',r.selected_operations,'digit_settings',r.digit_settings,'total_questions',r.total_questions,'wrong_answer_mode',r.wrong_answer_mode),
   'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'student_id',p.student_id,'nickname',p.nickname,'status',p.status,'correct_count',p.correct_count,'wrong_count',p.wrong_count,'score',p.score,'level',p.level,'question_number',p.question_number,'elapsed_seconds',p.elapsed_seconds) order by p.correct_count desc,p.score desc,p.elapsed_seconds) from public.arithmetic_players p where p.room_id=p_room),'[]'::jsonb));
 end if;
end$$;

create or replace function public.gamehub_student_game_command(p_game text,p_action text,p_token text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.gamehub_sessions; r record; me record; opp record; g record; attempt_no int; strikes int; balls int; i int; guess text; ans text; round_no int; rows_count int; home_count int; winner uuid; good boolean; penalty int; elapsed int; answer_num int; correct_num int; begin
 if p_game not in ('baseball1v1','baseball_class','arithmetic') then raise exception '지원하지 않는 게임입니다.'; end if;
 select * into sess from public.gamehub_sessions where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and game_key=p_game and expires_at>now();
 if not found then raise exception 'SESSION_EXPIRED'; end if;
 if p_game='baseball1v1' then
  select * into r from public.baseball1v1_rooms where id=sess.room_id for update; select * into me from public.baseball1v1_players where room_id=r.id and student_id=sess.student_id for update;
  if not found or not me.is_active then raise exception 'SESSION_EXPIRED'; end if;
  select * into opp from public.baseball1v1_players where room_id=r.id and id<>me.id and is_active limit 1;
  if p_action='leave' then update public.baseball1v1_players set is_active=false where id=me.id; delete from public.gamehub_sessions where token_hash=sess.token_hash;
  elsif p_action='set_secret' then
   guess:=coalesce(p_data->>'number','');
   if r.status not in ('SETTING_SECRET','WAITING') or not opp.id is not null then raise exception '상대가 입장한 뒤 비밀 숫자를 입력할 수 있습니다.'; end if;
   if length(guess)<>r.digit_length or guess !~ '^[0-9]+$' or (not r.allow_zero and position('0' in guess)>0) or guess ~ '([0-9]).*\1' then raise exception '중복 없는 숫자와 자리수를 확인하세요.'; end if;
   update public.baseball1v1_players set secret_number=guess where id=me.id;
   if (select count(*) from public.baseball1v1_players where room_id=r.id and is_active and secret_number is not null)=2 then update public.baseball1v1_rooms set status='PLAYING' where id=r.id; end if;
  elsif p_action='guess' then
   if r.status<>'PLAYING' or opp.id is null or opp.secret_number is null then raise exception '게임이 아직 시작되지 않았습니다.'; end if;
   guess:=coalesce(p_data->>'number','');
   if length(guess)<>r.digit_length or guess !~ '^[0-9]+$' or (not r.allow_zero and position('0' in guess)>0) or guess ~ '([0-9]).*\1' then raise exception '중복 없는 숫자와 자리수를 확인하세요.'; end if;
   if exists(select 1 from public.baseball1v1_guesses where player_id=me.id and round_number=r.current_round) then raise exception '이번 라운드는 이미 제출했습니다.'; end if;
   ans:=opp.secret_number; strikes:=0; balls:=0;
   for i in 1..r.digit_length loop if substr(guess,i,1)=substr(ans,i,1) then strikes:=strikes+1; elsif position(substr(guess,i,1) in ans)>0 then balls:=balls+1; end if; end loop;
   insert into public.baseball1v1_guesses(room_id,player_id,target_player_id,round_number,guess_number,strikes,balls,is_home_run) values(r.id,me.id,opp.id,r.current_round,guess,strikes,balls,strikes=r.digit_length);
   select count(*),count(*) filter(where is_home_run) into rows_count,home_count from public.baseball1v1_guesses where room_id=r.id and round_number=r.current_round;
   if rows_count=2 then
    if home_count=2 then update public.baseball1v1_rooms set status='ENDED',ended_at=now(),result_text='같은 라운드에 두 플레이어가 홈런을 기록했습니다. 무승부입니다.' where id=r.id;
    elsif home_count=1 then select player_id into winner from public.baseball1v1_guesses where room_id=r.id and round_number=r.current_round and is_home_run; update public.baseball1v1_rooms set status='ENDED',ended_at=now(),winner_player_id=winner,result_text='홈런을 기록한 플레이어가 승리했습니다.' where id=r.id;
    elsif r.current_round>=r.max_rounds then update public.baseball1v1_rooms set status='ENDED',ended_at=now(),result_text='최대 라운드가 끝났습니다. 무승부입니다.' where id=r.id;
    else update public.baseball1v1_rooms set current_round=current_round+1 where id=r.id; end if;
   end if;
  elsif p_action<>'state' then raise exception '지원하지 않는 작업입니다.'; end if;
  select * into r from public.baseball1v1_rooms where id=sess.room_id; select * into me from public.baseball1v1_players where id=me.id;
  select * into opp from public.baseball1v1_players where room_id=r.id and id<>me.id and is_active limit 1;
  return jsonb_build_object('room',jsonb_build_object('room_code',r.room_code,'status',r.status,'digit_length',r.digit_length,'allow_zero',r.allow_zero,'max_rounds',r.max_rounds,'current_round',r.current_round,'result_text',r.result_text),
   'me',jsonb_build_object('id',me.id,'nickname',me.nickname,'has_secret',me.secret_number is not null,'secret_number',case when r.status='ENDED' then me.secret_number else null end),
   'opponent',case when opp.id is null then null else jsonb_build_object('id',opp.id,'nickname',opp.nickname,'has_secret',opp.secret_number is not null,'secret_number',case when r.status='ENDED' then opp.secret_number else null end) end,
   'my_submitted',exists(select 1 from public.baseball1v1_guesses where player_id=me.id and round_number=r.current_round),
   'opponent_submitted',exists(select 1 from public.baseball1v1_guesses where player_id=opp.id and round_number=r.current_round),
   'records',coalesce((select jsonb_agg(jsonb_build_object('round',g.round_number,'my_guess',g.guess_number,'my_result',g.strikes||'S '||g.balls||'B','opponent_guess',o.guess_number,'opponent_result',o.strikes||'S '||o.balls||'B') order by g.round_number) from public.baseball1v1_guesses g join public.baseball1v1_guesses o on o.room_id=g.room_id and o.round_number=g.round_number and o.player_id<>g.player_id where g.room_id=r.id and g.player_id=me.id and (r.status='ENDED' or g.round_number<r.current_round)),'[]'::jsonb));
 elsif p_game='baseball_class' then
  select * into r from public.baseballclass_rooms where id=sess.room_id for update; select * into me from public.baseballclass_players where room_id=r.id and student_id=sess.student_id for update;
  if not found then raise exception 'SESSION_EXPIRED'; end if;
  if p_action='leave' then update public.baseballclass_players set status='LEFT',ended_at=now() where id=me.id; delete from public.gamehub_sessions where token_hash=sess.token_hash;
  elsif p_action='guess' then
   if r.status<>'PLAYING' or me.status<>'PLAYING' then raise exception '게임이 진행 중이 아닙니다.'; end if;
   guess:=coalesce(p_data->>'number',''); if length(guess)<>r.digit_length or guess !~ '^[0-9]+$' or (not r.allow_zero and position('0' in guess)>0) or guess ~ '([0-9]).*\1' then raise exception '중복 없는 숫자와 자리수를 확인하세요.'; end if;
   select count(*)+1 into attempt_no from public.baseballclass_guesses where player_id=me.id; if attempt_no>r.max_rounds then raise exception '추측 횟수를 모두 사용했습니다.'; end if;
   strikes:=0; balls:=0; for i in 1..r.digit_length loop if substr(guess,i,1)=substr(r.answer_number,i,1) then strikes:=strikes+1; elsif position(substr(guess,i,1) in r.answer_number)>0 then balls:=balls+1; end if; end loop;
   insert into public.baseballclass_guesses(room_id,player_id,attempt_number,guess_number,strikes,balls,is_out,is_home_run) values(r.id,me.id,attempt_no,guess,strikes,balls,strikes=0 and balls=0,strikes=r.digit_length);
   if strikes=r.digit_length then update public.baseballclass_players set status='SUCCESS',ended_at=now() where id=me.id; elsif attempt_no>=r.max_rounds then update public.baseballclass_players set status='FAILED',ended_at=now() where id=me.id; end if;
  elsif p_action<>'state' then raise exception '지원하지 않는 작업입니다.'; end if;
  select * into r from public.baseballclass_rooms where id=sess.room_id; select * into me from public.baseballclass_players where id=me.id;
  return jsonb_build_object('room',jsonb_build_object('room_code',r.room_code,'status',r.status,'digit_length',r.digit_length,'allow_zero',r.allow_zero,'max_rounds',r.max_rounds,'answer_number',case when r.status='ENDED' or me.status in ('SUCCESS','FAILED') then r.answer_number else null end),
   'me',jsonb_build_object('id',me.id,'nickname',me.nickname,'status',me.status,'attempts',coalesce((select jsonb_agg(jsonb_build_object('attempt',g.attempt_number,'guess',g.guess_number,'strikes',g.strikes,'balls',g.balls,'is_out',g.is_out,'is_home_run',g.is_home_run) order by g.attempt_number) from public.baseballclass_guesses g where g.player_id=me.id),'[]'::jsonb)));
 else
  select * into r from public.arithmetic_rooms where id=sess.room_id for update; select * into me from public.arithmetic_players where room_id=r.id and student_id=sess.student_id for update;
  if not found then raise exception 'SESSION_EXPIRED'; end if;
  if me.status='PLAYING' and now()>=me.started_at+interval '1 hour' then update public.arithmetic_players set status='FAILED',ended_at=now(),elapsed_seconds=3600,updated_at=now() where id=me.id returning * into me; end if;
  if p_action='leave' then update public.arithmetic_players set status='LEFT',ended_at=now() where id=me.id; delete from public.gamehub_sessions where token_hash=sess.token_hash;
  elsif p_action='answer' then
   if r.status<>'PLAYING' or me.status<>'PLAYING' or me.current_question is null then raise exception '게임이 진행 중이 아닙니다.'; end if;
   if coalesce(p_data->>'answer','') !~ '^-?[0-9]{1,8}$' then raise exception '정수를 입력하세요.'; end if;
   answer_num:=(p_data->>'answer')::int; correct_num:=(me.current_question->>'answer')::int; good:=answer_num=correct_num;
   elapsed:=greatest(0,floor(extract(epoch from(now()-me.started_at)))::int);
   if good then
    update public.arithmetic_players set correct_count=correct_count+1,score=score+10*level,question_number=question_number+1,
     level=least(20,(correct_count+1)/5+1),elapsed_seconds=elapsed,updated_at=now() where id=me.id returning * into me;
    if me.correct_count>=r.total_questions then update public.arithmetic_players set status='FINISHED',score=score+greatest(0,3600-elapsed),ended_at=now() where id=me.id returning * into me;
    else update public.arithmetic_players set current_question=public.arithmetic_make_question(r.selected_operations,r.digit_settings,me.level) where id=me.id returning * into me; end if;
   else
    penalty:=case when r.wrong_answer_mode='minus2' then 20*me.level when r.wrong_answer_mode='reset_zero' then me.score else 10*me.level end;
    if r.wrong_answer_mode='gameover' then update public.arithmetic_players set wrong_count=wrong_count+1,status='FAILED',ended_at=now(),elapsed_seconds=elapsed,updated_at=now() where id=me.id returning * into me;
    elsif r.wrong_answer_mode='reset_zero' then update public.arithmetic_players set wrong_count=wrong_count+1,correct_count=0,question_number=1,level=1,score=0,elapsed_seconds=elapsed,updated_at=now(),current_question=public.arithmetic_make_question(r.selected_operations,r.digit_settings,1) where id=me.id returning * into me;
    else update public.arithmetic_players set wrong_count=wrong_count+1,score=greatest(0,score-penalty),correct_count=case when r.wrong_answer_mode='minus1' then greatest(0,correct_count-1) when r.wrong_answer_mode='minus2' then greatest(0,correct_count-2) else correct_count end,
     question_number=least(r.total_questions,case when r.wrong_answer_mode='minus1' then greatest(0,correct_count-1) when r.wrong_answer_mode='minus2' then greatest(0,correct_count-2) else correct_count end+1),
     level=least(20,(case when r.wrong_answer_mode='minus1' then greatest(0,correct_count-1) when r.wrong_answer_mode='minus2' then greatest(0,correct_count-2) else correct_count end)/5+1),elapsed_seconds=elapsed,updated_at=now(),current_question=public.arithmetic_make_question(r.selected_operations,r.digit_settings,least(20,(case when r.wrong_answer_mode='minus1' then greatest(0,correct_count-1) when r.wrong_answer_mode='minus2' then greatest(0,correct_count-2) else correct_count end)/5+1)) where id=me.id returning * into me; end if;
   end if;
   return jsonb_build_object('correct',good,'correct_answer',correct_num,'score',me.score,'correct_count',me.correct_count,'wrong_count',me.wrong_count,'status',me.status);
  elsif p_action<>'state' then raise exception '지원하지 않는 작업입니다.'; end if;
  select * into r from public.arithmetic_rooms where id=sess.room_id; select * into me from public.arithmetic_players where id=me.id;
  return jsonb_build_object('room',jsonb_build_object('room_code',r.room_code,'status',r.status,'total_questions',r.total_questions,'wrong_answer_mode',r.wrong_answer_mode),
   'me',jsonb_build_object('nickname',me.nickname,'status',me.status,'correct_count',me.correct_count,'wrong_count',me.wrong_count,'score',me.score,'level',me.level,'question_number',me.question_number,'elapsed_seconds',greatest(me.elapsed_seconds,case when me.started_at is null then 0 else floor(extract(epoch from(now()-me.started_at)))::int end),'question',case when r.status='PLAYING' and me.status='PLAYING' then jsonb_build_object('text',me.current_question->>'text') else null end));
 end if;
end$$;

-- Extend the established common student API allowlist and raise Streams to a 100-player competition room.
create or replace function public.streams_join(p_code text,p_room_password text,p_number text,p_name text,p_password text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.streams_rooms; s public.gamehub_students; p public.streams_players; token text; begin
 if p_code is null or p_number is null or p_name is null or p_password is null or p_room_password is null
 or p_code !~ '^[A-Z0-9]{6,8}$' or p_number !~ '^[-_A-Za-z0-9]{1,24}$'
 or char_length(trim(p_name)) not between 1 and 40 or char_length(p_password)<4 or octet_length(p_password)>72 or octet_length(p_room_password)>72
 then raise exception '입력 형식을 확인하세요. 개인 비밀번호는 6자 이상입니다.'; end if;
 select * into r from public.streams_rooms where room_code=p_code for update;
 if not found or not public.gamehub_verify_password(p_room_password,r.password_hash) then raise exception '방 코드 또는 인증 정보를 확인하세요.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(r.teacher_id::text||':'||p_number,0));
 select * into s from public.gamehub_students where teacher_id=r.teacher_id and student_number=p_number for update;
 if found then if not public.gamehub_verify_password(p_password,s.password_hash) or s.student_name<>trim(p_name) then raise exception '학번·이름·개인 비밀번호를 확인하세요.'; end if;
 else insert into public.gamehub_students(teacher_id,student_number,student_name,password_hash) values(r.teacher_id,p_number,trim(p_name),public.gamehub_hash_password(p_password)) returning * into s; end if;
 select * into p from public.streams_players where room_id=r.id and student_id=s.id;
 if found then if not p.is_active then raise exception '교사가 참가를 종료한 학생입니다.'; end if;
 else
  if r.status<>'WAITING' then raise exception '시작된 방에는 새로 참가할 수 없습니다.'; end if;
  if (select count(*) from public.streams_players where room_id=r.id)>=100 then raise exception '한 방에는 100명까지 참가할 수 있습니다.'; end if;
  insert into public.streams_players(room_id,student_id,student_number,student_name) values(r.id,s.id,p_number,s.student_name);
 end if;
 update public.gamehub_students set last_seen_at=now() where id=s.id; token:=encode(extensions.gen_random_bytes(32),'hex');
 delete from public.gamehub_sessions where student_id=s.id and game_key='streams' and room_id=r.id;
 insert into public.gamehub_sessions(token_hash,student_id,game_key,room_id) values(encode(extensions.digest(token,'sha256'),'hex'),s.id,'streams',r.id);
 perform public.streams_notify(r.id);
 return jsonb_build_object('sessionToken',token,'roomCode',r.room_code,'gameKey','streams','expiresAt',now()+interval '12 hours');
end$$;

do $$ declare f record; begin
 for f in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and (proname like 'gamehub\_%' escape '\' or proname like 'streams\_%' escape '\' or proname like 'baseball1v1\_%' escape '\' or proname like 'baseballclass\_%' escape '\' or proname like 'arithmetic\_%' escape '\') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end$$;
grant execute on function public.gamehub_teacher_game_command(text,text,uuid,jsonb) to authenticated;
grant execute on function public.gamehub_is_teacher() to authenticated;
grant execute on function public.gamehub_before_user_created(jsonb) to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.streams_teacher_command(text,uuid,text,uuid),public.streams_create_room(text),public.streams_draw_card(uuid),public.streams_end_room(uuid),public.gamehub_delete_student(uuid) to authenticated;
commit;
