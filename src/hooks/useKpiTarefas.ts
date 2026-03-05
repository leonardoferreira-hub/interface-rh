import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

// ── Types ──

type TarefaStatus = 'todo' | 'doing' | 'validating' | 'done';

interface StatusLogRow {
  id: string;
  tarefa_id: string;
  status_novo: string;
  transicao_em: string;
}

interface TarefaRow {
  id: string;
  status: TarefaStatus;
}

export interface KpiTarefasResult {
  tempoMedioPorColuna: {
    todo: number;
    doing: number;
    validating: number;
  };

  leadTimeMedio: number;

  distribuicaoAtual: {
    todo: number;
    doing: number;
    validating: number;
    done: number;
  };

  totalTarefas: number;
  tarefasConcluidas: number;
}

// ── Hook ──

export function useKpiTarefas() {
  return useQuery({
    queryKey: ['kpi-tarefas-rh'],
    queryFn: async () => {
      // Fetch status logs ordered by tarefa_id, transicao_em
      const { data: logs, error: errLogs } = await supabase
        .from('tarefa_rh_status_log')
        .select('id, tarefa_id, status_novo, transicao_em')
        .order('tarefa_id', { ascending: true })
        .order('transicao_em', { ascending: true });
      if (errLogs) throw errLogs;

      // Fetch current tarefas for distribution
      const { data: tarefas, error: errTarefas } = await supabase
        .from('tarefas_rh')
        .select('id, status');
      if (errTarefas) throw errTarefas;

      return calcularKpis(
        (logs || []) as StatusLogRow[],
        (tarefas || []) as TarefaRow[],
      );
    },
    staleTime: 5 * 60 * 1000,
  });
}

// ── Calculation ──

function calcularKpis(logs: StatusLogRow[], tarefas: TarefaRow[]): KpiTarefasResult {
  // Group logs by tarefa_id
  const logsByTarefa = new Map<string, StatusLogRow[]>();
  for (const log of logs) {
    if (!logsByTarefa.has(log.tarefa_id)) {
      logsByTarefa.set(log.tarefa_id, []);
    }
    logsByTarefa.get(log.tarefa_id)!.push(log);
  }

  // Accumulators for time per column
  const columnHours: Record<string, number> = { todo: 0, doing: 0, validating: 0 };
  const columnCount: Record<string, number> = { todo: 0, doing: 0, validating: 0 };

  // Lead time accumulator
  const leadTimes: number[] = [];
  const now = new Date();

  for (const [, tarefaLogs] of logsByTarefa) {
    // Logs are already sorted by transicao_em ASC
    const trackedColumns = new Set<string>();

    for (let i = 0; i < tarefaLogs.length; i++) {
      const status = tarefaLogs[i].status_novo;
      const start = new Date(tarefaLogs[i].transicao_em);
      const end = i + 1 < tarefaLogs.length
        ? new Date(tarefaLogs[i + 1].transicao_em)
        : now;

      const durationHours = (end.getTime() - start.getTime()) / (1000 * 60 * 60);

      if (status in columnHours) {
        columnHours[status] += durationHours;
        trackedColumns.add(status);
      }
    }

    // Count this task for each column it entered
    for (const col of trackedColumns) {
      columnCount[col]++;
    }

    // Lead time: first log to 'done' entry
    const firstLog = tarefaLogs[0];
    const doneLog = tarefaLogs.find(l => l.status_novo === 'done');
    if (firstLog && doneLog) {
      const firstTime = new Date(firstLog.transicao_em);
      const doneTime = new Date(doneLog.transicao_em);
      const leadDays = (doneTime.getTime() - firstTime.getTime()) / (1000 * 60 * 60 * 24);
      leadTimes.push(leadDays);
    }
  }

  // Average time per column
  const tempoMedioPorColuna = {
    todo: columnCount.todo > 0 ? columnHours.todo / columnCount.todo : 0,
    doing: columnCount.doing > 0 ? columnHours.doing / columnCount.doing : 0,
    validating: columnCount.validating > 0 ? columnHours.validating / columnCount.validating : 0,
  };

  // Average lead time
  const leadTimeMedio = leadTimes.length > 0
    ? leadTimes.reduce((sum, v) => sum + v, 0) / leadTimes.length
    : 0;

  // Current distribution
  const distribuicaoAtual = { todo: 0, doing: 0, validating: 0, done: 0 };
  for (const tarefa of tarefas) {
    if (tarefa.status in distribuicaoAtual) {
      distribuicaoAtual[tarefa.status as keyof typeof distribuicaoAtual]++;
    }
  }

  return {
    tempoMedioPorColuna,
    leadTimeMedio,
    distribuicaoAtual,
    totalTarefas: tarefas.length,
    tarefasConcluidas: distribuicaoAtual.done,
  };
}
