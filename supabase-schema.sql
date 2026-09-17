-- In The Know production schema
create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('student', 'teacher')),
  full_name text not null default '',
  school_name text not null default '',
  school_code text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
create index if not exists calendar_events_due_idx on public.calendar_events(due_at) where reminder_sent_at is null;
create index if not exists class_members_student_idx on public.class_members(student_id);

alter table public.profiles enable row level security;
alter table public.schools enable row level security;
alter table public.classes enable row level security;
alter table public.class_members enable row level security;
alter table public.notifications enable row level security;
alter table public.calendar_events enable row level security;
alter table public.push_subscriptions enable row level security;

create policy "Users can read their profile" on public.profiles for select using (id = auth.uid());
create policy "Users can create their profile" on public.profiles for insert with check (id = auth.uid());
create policy "Users can update their profile" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy "School members can read their school" on public.schools for select using (
  owner_id = auth.uid() or exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.school_code = schools.code
  )
);
create policy "Teachers can create schools" on public.schools for insert with check (owner_id = auth.uid());
create policy "School owners can update schools" on public.schools for update using (owner_id = auth.uid());

create policy "Class members can read classes" on public.classes for select using (
  teacher_id = auth.uid() or exists (
    select 1 from public.class_members cm where cm.class_id = classes.id and cm.student_id = auth.uid()
  )
);
create policy "Teachers can create classes" on public.classes for insert with check (teacher_id = auth.uid());
create policy "Teachers can update classes" on public.classes for update using (teacher_id = auth.uid());
create policy "Teachers can delete classes" on public.classes for delete using (teacher_id = auth.uid());

create policy "Members can read membership" on public.class_members for select using (
  student_id = auth.uid() or exists (
    select 1 from public.classes c where c.id = class_members.class_id and c.teacher_id = auth.uid()
  )
);
create policy "Students can join classes" on public.class_members for insert with check (student_id = auth.uid());
create policy "Students can leave classes" on public.class_members for delete using (student_id = auth.uid());

create policy "Class members can read notifications" on public.notifications for select using (
  teacher_id = auth.uid() or exists (
    select 1 from public.class_members cm where cm.class_id = notifications.class_id and cm.student_id = auth.uid()
  )
);
create policy "Teachers can send notifications" on public.notifications for insert with check (
  teacher_id = auth.uid() and exists (
    select 1 from public.classes c where c.id = notifications.class_id and c.teacher_id = auth.uid()
  )
);

create policy "Class members can read calendar events" on public.calendar_events for select using (
  created_by = auth.uid() or exists (
    select 1 from public.class_members cm where cm.class_id = calendar_events.class_id and cm.student_id = auth.uid()
  )
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
  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'student'),
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

revoke all on function public.join_class_by_code(text) from public;
grant execute on function public.join_class_by_code(text) to authenticated;
