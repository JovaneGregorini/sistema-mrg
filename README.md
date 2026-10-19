# Sistema MRG

CRM e gestão da MRG: cadastros de clientes e fornecedores, propostas, ordens de serviço, financeiro, análises do CRM e importação do GMPE.

- **Telas:** `index.html`, publicado pelo GitHub Pages.
- **Dados, login e arquivos:** Supabase.

## Instalação (uma vez)

1. No Supabase, abra **SQL Editor**, cole todo o conteúdo de `supabase.sql` e clique em **Run**.
2. Em **Authentication → URL Configuration**, coloque o endereço do GitHub Pages em **Site URL** e em **Redirect URLs**.
3. Em `index.html`, preencha `SUPA_URL` e `SUPA_KEY` (Project URL e chave anon/public). A chave anon pode ficar pública: quem protege os dados são as regras do banco.
4. No GitHub, ative **Settings → Pages → Deploy from a branch → main / (root)**.

## Acessos

- A **primeira pessoa** que criar conta vira administradora automaticamente.
- As demais criam conta na tela de login e ficam aguardando. Um administrador libera cada uma em **Configurações → Usuários e acessos**.
- **Administrador:** vê tudo.
- **Equipe:** vê só os módulos liberados e nunca o financeiro, os dados bancários ou o registro de alterações. Esse bloqueio é feito pelo banco de dados.

## Backup

No Supabase, em **Database → Backups**. Também dá para exportar as planilhas pelo próprio sistema, na tela **Importar**.
