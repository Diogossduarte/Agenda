-- =====================================================================
--  Agenda do consultorio - Dra. Gabriela Porcaro
--  Esquema do banco de dados (Supabase / PostgreSQL)
--  Cole TODO este conteudo no SQL Editor do Supabase e clique em "Run".
-- =====================================================================

-- ---- Perfis (mapeia cada usuario logado para um nome e um papel) ----
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  role text not null default 'secretaria'   -- 'medica' ou 'secretaria'
);

-- ---- Consultas / bloqueios de horario / horarios disponiveis ----
-- kind: 'appt' (consulta) | 'block' (horario bloqueado) | 'slot' (horario disponivel)
create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'appt',
  patient text default '',
  phone text default '',
  date text not null,            -- 'YYYY-MM-DD'
  start_time text not null,      -- 'HH:MM'
  end_time text not null,        -- 'HH:MM'
  type text,
  convenio text,
  status text,
  notes text default '',
  reason text default '',
  created_at timestamptz default now()
);
create index if not exists appointments_date_idx on public.appointments(date);

-- ---- Lista de espera ----
create table if not exists public.waitlist (
  id uuid primary key default gen_random_uuid(),
  name text not null default '',
  phone text default '',
  note text default '',
  priority text default 'media',
  period text default 'qualquer',
  created_at timestamptz default now()
);

-- ---- Dias inteiros bloqueados ----
create table if not exists public.blocked_dates (
  d text primary key             -- 'YYYY-MM-DD'
);

-- ---- Configuracoes (linha unica, id = 1) ----
create table if not exists public.settings (
  id int primary key default 1,
  start_hour int not null default 7,
  end_hour int not null default 21,
  duration int not null default 50,
  workdays int[] not null default '{0,1,2,3,4}',
  hide_weekend boolean not null default true,
  confirm_template text
);

insert into public.settings (id) values (1)
on conflict (id) do nothing;

-- ---- Chat da equipe ----
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_role text not null,     -- 'medica' ou 'secretaria'
  sender_name text default '',
  text text not null,
  created_at timestamptz default now()
);
create index if not exists messages_created_idx on public.messages(created_at);

-- =====================================================================
--  SEGURANCA (RLS) - so quem estiver logado acessa os dados
-- =====================================================================
alter table public.profiles       enable row level security;
alter table public.appointments   enable row level security;
alter table public.waitlist       enable row level security;
alter table public.blocked_dates  enable row level security;
alter table public.settings       enable row level security;
alter table public.messages       enable row level security;

-- Perfil: cada usuario le o proprio perfil
drop policy if exists "perfil proprio" on public.profiles;
create policy "perfil proprio" on public.profiles
  for select using (auth.uid() = id);

-- Demais tabelas: qualquer usuario autenticado pode ler e escrever
drop policy if exists "agenda auth" on public.appointments;
create policy "agenda auth" on public.appointments
  for all to authenticated using (true) with check (true);

drop policy if exists "espera auth" on public.waitlist;
create policy "espera auth" on public.waitlist
  for all to authenticated using (true) with check (true);

drop policy if exists "bloqueios auth" on public.blocked_dates;
create policy "bloqueios auth" on public.blocked_dates
  for all to authenticated using (true) with check (true);

drop policy if exists "config auth" on public.settings;
create policy "config auth" on public.settings
  for all to authenticated using (true) with check (true);

drop policy if exists "chat auth" on public.messages;
create policy "chat auth" on public.messages
  for all to authenticated using (true) with check (true);

-- =====================================================================
--  TEMPO REAL - as duas pessoas veem as mudancas na hora
--  (idempotente: so adiciona a tabela se ela ainda nao estiver na lista)
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['appointments','waitlist','blocked_dates','settings','messages']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- =====================================================================
--  DEPOIS de criar os dois usuarios em Authentication > Users,
--  volte aqui, troque os UUIDs abaixo e rode este bloco para
--  definir os nomes e papeis (medica / secretaria):
-- =====================================================================
-- insert into public.profiles (id, name, role) values
--   ('COLE-AQUI-O-UUID-DA-MEDICA',    'Dra. Gabriela', 'medica'),
--   ('COLE-AQUI-O-UUID-DA-SECRETARIA','Secretaria',    'secretaria')
-- on conflict (id) do update set name = excluded.name, role = excluded.role;
