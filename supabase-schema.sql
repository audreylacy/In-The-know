-- In The Know production schema
create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('student', 'teacher')),
  username text,
  full_name text not null default '',
  school_name text not null default '',
  school_code text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists username text;
create unique index if not exists profiles_username_lower_idx on public.profiles (lower(username)) where username is not null;

create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  code text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.class_members (
  class_id uuid not null references public.classes(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (class_id, student_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.school_notifications (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  due_at timestamptz not null,
  reminder_hours integer not null default 3 check (reminder_hours between 1 and 72),
  reminder_sent_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);

create index if not exists notifications_class_created_idx on public.notifications(class_id, created_at desc);
create index if not exists school_notifications_created_idx on public.school_notifications(school_id, created_at desc);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'school_notifications'
  ) then
    alter publication supabase_realtime add table public.school_notifications;
  end if;
end;
$$;

create index if not exists calendar_events_due_idx on public.calendar_events(due_at) where reminder_sent_at is null;
create index if not exists class_members_student_idx on public.class_members(student_id);

alter table public.profiles enable row level security;
alter table public.schools enable row level security;
alter table public.classes enable row level security;
alter table public.class_members enable row level security;
alter table public.notifications enable row level security;
alter table public.school_notifications enable row level security;
alter table public.calendar_events enable row level security;
alter table public.push_subscriptions enable row level security;

drop policy if exists "Users can read their profile" on public.profiles;
drop policy if exists "Users can create their profile" on public.profiles;
drop policy if exists "Users can update their profile" on public.profiles;
drop policy if exists "Teachers can read class member profiles" on public.profiles;
drop policy if exists "School members can read their school" on public.schools;
drop policy if exists "Teachers can create schools" on public.schools;
drop policy if exists "School owners can update schools" on public.schools;
drop policy if exists "Class members can read classes" on public.classes;
drop policy if exists "Teachers can create classes" on public.classes;
drop policy if exists "Teachers can update classes" on public.classes;
drop policy if exists "Teachers can delete classes" on public.classes;
drop policy if exists "Members can read membership" on public.class_members;
drop policy if exists "Students can join classes" on public.class_members;
drop policy if exists "Students can leave classes" on public.class_members;
drop policy if exists "Class members can read notifications" on public.notifications;
drop policy if exists "Teachers can send notifications" on public.notifications;
drop policy if exists "School members can read school notifications" on public.school_notifications;
drop policy if exists "School teachers can send school notifications" on public.school_notifications;
drop policy if exists "Class members can read calendar events" on public.calendar_events;
drop policy if exists "Teachers can create calendar events" on public.calendar_events;
drop policy if exists "Teachers can update calendar events" on public.calendar_events;
drop policy if exists "Teachers can delete calendar events" on public.calendar_events;
drop policy if exists "Users manage their push subscriptions" on public.push_subscriptions;

create or replace function public.is_class_member(target_class_id uuid, target_student_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.class_members
    where class_id = target_class_id and student_id = target_student_id
  );
$$;

create or replace function public.is_class_teacher(target_class_id uuid, target_teacher_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.classes
    where id = target_class_id and teacher_id = target_teacher_id
  );
$$;

revoke all on function public.is_class_member(uuid, uuid) from public;
revoke all on function public.is_class_teacher(uuid, uuid) from public;
grant execute on function public.is_class_member(uuid, uuid) to authenticated;
grant execute on function public.is_class_teacher(uuid, uuid) to authenticated;

create or replace function public.is_school_member(target_school_id uuid, target_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.schools s
    join public.profiles p on p.school_code = s.code
    where s.id = target_school_id and p.id = target_user_id
  );
$$;

revoke all on function public.is_school_member(uuid, uuid) from public;
grant execute on function public.is_school_member(uuid, uuid) to authenticated;

create or replace function public.resolve_login_email(login_username text)
returns text
language sql
security definer
set search_path = public
as $$
  select u.email
  from auth.users u
  join public.profiles p on p.id = u.id
  where lower(p.username) = lower(trim(login_username))
  limit 1;
$$;

revoke all on function public.resolve_login_email(text) from public;
grant execute on function public.resolve_login_email(text) to anon, authenticated;

create or replace function public.prevent_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata_role text;
begin
  if tg_op = 'UPDATE' and new.role is distinct from old.role then
    raise exception 'Account role cannot be changed';
  end if;
  if tg_op = 'INSERT' and auth.uid() is not null then
    select lower(raw_user_meta_data->>'role')
    into metadata_role
    from auth.users
    where id = auth.uid();
    if metadata_role in ('student', 'teacher') and new.role <> metadata_role then
      raise exception 'Profile role must match the account role';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_profile_role_change on public.profiles;
create trigger prevent_profile_role_change
before insert or update on public.profiles
for each row execute procedure public.prevent_profile_role_change();

create policy "Users can read their profile" on public.profiles for select using (id = auth.uid());
create policy "Users can create their profile" on public.profiles for insert with check (id = auth.uid());
create policy "Users can update their profile" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
create policy "Teachers can read class member profiles" on public.profiles for select using (
  id = auth.uid() or exists (
    select 1 from public.class_members cm
    where cm.student_id = profiles.id and public.is_class_teacher(cm.class_id, auth.uid())
  )
);

create policy "School members can read their school" on public.schools for select using (
  owner_id = auth.uid() or exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.school_code = schools.code
  )
);
create policy "Teachers can create schools" on public.schools for insert with check (owner_id = auth.uid());
create policy "School owners can update schools" on public.schools for update using (owner_id = auth.uid());

create policy "Class members can read classes" on public.classes for select using (
  teacher_id = auth.uid() or public.is_class_member(id, auth.uid())
);
create policy "Teachers can create classes" on public.classes for insert with check (teacher_id = auth.uid());
create policy "Teachers can update classes" on public.classes for update using (teacher_id = auth.uid());
create policy "Teachers can delete classes" on public.classes for delete using (teacher_id = auth.uid());

create policy "Members can read membership" on public.class_members for select using (
  student_id = auth.uid() or public.is_class_teacher(class_id, auth.uid())
);
create policy "Students can join classes" on public.class_members for insert with check (student_id = auth.uid());
create policy "Students can leave classes" on public.class_members for delete using (student_id = auth.uid());

create policy "Class members can read notifications" on public.notifications for select using (
  teacher_id = auth.uid() or public.is_class_member(class_id, auth.uid())
);
create policy "Teachers can send notifications" on public.notifications for insert with check (
  teacher_id = auth.uid() and exists (
    select 1 from public.classes c where c.id = notifications.class_id and c.teacher_id = auth.uid()
  )
);

create policy "School members can read school notifications" on public.school_notifications for select using (
  public.is_school_member(school_id, auth.uid())
);
create policy "School teachers can send school notifications" on public.school_notifications for insert with check (
  teacher_id = auth.uid()
  and exists (
    select 1 from public.profiles p
    join public.schools s on s.code = p.school_code
    where p.id = auth.uid() and p.role = 'teacher' and s.id = school_notifications.school_id
  )
);

create policy "Class members can read calendar events" on public.calendar_events for select using (
  created_by = auth.uid() or public.is_class_member(class_id, auth.uid())
);
create policy "Teachers can create calendar events" on public.calendar_events for insert with check (
  created_by = auth.uid() and exists (
    select 1 from public.classes c where c.id = calendar_events.class_id and c.teacher_id = auth.uid()
  )
);
create policy "Teachers can update calendar events" on public.calendar_events for update using (created_by = auth.uid());
create policy "Teachers can delete calendar events" on public.calendar_events for delete using (created_by = auth.uid());

create policy "Users manage their push subscriptions" on public.push_subscriptions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, role, username, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'student'),
    lower(nullif(trim(new.raw_user_meta_data->>'username'), '')),
    coalesce(new.raw_user_meta_data->>'full_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.join_class_by_code(join_code text)
returns public.classes
language plpgsql
security definer set search_path = public
as $$
declare
  matched_class public.classes;
begin
  select * into matched_class from public.classes where code = upper(trim(join_code));
  if matched_class.id is null then
    raise exception 'Class code not found';
  end if;
  insert into public.class_members (class_id, student_id)
  values (matched_class.id, auth.uid())
  on conflict do nothing;
  return matched_class;
end;
$$;

create or replace function public.join_school_by_code(join_code text)
returns public.schools
language plpgsql
security definer set search_path = public
as $$
declare
  matched_school public.schools;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to join a school';
  end if;

  select * into matched_school
  from public.schools
  where code = upper(trim(join_code));

  if matched_school.id is null then
    raise exception 'School code not found';
  end if;

  update public.profiles
  set school_code = matched_school.code,
      school_name = matched_school.name,
      updated_at = now()
  where id = auth.uid();

  if not found then
    raise exception 'Your account profile could not be found';
  end if;

  return matched_school;
end;
$$;

revoke all on function public.join_class_by_code(text) from public;
grant execute on function public.join_class_by_code(text) to authenticated;
revoke all on function public.join_school_by_code(text) from public;
grant execute on function public.join_school_by_code(text) to authenticated;
