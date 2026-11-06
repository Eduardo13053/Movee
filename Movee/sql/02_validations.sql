begin;
create function public.valid_cpf(v text) returns boolean language plpgsql immutable set search_path=public,pg_temp as $$
declare d text:=regexp_replace(coalesce(v,''),'\D','','g'); s int; x int; i int;
begin
 if coalesce(v,'') !~ '^[0-9.[:space:]-]+$' or d !~ '^\d{11}$' or d=repeat(substr(d,1,1),11) then return false; end if;
 for x in 10..11 loop
  s:=0; for i in 1..x-1 loop s:=s+substr(d,i,1)::int*(x+1-i); end loop;
  s:=(s*10)%11; if s=10 then s:=0; end if;
  if s<>substr(d,x,1)::int then return false; end if;
 end loop; return true;
end $$;
create function public.valid_phone(v text) returns boolean language plpgsql immutable set search_path=public,pg_temp as $$
declare d text:=regexp_replace(coalesce(v,''),'\D','','g');
begin
 if coalesce(v,'') !~ '^[0-9+() .-]+$' then return false; end if;
 if length(d) in (12,13) and left(d,2)='55' then d:=substr(d,3); end if;
 if left(d,2)<>all(array['11','12','13','14','15','16','17','18','19','21','22','24','27','28','31','32','33','34','35','37','38','41','42','43','44','45','46','47','48','49','51','53','54','55','61','62','63','64','65','66','67','68','69','71','73','74','75','77','79','81','82','83','84','85','86','87','88','89','91','92','93','94','95','96','97','98','99']) then return false; end if;
 return (length(d)=10 and substr(d,3) ~ '^[2-5][0-9]{7}$') or (length(d)=11 and substr(d,3) ~ '^9[0-9]{8}$');
end $$;
create function public.valid_full_name(v text) returns boolean language sql immutable set search_path=public,pg_temp as $$ select length(trim(v)) between 4 and 140 and trim(v) ~ '^[[:alpha:]À-ÖØ-öø-ÿĀ-ſ][[:alpha:]À-ÖØ-öø-ÿĀ-ſ''’-]*( [[:alpha:]À-ÖØ-öø-ÿĀ-ſ][[:alpha:]À-ÖØ-öø-ÿĀ-ſ''’-]*)+$' $$;
create function public.weight_kg(p_weight numeric,p_unit text) returns numeric language plpgsql immutable set search_path=public,pg_temp as $$
begin
 if p_weight is null or p_weight<=0 or p_weight::text in ('NaN','Infinity','-Infinity') then raise exception 'Peso inválido.'; end if;
 case p_unit when 'mg' then return p_weight/1000000; when 'g' then return p_weight/1000; when 'kg' then return p_weight; when 't' then return p_weight*1000; else raise exception 'Unidade de peso inválida.'; end case;
end $$;
create function public.valid_address(v jsonb) returns boolean language sql immutable set search_path=public,pg_temp as $$
 select coalesce(jsonb_typeof(v)='object' and length(trim(coalesce(v->>'street',''))) between 2 and 200 and length(trim(coalesce(v->>'number',''))) between 1 and 30 and length(trim(coalesce(v->>'neighborhood',''))) between 2 and 100 and length(trim(coalesce(v->>'city',''))) between 2 and 100 and length(coalesce(v->>'complement',''))<=100 and length(coalesce(v->>'reference',''))<=250 and coalesce(v->>'state','') ~ '^(AC|AL|AP|AM|BA|CE|DF|ES|GO|MA|MT|MS|MG|PA|PB|PR|PE|PI|RJ|RN|RS|RO|RR|SC|SP|SE|TO)$' and coalesce(v->>'postal_code','') ~ '^[0-9]{5}-?[0-9]{3}$',false)
$$;
create function public.valid_cnpj(v text) returns boolean language plpgsql immutable set search_path=public,pg_temp as $$
declare d text:=upper(regexp_replace(coalesce(v,''),'[^A-Za-z0-9]','','g')); weights int[]:=array[6,5,4,3,2,9,8,7,6,5,4,3,2]; s int; x int; i int;
begin
 if coalesce(v,'') !~ '^[A-Za-z0-9./[:space:]-]+$' or d !~ '^[A-Z0-9]{12}[0-9]{2}$' or d=repeat(substr(d,1,1),14) then return false; end if;
 for x in 13..14 loop
  s:=0; for i in 1..x-1 loop s:=s+(ascii(substr(d,i,1))-48)*weights[i+14-x]; end loop;
  s:=s%11; if s<2 then s:=0; else s:=11-s; end if;
  if s<>substr(d,x,1)::int then return false; end if;
 end loop; return true;
end $$;
create function public.valid_tax_id(v text) returns boolean language sql immutable set search_path=public,pg_temp as $$ select public.valid_cpf(v) or public.valid_cnpj(v) $$;
commit;
