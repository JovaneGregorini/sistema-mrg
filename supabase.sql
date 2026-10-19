-- =====================================================================
-- Sistema MRG — estrutura do banco no Supabase
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em Run.
-- Pode ser executado mais de uma vez sem problema.
-- =====================================================================

-- ---------- Perfis de usuário ----------
create table if not exists public.perfis (
  id         uuid primary key references auth.users on delete cascade,
  nome       text,
  email      text,
  papel      text not null default 'equipe' check (papel in ('admin','equipe')),
  modulos    text[] not null default array['painel','crm','cadastros','propostas','os'],
  ativo      boolean not null default false,
  visto      date,
  criado_em  timestamptz not null default now()
);

-- O primeiro usuário a se cadastrar vira administrador e já entra ativo.
-- Os demais ficam aguardando aprovação de um administrador.
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare primeiro boolean;
begin
  select not exists (select 1 from public.perfis) into primeiro;
  insert into public.perfis (id, nome, email, papel, ativo)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data->>'nome',''), split_part(new.email,'@',1)),
          new.email,
          case when primeiro then 'admin' else 'equipe' end,
          primeiro);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.novo_usuario();

create or replace function public.is_ativo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and ativo);
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and ativo and papel = 'admin');
$$;

create or replace function public.marcar_visto() returns void
language sql security definer set search_path = public as $$
  update public.perfis set visto = current_date where id = auth.uid();
$$;

alter table public.perfis enable row level security;
drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (id = auth.uid() or public.is_ativo());
drop policy if exists perfis_admin on public.perfis;
create policy perfis_admin on public.perfis for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- Documentos do sistema ----------
-- Cada registro (cadastro, proposta, OS, lançamento...) é um documento JSON
-- identificado pela coleção e por um id.
create table if not exists public.docs (
  colecao        text not null,
  id             text not null,
  data           jsonb not null default '{}'::jsonb,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid default auth.uid(),
  primary key (colecao, id)
);

create or replace function public.docs_carimbo() returns trigger
language plpgsql as $$
begin new.atualizado_em := now(); new.atualizado_por := auth.uid(); return new; end $$;
drop trigger if exists trg_docs_carimbo on public.docs;
create trigger trg_docs_carimbo before update on public.docs
  for each row execute function public.docs_carimbo();

-- Coleções:
--   equipe e administradores:  cadastros, propostas, os, listas
--   só administradores:        lancamentos, pagamentos, log, config (config: todos leem)
alter table public.docs enable row level security;

drop policy if exists docs_ler on public.docs;
create policy docs_ler on public.docs for select to authenticated
  using (public.is_ativo() and (colecao not in ('lancamentos','pagamentos','log') or public.is_admin()));

drop policy if exists docs_criar on public.docs;
create policy docs_criar on public.docs for insert to authenticated
  with check (public.is_ativo() and (colecao in ('cadastros','propostas','os','listas') or public.is_admin()));

drop policy if exists docs_alterar on public.docs;
create policy docs_alterar on public.docs for update to authenticated
  using (public.is_ativo() and colecao <> 'log' and (colecao in ('cadastros','propostas','os','listas') or public.is_admin()))
  with check (public.is_ativo() and colecao <> 'log' and (colecao in ('cadastros','propostas','os','listas') or public.is_admin()));

drop policy if exists docs_apagar on public.docs;
create policy docs_apagar on public.docs for delete to authenticated
  using (public.is_admin() and colecao <> 'log');

-- Atualização parcial de um documento (junta os campos enviados).
create or replace function public.merge_doc(p_colecao text, p_id text, p_patch jsonb) returns void
language sql security invoker set search_path = public as $$
  update public.docs set data = data || p_patch where colecao = p_colecao and id = p_id;
$$;

-- Registro automático de toda alteração em dados de pagamento (feito pelo banco).
create or replace function public.log_pagamentos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.colecao = 'pagamentos' and (tg_op = 'INSERT' or old.data is distinct from new.data) then
    insert into public.docs (colecao, id, data, atualizado_por)
    values ('log', gen_random_uuid()::text,
            jsonb_build_object('em', now(), 'por', auth.uid(), 'cadastroId', new.id,
                               'antes', case when tg_op = 'UPDATE' then old.data else '{}'::jsonb end,
                               'depois', new.data),
            auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists trg_log_pag on public.docs;
create trigger trg_log_pag after insert or update on public.docs
  for each row execute function public.log_pagamentos();

-- Atualização em tempo real nas telas de todos
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.perfis;
exception when others then null; end $$;

-- ---------- Arquivos ----------
-- imagens: logomarcas (públicas, aparecem nos PDFs)
-- anexos:  briefings, áudios, documentos (privados, só usuários ativos)
insert into storage.buckets (id, name, public, file_size_limit)
values ('imagens','imagens', true, 5242880), ('anexos','anexos', false, 52428800)
on conflict (id) do nothing;

drop policy if exists mrg_imagens_ler on storage.objects;
create policy mrg_imagens_ler on storage.objects for select using (bucket_id = 'imagens');
drop policy if exists mrg_imagens_enviar on storage.objects;
create policy mrg_imagens_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'imagens' and public.is_ativo());
drop policy if exists mrg_anexos_ler on storage.objects;
create policy mrg_anexos_ler on storage.objects for select to authenticated
  using (bucket_id = 'anexos' and public.is_ativo());
drop policy if exists mrg_anexos_enviar on storage.objects;
create policy mrg_anexos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'anexos' and public.is_ativo());
drop policy if exists mrg_arquivos_apagar on storage.objects;
create policy mrg_arquivos_apagar on storage.objects for delete to authenticated
  using (bucket_id in ('imagens','anexos') and public.is_admin());
