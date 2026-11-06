-- SOMENTE LEITURA. Não faz parte das 20 migrações de instalação.
-- SQL Editor usa os privilégios do operador; a aplicação respeita RLS e grants.
select
 d.id as entrega_id, d.code as codigo_entrega, d.status,
 cliente.full_name as cliente, entregador.full_name as entregador,
 vc.name as categoria_solicitada, v.brand as marca_veiculo,
 v.model as modelo_veiculo, v.plate as placa_veiculo,
 d.vehicle_confirmed_at as veiculo_confirmado_em, d.scheduled_at as agendada_para,
 d.price as valor_frete, d.commission_amount as comissao_movee,
 case when d.commission_amount is not null then d.price-d.commission_amount else null end as parcela_entregador,
 coalesce((select jsonb_agg(jsonb_build_object(
   'descricao',i.description,'quantidade',i.quantity,'peso_unitario_kg',i.unit_weight_kg,
   'comprimento_cm',i.length_cm,'largura_cm',i.width_cm,'altura_cm',i.height_cm
 ) order by i.id) from public.delivery_items i where i.delivery_id=d.id),'[]'::jsonb) as mercadorias
from public.deliveries d
join public.profiles cliente on cliente.id=d.client_id
join public.vehicle_categories vc on vc.id=d.category_id
left join public.driver_profiles dp on dp.id=d.driver_id
left join public.profiles entregador on entregador.id=dp.id
left join public.vehicles v on v.id=d.vehicle_id
order by d.created_at desc;
