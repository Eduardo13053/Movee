# Atualização da administração e rendimentos mensais

## 1. Páginas da administração

A atualização acrescenta três páginas exclusivas de administradores autorizados:

- `admin-entregas.html`: acompanhamento das entregas, filtros, detalhes, histórico e ocorrências da operação.
- `admin-entregadores.html`: análise de cadastros de entregadores, documentos, decisões com justificativa e histórico.
- `admin-rendimentos.html`: gráfico mensal da receita de comissões da Movee, seleção de ano e tabela dos valores.

O painel `admin.html` permanece disponível. A análise de solicitações administrativas continua separada da página exclusiva de entregadores. Os links de navegação levam às novas áreas; esconder um botão não é a proteção de acesso: a API e o banco também verificam as permissões.

## 2. Regra de comissão definida

A divisão inicial é **30% para a Movee e 70% para o entregador**. Em um frete de R$ 10,00, a empresa registra R$ 3,00 de comissão e o entregador tem R$ 7,00 destinados a ele.

A comissão monetária é arredondada em centavos. A parcela do entregador corresponde ao valor do frete menos a comissão, de modo que a soma das parcelas seja exatamente igual ao frete.

O gráfico mostra a **receita das comissões**, não o lucro líquido da empresa. Não são descontados automaticamente custos operacionais, impostos, taxas do provedor ou outros gastos não registrados nesse modelo. O registro da divisão não executa, por si só, uma transferência bancária ao entregador.

## 3. Preservação do histórico

Cada nova entrega guarda o percentual de comissão e o valor calculado naquele momento. O pagamento confirmado guarda a mesma divisão vinculada à entrega. Alterar o percentual na administração afeta novas entregas; não recalcula contratos e receitas anteriores.

Uma entrega antiga sem percentual registrado não recebe uma comissão histórica inventada. Os pagamentos correspondentes aparecem no aviso de registros sem divisão conhecida. O valor bruto pode ser conhecido, mas as parcelas da empresa e do entregador permanecem desconhecidas até uma análise contábil autorizada.

Por isso, o indicador destinado aos entregadores também considera apenas pagamentos com divisão registrada. Não se calcula esse indicador subtraindo uma comissão conhecida do valor bruto de pagamentos cujo histórico esteja incompleto.

## 4. Como o gráfico mensal é calculado

O relatório `admin_monthly_revenue(p_year)` é executado no banco/adaptador autorizado e retorna os doze meses, inclusive meses sem movimentação. A interface não soma apenas as linhas de pagamentos carregadas na tela.

São considerados pagamentos reais com status confirmado. Pagamentos demonstrativos, pendentes, com falha ou estornados não compõem a receita de comissões mostrada. As demonstrações excluídas e os registros históricos sem comissão possuem identificação própria.

Os meses seguem a data de confirmação no fuso `America/Sao_Paulo`. Um pagamento próximo da meia-noite UTC pode pertencer ao mês anterior nesse fuso. A data de confirmação de pagamentos novos é preservada após a confirmação.

Pagamentos já confirmados antes desta atualização podem não possuir uma data de confirmação original. Nesses casos, a migração utiliza a data de atualização ou criação como aproximação e marca essa situação para que o relatório informe a limitação. Essa aproximação da data não autoriza supor uma comissão histórica ausente.

## 5. Análise de entregadores

A página de entregadores filtra solicitações de entregador e permite consultar pendências, documentos e decisões. A aprovação depende das regras já existentes: identidade, CNH válida, documentação do veículo e análise por administrador autorizado.

Aprovação, rejeição, solicitação de correções e suspensão exigem justificativa conforme o fluxo. As decisões são auditadas e notificadas dentro da aplicação. A página não concede privilégios por parâmetros enviados no navegador, e uma conta sem aprovação não pode aceitar entregas.

## 6. Atualização do Supabase

Se a instalação anterior ia até18, aplique **19 e20**, nessa ordem. Se já aplicou19, execute somente20 para a confirmação obrigatória. Não tente recriar as tabelas executando novamente01–18.

Para uma instalação nova, execute os scripts de produção **01–20**, em ordem, uma única vez. Os documentos com o banco escrito por extenso reproduzem esses arquivos; execute os arquivos individuais ou a versão consolidada, sem duplicar a execução.

A atualização acrescenta os campos financeiros, as regras de preservação e o relatório mensal restrito a administradores. Não cria usuários reais nem concede acesso administrativo a um e-mail automaticamente.

## 7. Atualização do MongoDB

A variante MongoDB utiliza os mesmos conceitos e a mesma API PHP: comissão registrada por entrega, confirmação e divisão no pagamento e relatório administrativo mensal. Siga `MONGODB.md` para executar o inicializador e aplicar os schemas/índices atualizados ao banco escolhido.

Registros anteriores que não possuem os novos campos continuam sendo tratados como históricos incompletos. Não execute os SQL de domínio no projeto Supabase usado exclusivamente como Auth/Storage dessa variante.

## 8. Verificação após a instalação

1. Entre como administrador e abra as três páginas novas.
2. Confira que uma conta cliente ou entregador não consegue consultar o relatório financeiro administrativo.
3. Crie uma entrega nova, com a comissão inicial de 30%, e confira a divisão de R$ 10,00 em R$ 3,00/R$ 7,00 usando dados de teste apropriados.
4. Confira que pagamento demonstrativo não cria receita real no gráfico.
5. Use pagamentos reais de sandbox devidamente confirmados para validar a integração com o provedor. O retorno do navegador sozinho não confirma pagamento.
6. Altere a comissão para novas entregas e confira que a divisão de uma entrega já criada não muda.
7. Confira a seleção de ano, os doze meses, os avisos de histórico e a experiência em celular.

Os resultados efetivamente executados no ambiente de desenvolvimento e as integrações externas não executadas ficam em `TESTES.md`. Este roteiro não afirma que credenciais, pagamentos ou cadastros remotos já foram configurados.

## 8. Nome da marca

A assinatura visual passou a usar **Movee**, com M maiúsculo, no cabeçalho e rodapé. O monograma e o ícone da aba também usam M maiúsculo. A mudança acompanha os arquivos de interface desta atualização.
