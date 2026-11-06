# Requisitos, configuração e critérios de aceite

Esta matriz descreve onde cada requisito é atendido e o que é necessário para validá-lo. **Código entregue** não significa que um serviço externo foi provisionado ou testado remotamente. As evidências efetivamente executadas e seus limites estão em `TESTES.md`.

| Requisito | Implementação / critério de aceite | Dependência ou limite |
|---|---|---|
| Revisão integral do ZIP | Inventário e análise dos 13 arquivos em `AUDITORIA-ORIGINAL.md`. | Auditoria original estática; nenhum banco externo original foi acessado. |
| Identidade Movee | Roxo, verde e branco; CSS comum, páginas com composições próprias, SVGs locais. | Avaliação visual e tamanhos efetivamente verificados em `TESTES.md`. |
| Solicitar e rastrear na inicial | Ações específicas e retorno à operação após login. | Rastreamento exige autorização sobre a entrega. |
| Pagamentos apenas no fluxo pertinente | Escolha de Pix/crédito/débito na página de pagamento. | Sem coleta de PAN/CVV. |
| Contas | Cliente, entregador e administrador; vendedor preservado como modalidade com operações de cliente. | Papel solicitado não concede privilégio. |
| CPF/CNPJ | CPF com dígitos verificadores; vendedor aceita CPF/CNPJ; demais tipos usam CPF. | O número validado matematicamente não prova identidade. |
| Dados pessoais e termos | Nome completo, telefone, nascimento, senha/confirmar, aceite; validação no servidor. | Dados pessoais precisam ser verdadeiros na instalação final. |
| Documento oficial | Upload privado autenticado na conclusão do cadastro. | Não é possível solicitar/aceitar operações protegidas com cadastro incompleto. |
| E-mail/SMS | Supabase Auth, código real e backend de verificação. | SMTP/provedor SMS e templates com `{{ .Token }}` precisam ser configurados. |
| Recuperação | Solicitação e validação de código de recuperação. | Envio depende de Auth; não há senha própria no banco de domínio. |
| Administrador inicial | CLI com credencial de serviço, conferência manual e auditoria. | Operador autorizado de infraestrutura; apenas quando não existe admin. |
| Aprovação de administrador | Identidade, justificativa, fila, decisão por admin e histórico. | E-mail da empresa recebe aviso; não concede acesso. |
| Entregador | CNH, categoria/validade, identidade, veículos e documentos. | Aprovação administrativa antes do aceite. |
| Estados de aprovação | Pendente, em análise, aprovado, rejeitado e suspenso. | Regras no banco e backend. |
| Vários veículos | Cadastro/gestão por entregador e categoria compatível. | Documento necessário e revisão conforme estado. |
| Três endereços | CRUD, principal, todos os campos e seleção na solicitação. | Limite também no banco com proteção concorrente. |
| Mercadorias | Vários itens, quantidade, peso e dimensões. | Valores positivos e limites por categoria. |
| Unidades de peso | mg, g, kg e t; armazenamento decimal normalizado. | Conferir arredondamento/precisão nos testes. |
| Categorias | 11 tipos de bicicleta a caminhão grande, imagens, capacidade, proteção e tarifas. | Tarifas iniciais fictícias e configuráveis. |
| Cotação | Peso/volume/distância/categoria/custos/combustível/proteção/extras/urgência/pico validados no servidor. | Rota Geoapify opcional; sem configuração, distância estimada identificada. |
| Pedágios | Estrutura de dados e valores validados conforme regra de cotação. | Não há consulta automática de pedágio por rota. |
| Criação de entrega | Etapas de mercadoria, rota, veículo, cotação, revisão, pagamento e confirmação. | Cadastro confirmado/documentado e backend configurado. |
| Preço protegido | Criado/calculado no backend/banco; navegador não define o preço final. | Estimativas de distância devem ser conferidas operacionalmente. |
| Aceite concorrente | Operação atômica e bloqueio/condição de exclusividade. | Somente um entregador pode ficar designado. |
| Veículo na coleta | Cliente confere modelo/placa; divergência abre chamado; atualização exige o mesmo veículo designado. | Veículo ativo em entrega não pode ser alterado ou desativado. |
| Rota real opcional | Geoapify no backend, cotação persistida vinculada a titular/categoria/endereços/validade. | Chave externa; administração pode ativar exigência de rota confiável. |
| Progresso da entrega | Transições validadas, histórico e notificações. | Não apresenta GPS fictício. |
| Rastreamento | Estado inicial com instruções, busca, resultado vazio e erro técnico distintos. | Apenas participantes autorizados; identificação do entregador limitada. |
| Previsão de chegada | Estimativa a partir dos dados disponíveis. | Não é SLA nem localização em tempo real. |
| Cliente | Entregas, endereços, pagamento, perfil, notificações, suporte e avaliação. | Dados reais aparecem após operações da conta. |
| Entregador | Disponíveis redigidas, seleção de veículo, aceite, status, histórico e valores. | Valores de entregas não equivalem a repasse bancário automático. |
| Administrador | Solicitações/documentos, usuários, entregas, pagamentos, tarifas, suporte, indicadores e auditoria. | Sem autoaprovação; decisões exigem motivo. |
| Confiabilidade/ocorrências | Indicadores de entregas concluídas/canceladas e entregas que merecem atenção. | Cálculos refletem os dados existentes, sem estatísticas fictícias. |
| Comprovante | Nome do recebedor, horário, confirmação e vínculo com entrega concluída. | Não implementa assinatura digital certificada. |
| Avaliação | Nota e comentário após conclusão, vinculados ao cliente/entregador. | Uma avaliação por entrega, conforme restrições. |
| Suporte | FAQ, abertura de chamado e acompanhamento administrativo. | Sem atendimento humano automatizado ou SLA prometido. |
| Notificações internas | Registros por usuário e marcação de leitura. | Não é push do sistema operacional. |
| E-mails da aplicação | Outbox e worker com provedor configurado. | Agendamento, chave e remetente autorizado. |
| Pagamento demonstrativo | Registro `is_demo` e aviso explícito. | Não movimenta dinheiro. |
| Mercado Pago real | Checkout hospedado, webhook validado e confirmação idempotente. | Token, segredo, HTTPS, cadastro do webhook e testes externos. |
| Banco novo | Migrações PostgreSQL/Supabase em ordem, RLS, funções, restrições e índices. | Não reutiliza tabelas do original. |
| Variante MongoDB | Mesmo contrato de frontend/PHP, persistência própria documentada. | Supabase Auth continua necessário; veja `MONGODB.md`. |
| Documentação | Instalação, DER/dicionário, permissões, auditoria e operação. | `DATABASE.md` e guia Mongo especificam diferenças entre variantes. |
| Segurança | Sessão HttpOnly, CSRF, escape, listas permitidas, RLS/isolamento, documentos privados e auditoria. | Segurança absoluta não é prometida; rever implantação e resultados de testes. |
| LGPD | Transparência, acesso restrito e rotina de retenção configurável. | Controlador deve definir base legal, prazos e atendimento aos titulares. |
| Responsividade e acessibilidade | Formulários/grades/menu/tabelas adaptáveis, foco e navegação por teclado. | Consulte dimensões e verificações executadas em `TESTES.md`. |

## Aceite após a configuração

Use duas contas cliente, duas contas entregador e uma administrativa. Uma conta não pode ler os dados particulares da outra; um entregador sem aprovação não aceita entrega; dois aceites concorrentes deixam apenas um vencedor. Tente inserir um quarto endereço, alterar papel, preço, status e identificadores pelo navegador. A operação deve falhar de maneira clara e não deixar registro parcial.

Teste confirmação/recuperação com o provedor real escolhido, upload de arquivo inválido e documento de outro usuário. Em pagamentos reais, valide notificações duplicadas, assinatura incorreta, valor diferente, moeda incorreta e retorno do navegador sem webhook. Em MongoDB, repita os testes de isolamento e concorrência, pois as políticas RLS do PostgreSQL não são usadas por essa variante.

Antes de apresentar como ambiente produtivo, complete os testes externos pendentes registrados em `TESTES.md` e revise as políticas de privacidade e operação com o responsável pelo projeto.

## Adição administrativa solicitada

As páginas `admin-entregas.html`, `admin-entregadores.html` e `admin-rendimentos.html` separam supervisão, análise de parceiros e receita mensal. O banco registra a divisão inicial 30% Movee/70% entregador por entrega. O relatório usa pagamentos reais confirmados e não mistura demonstrações com comissões. O script de atualização é `sql/19_admin_monthly_revenue.sql`, com equivalência na alternativa MongoDB. A marca visual agora usa M maiúsculo.
