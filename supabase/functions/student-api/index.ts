// Students have no Supabase Auth JWT. Authentication is checked inside every RPC.
import { createStudentHandler } from '../_shared/student-handler.ts';
Deno.serve(createStudentHandler({
  SUPABASE_URL:Deno.env.get('SUPABASE_URL'),
  SUPABASE_SERVICE_ROLE_KEY:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  ALLOWED_ORIGINS:Deno.env.get('ALLOWED_ORIGINS')
}));
