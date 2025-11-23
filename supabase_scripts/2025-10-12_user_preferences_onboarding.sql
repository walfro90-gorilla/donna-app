-- User preferences to control one-time onboarding/welcome experiences
-- Safe to run multiple times: uses IF NOT EXISTS

create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  has_seen_onboarding boolean not null default false,
  email_verified_congrats_shown boolean not null default false,
  welcome_shown_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_preferences enable row level security;

-- Update trigger to keep updated_at fresh
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_user_prefs_updated_at on public.user_preferences;
create trigger trg_user_prefs_updated_at
before update on public.user_preferences
for each row execute function public.set_updated_at();

-- Policies: each user can manage only their row
drop policy if exists "user_prefs_select_own" on public.user_preferences;
create policy "user_prefs_select_own" on public.user_preferences
  for select using (auth.uid() = user_id);

drop policy if exists "user_prefs_insert_own" on public.user_preferences;
create policy "user_prefs_insert_own" on public.user_preferences
  for insert with check (auth.uid() = user_id);

drop policy if exists "user_prefs_update_own" on public.user_preferences;
create policy "user_prefs_update_own" on public.user_preferences
  for update using (auth.uid() = user_id);

-- Optional helper function to mark onboarding as seen
create or replace function public.mark_onboarding_seen()
returns void
language plpgsql
security definer
as $$
begin
  insert into public.user_preferences (user_id, has_seen_onboarding, welcome_shown_at)
  values (auth.uid(), true, now())
  on conflict (user_id)
  do update set has_seen_onboarding = true, welcome_shown_at = now(), updated_at = now();
end;
$$;
