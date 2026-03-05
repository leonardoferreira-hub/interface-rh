import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface UsuarioRH {
  id: string;
  nome_completo: string;
  email: string;
  role: string;
}

// Emails da equipe RH (além do admin logado)
const EQUIPE_RH_EMAILS = [
  'livia.coelho@grupotravessia.com',
  'camila.oliveira@grupotravessia.com',
];

export function useEquipeRH() {
  return useQuery({
    queryKey: ['equipe-rh'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      const currentEmail = user?.email || '';

      // Buscar membros da equipe RH + o admin logado
      const emails = [...EQUIPE_RH_EMAILS];
      if (currentEmail && !emails.includes(currentEmail)) {
        emails.push(currentEmail);
      }

      const { data, error } = await supabase
        .from('usuarios')
        .select('id, nome_completo, email, role')
        .eq('ativo', true)
        .in('email', emails)
        .order('nome_completo');

      if (error) throw error;
      return (data || []) as UsuarioRH[];
    },
    staleTime: 5 * 60 * 1000,
  });
}
