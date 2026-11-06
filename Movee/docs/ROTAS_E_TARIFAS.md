# Distância, combustível, horário de pico e veículo utilizado

O frete é calculado no servidor com tarifas iniciais fictícias para o TCC. O formulário não define o preço final: a criação do pedido repete a cotação com os dados validados.

## Composição do frete

O cálculo inclui preço-base da categoria, quilômetros × tarifa por quilômetro, peso total × tarifa por kg, volume total × tarifa por m³, custo operacional, proteção opcional, serviços extras e pedágios quando habilitados. O combustível é uma parcela explícita:

`combustível = distância em km ÷ consumo em km/l da categoria × preço do litro`

Bicicleta tem consumo de combustível igual a zero e não recebe essa parcela. As demais categorias têm consumo inicial configurável: moto 35 km/l, carro compacto 12 km/l e veículos de maior porte com parâmetros próprios. O preço inicial do combustível é R$ 6,20/litro; não é uma consulta automática ao preço real de postos.

O subtotal recebe o multiplicador de urgência quando selecionado. Depois, aplica-se o adicional de pico quando o agendamento estiver em um intervalo configurado. O padrão é 20% em dias úteis, das 7h às 9h e das 17h às 20h, no fuso `America/Sao_Paulo`. O início do intervalo está incluído e o fim excluído. O resumo da cotação apresenta as parcelas e indica quando houve pico.

Administradores podem alterar preço do combustível, consumo por categoria, multiplicadores, dias/horários de pico, serviços extras e limite de distância. Alterações são auditadas. Um pedido criado conserva seu preço e detalhamento; a nova configuração afeta novas cotações.

## Modo sem provedor de rotas

Sem `GEOAPIFY_API_KEY`, a solicitação permite distância **estimada manualmente**, identificada como demonstração. O servidor calcula o preço com essa distância, mas não a apresenta como medição de mapa ou GPS. O padrão do banco é `route_required=false` para permitir esse modo de apresentação do TCC.

## Habilitar distância calculada por endereços

1. Crie uma conta no Geoapify e habilite as APIs de geocodificação e roteamento, com quota adequada.
2. Preencha `GEOAPIFY_API_KEY` no `.env` privado do servidor. A chave não é enviada ao navegador.
3. Execute todos os scripts SQL da versão entregue, incluindo a estrutura `route_quotes` e o RPC exclusivo de serviço `store_route_quote`.
4. Confirme que a chave privada do Supabase está configurada. Ela grava a evidência de rota, após a consulta real ao provedor.
5. No painel administrativo, ative **Exigir distância calculada automaticamente** (`route_required=true`). Essa etapa também impede chamadas diretas ao Supabase de criarem um pedido apenas com uma distância arbitrária.
6. Em uma instalação com política de rede restrita, permita HTTPS para `api.geoapify.com` no ambiente do servidor.
7. Teste endereços reais conhecidos e confira as distâncias retornadas antes de usar o modo operacional.

O navegador envia coleta, destino e categoria para a ação `route` da API PHP. O servidor geocodifica endereços no Brasil e solicita rota apropriada para bicicleta, direção ou caminhão. O resultado contém distância em km, duração estimada e validade de 30 minutos.

A evidência é gravada em `route_quotes` por uma função exclusiva de serviço. O servidor também assina um token HMAC com `APP_KEY`, que vincula usuário, categoria, distância, validade e hashes dos endereços. O token não inclui o texto dos endereços. Cotação e criação recusam token alterado, expirado, de outra conta/categoria ou incompatível com endereços modificados. Com `route_required=true`, o banco também exige o registro confiável e verifica titular, categoria, distância, validade e endereços.

Uma mudança de coleta, destino ou categoria exige recálculo. A rota é uma **estimativa do provedor**, não uma localização GPS ao vivo do entregador. Pedágios não são calculados automaticamente por essa integração; a configuração inicial exige valor zero. As condições de trânsito/rotas do provedor podem mudar.

A integração foi preparada em código. Sem chave configurada, as chamadas reais ao Geoapify não foram executadas; os testes locais verificam assinatura, expiração, vínculo de usuário/categoria e alteração de endereços sem simular uma medição real.

## Conferência do veículo contratado

O entregador aceita a entrega selecionando um veículo próprio, ativo, documentado e compatível com a categoria. A reserva é atômica. O pedido mantém o identificador desse veículo, cuja marca/modelo/placa são exibidos aos participantes autorizados.

Antes de registrar a coleta, o cliente precisa conferir se o veículo apresentado corresponde ao contratado. A confirmação é registrada com data e observação. Se houver divergência, o cliente pode registrá-la; isso gera ocorrência para análise. O sistema não afirma ter realizado uma verificação física automática.

Cada avanço de status informa o veículo utilizado. O backend exige o mesmo identificador reservado; não permite trocar para um veículo menor nem usar outro veículo da mesma categoria de forma silenciosa. O banco bloqueia o início da coleta sem a conferência do cliente e impede edição/desativação do veículo durante uma entrega ativa. Se o veículo precisar ser substituído por motivo operacional, os participantes devem abrir suporte e seguir uma nova análise; não há substituição automática ou promessa de reembolso.
