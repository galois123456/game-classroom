-- 수학 게임 교실 ver1.00
-- 새 Supabase 프로젝트의 SQL Editor에서 전체 실행하세요.
create extension if not exists pgcrypto;

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

alter table public.gamehub_teachers enable row level security;
alter table public.gamehub_students enable row level security;
alter table public.gamehub_games enable row level security;
alter table public.gamehub_results enable row level security;
alter table public.streams_rooms enable row level security;
alter table public.streams_players enable row level security;

create policy "teacher own profile" on public.gamehub_teachers for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "teacher own students" on public.gamehub_students for all to authenticated using(teacher_id=auth.uid()) with check(teacher_id=auth.uid());
create policy "read games" on public.gamehub_games for select using(true);
create policy "teacher own results" on public.gamehub_results for all to authenticated using(teacher_id=auth.uid()) with check(teacher_id=auth.uid());
create policy "teacher own streams rooms" on public.streams_rooms for all to authenticated using(teacher_id=auth.uid()) with check(teacher_id=auth.uid());
create policy "teacher streams players" on public.streams_players for select to authenticated using(exists(select 1 from public.streams_rooms r where r.id=room_id and r.teacher_id=auth.uid()));

create or replace function public.streams_create_room(p_password text)
returns public.streams_rooms language plpgsql security definer set search_path=public as $$
declare r public.streams_rooms; c text; d jsonb;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
 c:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 d:=(select jsonb_agg(v order by random()) from (
   select n::text v from generate_series(1,30)n
   union all select n::text from generate_series(11,19)n
   union all select '★'
 )x);
 insert into streams_rooms(teacher_id,room_code,password_hash,status,deck)
 values(auth.uid(),c,crypt(p_password,gen_salt('bf')),'PLAYING',d) returning * into r;
 return r;
end$$;

create or replace function public.streams_draw_card(p_room_id uuid)
returns public.streams_rooms language plpgsql security definer set search_path=public as $$
declare r public.streams_rooms; idx int; v text;
begin
 select * into r from streams_rooms where id=p_room_id and teacher_id=auth.uid() for update;
 if r.id is null then raise exception '방을 찾을 수 없습니다.'; end if;
 if r.current_turn>=20 then raise exception '20장을 모두 뽑았습니다.'; end if;
 idx:=r.current_turn; v:=r.deck->>idx;
 update streams_rooms set current_turn=current_turn+1,current_card=v,history=history||to_jsonb(v)
 where id=p_room_id returning * into r;
 update streams_players set has_placed=false where room_id=p_room_id;
 return r;
end$$;

create or replace function public.streams_end_room(p_room_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 update streams_rooms set status='ENDED',ended_at=now() where id=p_room_id and teacher_id=auth.uid();
end$$;

grant execute on function public.streams_create_room(text) to authenticated;
grant execute on function public.streams_draw_card(uuid) to authenticated;
grant execute on function public.streams_end_room(uuid) to authenticated;

alter publication supabase_realtime add table public.streams_rooms;
alter publication supabase_realtime add table public.streams_players;


create or replace function public.gamehub_hash_password(plain_text text)
returns text language sql security definer set search_path=public as $$ select crypt(plain_text,gen_salt('bf')); $$;
create or replace function public.gamehub_verify_password(plain_text text,password_hash text)
returns boolean language sql security definer set search_path=public as $$ select crypt(plain_text,password_hash)=password_hash; $$;
revoke all on function public.gamehub_hash_password(text) from public,anon,authenticated;
revoke all on function public.gamehub_verify_password(text,text) from public,anon,authenticated;
grant execute on function public.gamehub_hash_password(text) to service_role;
grant execute on function public.gamehub_verify_password(text,text) to service_role;
