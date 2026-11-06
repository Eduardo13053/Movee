-- Rodar DEPOIS de 01..18. Não modifica dados. Falha imediatamente em regressão.
begin;
do $$
begin
 if not public.valid_cpf('529.982.247-25') then raise exception 'CPF válido rejeitado'; end if;
 if public.valid_cpf('111.111.111-11') or public.valid_cpf('52998224724') then raise exception 'CPF inválido aceito'; end if;
 if not public.valid_cnpj('11.222.333/0001-81') then raise exception 'CNPJ válido rejeitado'; end if;
 if public.valid_cnpj('11.222.333/0001-82') then raise exception 'CNPJ inválido aceito'; end if;
 if not public.valid_cnpj('12.ABC.345/01DE-35') then raise exception 'CNPJ alfanumérico válido rejeitado'; end if;
 if public.weight_kg(1000000,'mg')<>1 or public.weight_kg(1000,'g')<>1 or public.weight_kg(1,'t')<>1000 or public.weight_kg(.000001,'kg')<>.000001 then raise exception 'Conversão de peso incorreta'; end if;
 if not public.valid_phone('(11) 99999-1234') or public.valid_phone('000') then raise exception 'Validação telefone incorreta'; end if;
 if public.valid_tax_id('invalid') then raise exception 'Identificação inválida aceita'; end if;
 raise notice 'PASS: CPF/CNPJ numérico/alfanumérico, telefone e conversões exatas.';
end $$;
rollback;
