-- =============================================
-- SQL completo para Interface RH
-- Rodar no Supabase Dashboard > SQL Editor
-- Projeto: gthtvpujwukbfgokghne.supabase.co
-- =============================================

-- =============================================
-- 1. Tabela tarefas_rh (Kanban RH)
-- =============================================

CREATE TABLE public.tarefas_rh (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.usuarios(id),
  titulo TEXT NOT NULL,
  descricao TEXT,
  status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'doing', 'validating', 'done')),
  posicao INTEGER NOT NULL DEFAULT 0,
  prioridade TEXT NOT NULL DEFAULT 'media' CHECK (prioridade IN ('baixa', 'media', 'alta', 'urgente')),
  id_emissao TEXT,
  mencionados UUID[] NOT NULL DEFAULT '{}',
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tarefas_rh ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tarefas_rh_select" ON public.tarefas_rh
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "tarefas_rh_insert" ON public.tarefas_rh
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "tarefas_rh_update" ON public.tarefas_rh
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.usuarios
      WHERE usuarios.id = auth.uid()
      AND usuarios.role IN ('admin', 'coordenador_rh')
    )
  );

CREATE POLICY "tarefas_rh_delete" ON public.tarefas_rh
  FOR DELETE TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.usuarios
      WHERE usuarios.id = auth.uid()
      AND usuarios.role IN ('admin', 'coordenador_rh')
    )
  );

-- =============================================
-- 2. Tabela tarefa_rh_status_log (KPI trigger)
-- =============================================

CREATE TABLE public.tarefa_rh_status_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tarefa_id UUID NOT NULL REFERENCES public.tarefas_rh(id) ON DELETE CASCADE,
  status_anterior TEXT,
  status_novo TEXT NOT NULL,
  transicao_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id UUID REFERENCES public.usuarios(id)
);

CREATE INDEX idx_rh_status_log_tarefa ON public.tarefa_rh_status_log(tarefa_id, transicao_em);

ALTER TABLE public.tarefa_rh_status_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rh_log_select" ON public.tarefa_rh_status_log
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "rh_log_insert" ON public.tarefa_rh_status_log
  FOR INSERT TO authenticated WITH CHECK (true);

-- Trigger automático
CREATE OR REPLACE FUNCTION public.log_tarefa_rh_status()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.tarefa_rh_status_log (tarefa_id, status_anterior, status_novo, user_id)
    VALUES (NEW.id, NULL, NEW.status, NEW.user_id);
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.tarefa_rh_status_log (tarefa_id, status_anterior, status_novo, user_id)
    VALUES (NEW.id, OLD.status, NEW.status, NEW.user_id);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_tarefa_rh_status
  AFTER INSERT OR UPDATE ON public.tarefas_rh
  FOR EACH ROW
  EXECUTE FUNCTION public.log_tarefa_rh_status();

-- =============================================
-- 3. Tabela rotinas_rh (cadastro de rotinas)
-- =============================================

CREATE TABLE public.rotinas_rh (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome TEXT NOT NULL,
  descricao TEXT,
  dia_util_regra INTEGER NOT NULL DEFAULT 5,
  responsavel_id UUID REFERENCES public.usuarios(id),
  ativo BOOLEAN NOT NULL DEFAULT true,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.rotinas_rh ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rotinas_rh_select" ON public.rotinas_rh
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "rotinas_rh_insert" ON public.rotinas_rh
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.usuarios
      WHERE usuarios.id = auth.uid()
      AND usuarios.role IN ('admin', 'coordenador_rh')
    )
  );

CREATE POLICY "rotinas_rh_update" ON public.rotinas_rh
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.usuarios
      WHERE usuarios.id = auth.uid()
      AND usuarios.role IN ('admin', 'coordenador_rh')
    )
  );

CREATE POLICY "rotinas_rh_delete" ON public.rotinas_rh
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.usuarios
      WHERE usuarios.id = auth.uid()
      AND usuarios.role IN ('admin', 'coordenador_rh')
    )
  );

-- =============================================
-- 4. Tabela rotina_rh_cumprimentos (mensal)
-- =============================================

CREATE TABLE public.rotina_rh_cumprimentos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rotina_id UUID NOT NULL REFERENCES public.rotinas_rh(id) ON DELETE CASCADE,
  mes_referencia DATE NOT NULL,
  data_esperada DATE NOT NULL,
  data_cumprimento TIMESTAMPTZ,
  cumprida_por UUID REFERENCES public.usuarios(id),
  status TEXT NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'cumprida', 'atrasada')),
  observacao TEXT,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (rotina_id, mes_referencia)
);

ALTER TABLE public.rotina_rh_cumprimentos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rh_cumprimentos_select" ON public.rotina_rh_cumprimentos
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "rh_cumprimentos_insert" ON public.rotina_rh_cumprimentos
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "rh_cumprimentos_update" ON public.rotina_rh_cumprimentos
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.usuarios
      WHERE usuarios.id = auth.uid()
      AND (
        usuarios.role IN ('admin', 'coordenador_rh')
        OR usuarios.id = (
          SELECT responsavel_id FROM public.rotinas_rh WHERE rotinas_rh.id = rotina_rh_cumprimentos.rotina_id
        )
      )
    )
  );

-- =============================================
-- 5. Inserir usuárias RH (se não existirem)
-- =============================================

INSERT INTO public.usuarios (nome_completo, email, role, ativo)
SELECT 'Lívia Coelho', 'livia.coelho@grupotravessia.com', 'analista_rh', true
WHERE NOT EXISTS (SELECT 1 FROM public.usuarios WHERE email = 'livia.coelho@grupotravessia.com');

INSERT INTO public.usuarios (nome_completo, email, role, ativo)
SELECT 'Camila Oliveira', 'camila.oliveira@grupotravessia.com', 'coordenador_rh', true
WHERE NOT EXISTS (SELECT 1 FROM public.usuarios WHERE email = 'camila.oliveira@grupotravessia.com');

-- =============================================
-- 6. Inserir interface RH no portal
-- =============================================

INSERT INTO public.interfaces (slug, nome, descricao, url, icone, cor, ordem)
SELECT 'rh', 'Recursos Humanos', 'Rotinas, KPIs e pendências do RH', 'https://interface-rh.vercel.app', 'Users', '330 65% 28%', 5
WHERE NOT EXISTS (SELECT 1 FROM public.interfaces WHERE slug = 'rh');

-- =============================================
-- 7. Conceder acesso às usuárias no portal
-- =============================================

INSERT INTO public.usuario_interface_acesso (usuario_id, interface_id)
SELECT u.id, i.id
FROM public.usuarios u, public.interfaces i
WHERE u.email = 'livia.coelho@grupotravessia.com' AND i.slug = 'rh'
AND NOT EXISTS (
  SELECT 1 FROM public.usuario_interface_acesso a WHERE a.usuario_id = u.id AND a.interface_id = i.id
);

INSERT INTO public.usuario_interface_acesso (usuario_id, interface_id)
SELECT u.id, i.id
FROM public.usuarios u, public.interfaces i
WHERE u.email = 'camila.oliveira@grupotravessia.com' AND i.slug = 'rh'
AND NOT EXISTS (
  SELECT 1 FROM public.usuario_interface_acesso a WHERE a.usuario_id = u.id AND a.interface_id = i.id
);
