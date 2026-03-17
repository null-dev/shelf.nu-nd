-- Enable Row Level Security on the Prisma migrations tracking table.
-- This prevents the anon/authenticated roles from reading or writing to it
-- via the PostgREST API, without affecting Prisma's migration runner
-- (which connects as the postgres superuser, bypassing RLS).
ALTER TABLE public._prisma_migrations ENABLE ROW LEVEL SECURITY;
