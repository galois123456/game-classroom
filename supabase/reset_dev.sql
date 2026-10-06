-- DEVELOPMENT ONLY: deletes all gamehub_/streams_ data and teacher allowlist.
-- Not a migration. Back up first. Intentionally disabled unless the next line is uncommented.
-- set gamehub.allow_reset = 'YES';
begin;
do $$ begin
 if current_setting('gamehub.allow_reset',true) is distinct from 'YES' then
 raise exception '초기화가 차단되었습니다. 운영 데이터에는 실행하지 마세요. 개발 초기화가 필요하면 파일의 set 행 주석을 해제하세요.';
 end if;
end$$;
drop table if exists public.streams_room_events,public.gamehub_sessions,public.gamehub_rate_limits,
public.streams_players,public.streams_rooms,public.gamehub_results,public.gamehub_games,
public.gamehub_students,public.gamehub_teachers,public.gamehub_teacher_allowlist cascade;
do $$ declare f record; begin
 for f in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace
 and (proname like 'gamehub\_%' escape '\' or proname like 'streams\_%' escape '\') loop
 execute format('drop function %s cascade',f.signature);
 end loop;
end$$;
commit;
-- Re-run schema.sql, register allowlist emails, then configure the Auth Hook again.
