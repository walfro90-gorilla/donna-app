-- Optional helper to refresh PostgREST schema cache after DDL changes
-- Run this if you still get 404/42883 after applying the migrations
NOTIFY pgrst, 'reload schema';
