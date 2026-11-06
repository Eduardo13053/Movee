# Integração da versão final

A aplicação usa os mesmos nomes de tabelas e RPCs fornecidos no banco. Supabase Auth é a fonte de verdade de senha e confirmação; a API PHP usa a sessão segura para consultar o banco operacional escolhido.

| Área do site | Persistência e operação |
|---|---|
| Cadastro | Supabase Auth; trigger de perfil e entregador no PostgreSQL. |
| Confirmação de e-mail | Token hash ou código verificado no Auth; `email_confirmed_at` canônico libera a conta. Nenhum campo editável em metadata confirma a pessoa. |
| Login, sessão e renovação | Backend consulta o usuário canônico no Auth antes de aceitar acesso. O SQL 20 reforça RLS e operações protegidas. |
| Dados pessoais | `profiles` e `complete_profile`; tipo efetivo e CPF/CNPJ não são promovidos pelo formulário. |
| CNH e documentos | `driver_profiles`, `save_driver`, `documents` e Storage privado, acessados pelo backend autorizado. |
| Endereços | `addresses`, limite de três e endereço principal com controle de concorrência. |
| Veículos | `vehicles`, `vehicle_categories` e documentação; vários veículos por entregador. |
| Cotação | `quote_delivery`, categorias e `system_settings`; peso decimal, volume, combustível, pico e adicionais. |
| Distância automática | Geoapify no servidor, `route_quotes`, `store_route_quote` exclusivo de serviço e token assinado. |
| Nova entrega | `create_delivery`, `deliveries`, `delivery_items`, `delivery_events`, `notifications` e snapshot de comissão. |
| Aceite e execução | `available_deliveries`, `accept_delivery`, `assigned_vehicle`, `confirm_pickup_vehicle`, `advance_delivery`; veículo exato e aceite único. |
| Rastreamento | `track_delivery` com autorização e histórico, sem inventar GPS. |
| Pagamento | `payments`, confirmação demonstrativa marcada ou checkout/webhook real; data e comissão preservadas. |
| Entrega concluída | `delivery_proofs`, recebedor e histórico; `reviews` vincula a avaliação à entrega concluída. |
| Análise administrativa | `approval_requests`, `approval_history`, `review_document`, `review_account` e auditoria. |
| Rendimentos da empresa | `admin_monthly_revenue`, doze meses no fuso São Paulo, comissão real confirmada, sem misturar demonstrações. |
| Tarifas e comissão | `update_tariff`, `get_pricing_settings`, `update_pricing_settings`; alterações auditadas e sem recalcular entregas anteriores. |
| Suporte e avisos | `support_tickets`, `notifications`, `outbox`, worker de e-mails e `audit_logs`. |

A consulta de rendimentos é agregada no banco, sem depender da paginação da interface.

A instalação final PostgreSQL foi executada em uma base local nova com os 20 scripts e as seis suítes SQL. Também foram conferidos os nomes utilizados pela API, sem tabelas ou RPCs ausentes. Essas verificações não substituem os testes externos do projeto Supabase/SMTP/provedores do usuário.
