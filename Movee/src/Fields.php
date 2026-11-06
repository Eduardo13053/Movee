<?php
declare(strict_types=1);
namespace Movee;
/** Shared request boundaries for both the PostgreSQL and MongoDB gateways. */
final class Fields {
    public static function number(mixed $v,float $min,float $max,string $label,bool $integer=false): int|float|string {
        if ((!is_int($v)&&!is_float($v)&&!is_string($v)) || (is_string($v)&&!preg_match('/^\d+(?:\.\d{1,9})?$/D',$v)) || !is_numeric($v) || !is_finite((float)$v) || (float)$v<$min || (float)$v>$max || ($integer&&(float)$v!==floor((float)$v))) throw new ApiException("$label deve ser ".($integer?'um número inteiro':'um número')." entre $min e $max.",422);
        return $integer?(int)$v:$v;
    }
    public static function choice(mixed $v,array $allowed,string $label): string { if(!is_string($v)||!in_array($v,$allowed,true))throw new ApiException("$label inválido.",422);return$v; }
    public static function bool(mixed $v,string $label): bool { if(!is_bool($v))throw new ApiException("$label deve ser verdadeiro ou falso.",422);return$v; }
    public static function keys(array $v,array $allowed,array $required=[]): void {
        if(array_diff(array_keys($v),$allowed))throw new ApiException('A operação contém campos desconhecidos ou protegidos.',422);
        if($missing=array_diff($required,array_keys($v)))throw new ApiException('Preencha os campos obrigatórios: '.implode(', ',$missing).'.',422);
    }
    public static function date(mixed $v,string $label,int $minDays=0,int $maxDays=3650): string {
        if(!is_string($v)||!preg_match('/^\d{4}-\d{2}-\d{2}$/D',$v))throw new ApiException("$label inválida.",422);
        $d=\DateTimeImmutable::createFromFormat('!Y-m-d',$v);$today=new \DateTimeImmutable('today');
        if(!$d||$d->format('Y-m-d')!==$v||$d<$today->modify("$minDays days")||$d>$today->modify("+$maxDays days"))throw new ApiException("$label fora do período permitido.",422);
        return$v;
    }
    public static function address(array $v,bool $partial=false): array {
        $allowed=['label','postal_code','street','number','complement','neighborhood','city','state','reference','is_default'];
        self::keys($v,$allowed,$partial?[]:['postal_code','street','number','neighborhood','city','state']);
        foreach(['label'=>[2,40,'Identificação'],'street'=>[2,200,'Rua'],'number'=>[1,30,'Número'],'complement'=>[0,100,'Complemento'],'neighborhood'=>[2,100,'Bairro'],'city'=>[2,100,'Cidade'],'reference'=>[0,250,'Referência']]as$key=>$rule)if(array_key_exists($key,$v))$v[$key]=Validation::text($v[$key],...$rule);
        if(array_key_exists('postal_code',$v)){
            if(!is_scalar($v['postal_code'])||!preg_match('/^\d{5}-?\d{3}$/D',(string)$v['postal_code']))throw new ApiException('CEP deve conter 8 números.',422);$v['postal_code']=Validation::digits($v['postal_code']);
        }
        if(array_key_exists('state',$v))$v['state']=self::choice(strtoupper((string)$v['state']),['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'],'Estado');
        if(array_key_exists('is_default',$v))$v['is_default']=self::bool($v['is_default'],'Endereço principal');
        return$v;
    }
    public static function items(mixed $items): array {
        if(!is_array($items)||!array_is_list($items)||count($items)<1||count($items)>30)throw new ApiException('Informe entre 1 e 30 mercadorias.',422);
        foreach($items as&$i){
            if(!is_array($i))throw new ApiException('Mercadoria inválida.',422);
            self::keys($i,['description','quantity','weight','unit','length_cm','width_cm','height_cm'],['description','quantity','weight','unit','length_cm','width_cm','height_cm']);
            $i['description']=Validation::text($i['description'],2,500,'Descrição da mercadoria');$i['quantity']=self::number($i['quantity'],1,10000,'Quantidade',true);$i['weight']=self::number($i['weight'],0.000001,14000000000,'Peso');
            $i['unit']=self::choice($i['unit'],['mg','g','kg','t'],'Unidade de peso');$factor=['mg'=>0.000001,'g'=>0.001,'kg'=>1,'t'=>1000][$i['unit']];$kg=(float)$i['weight']*$factor;
            if($kg<0.000001||$kg>14000)throw new ApiException('Peso unitário deve estar entre 1 mg e 14 toneladas.',422);
            foreach(['length_cm'=>'Comprimento','width_cm'=>'Largura','height_cm'=>'Altura']as$key=>$label)$i[$key]=self::number($i[$key],0.001,10000,$label);
        }unset($i);return$items;
    }
    public static function delivery(array $p): array {
        self::keys($p,['category_id','items','distance_km','pickup','destination','recipient_name','recipient_phone','scheduled_at','notes','special_instructions','urgent','protection','extras','tolls','route_token'],['category_id','items','distance_km','pickup','destination','recipient_name','recipient_phone','scheduled_at']);
        $p['category_id']=self::slug($p['category_id']);$p['items']=self::items($p['items']);$p['distance_km']=self::number($p['distance_km'],0.001,10000,'Distância');
        foreach(['pickup'=>'Coleta','destination'=>'Destino']as$key=>$label){if(!is_array($p[$key]))throw new ApiException("Endereço de $label inválido.",422);$p[$key]=self::address($p[$key]);}
        $p['recipient_name']=Validation::text($p['recipient_name'],3,160,'Nome do destinatário');$p['recipient_phone']=Validation::e164($p['recipient_phone']);
        if(!is_string($p['scheduled_at'])||strlen($p['scheduled_at'])>40||!preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})?$/D',$p['scheduled_at']))throw new ApiException('Data e horário de agendamento inválidos.',422);
        try{$schedule=new \DateTimeImmutable($p['scheduled_at']);}catch(\Throwable $e){throw new ApiException('Data de agendamento inválida.',422);}
        $dateErrors=\DateTimeImmutable::getLastErrors();if(is_array($dateErrors)&&($dateErrors['warning_count']>0||$dateErrors['error_count']>0))throw new ApiException('Data de agendamento inválida.',422);
        if($schedule->getTimestamp()<time()-300||$schedule->getTimestamp()>time()+366*86400)throw new ApiException('Agende a entrega de agora até um ano.',422);
        foreach(['notes'=>'Observações','special_instructions'=>'Instruções especiais']as$key=>$label)$p[$key]=Validation::text($p[$key]??'',0,2000,$label);
        foreach(['urgent','protection']as$key)$p[$key]=self::bool($p[$key]??false,$key==='urgent'?'Urgência':'Proteção adicional');
        $p['extras']=self::number($p['extras']??0,0,5,'Serviços extras',true);$p['tolls']=self::number($p['tolls']??0,0,10000,'Pedágios');return$p;
    }
    public static function table(string $table,string $op,array $d): array {
        if($op==='delete')return [];
        if($table==='addresses')return self::address($d,$op==='update');
        if($table==='vehicles'){
            if($op==='insert')self::keys($d,['category_id','brand','model','plate','year','active'],['category_id','brand','model','year']);
            if(array_key_exists('category_id',$d))$d['category_id']=self::slug($d['category_id']);
            foreach(['brand'=>'Marca','model'=>'Modelo']as$key=>$label)if(array_key_exists($key,$d))$d[$key]=Validation::text($d[$key],2,80,$label);
            if(array_key_exists('year',$d))$d['year']=self::number($d['year'],1980,(int)date('Y')+1,'Ano do veículo',true);
            if(array_key_exists('active',$d))$d['active']=self::bool($d['active'],'Veículo ativo');
            if(array_key_exists('plate',$d)||$op==='insert'){
                if(($d['category_id']??'')==='bicycle'&&empty($d['plate']))$d['plate']=null;
                else{if(!is_string($d['plate']??null))throw new ApiException('Informe a placa do veículo.',422);$d['plate']=strtoupper(str_replace('-','',$d['plate']));if(!preg_match('/^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$/D',$d['plate']))throw new ApiException('Placa deve seguir ABC1234 ou ABC1D23.',422);}
            }
        }
        if($table==='reviews'){
            self::keys($d,['delivery_id','rating','comment'],['delivery_id','rating']);$d['delivery_id']=Validation::uuid($d['delivery_id']);$d['rating']=self::number($d['rating'],1,5,'Avaliação',true);$d['comment']=Validation::text($d['comment']??'',0,1000,'Comentário');
        }
        if($table==='support_tickets'){
            if($op==='insert'){self::keys($d,['delivery_id','subject','message'],['subject','message']);$d['subject']=Validation::text($d['subject'],5,150,'Assunto');$d['message']=Validation::text($d['message'],10,4000,'Mensagem');$d['delivery_id']=empty($d['delivery_id'])?null:Validation::uuid($d['delivery_id']);}
            if(array_key_exists('status',$d))$d['status']=self::choice($d['status'],['open','in_progress','closed'],'Status do suporte');
            if(array_key_exists('admin_reply',$d))$d['admin_reply']=Validation::text($d['admin_reply'],0,4000,'Resposta do suporte');
        }
        return$d;
    }
    public static function rpc(string $name,array $a): array {
        foreach(['p_delivery_id','p_vehicle_id','p_request_id','p_document_id']as$key)if(array_key_exists($key,$a))$a[$key]=Validation::uuid($a[$key]);
        if($name==='admin_monthly_revenue')$a['p_year']=self::number($a['p_year'],2000,2100,'Ano do relatório',true);
        if($name==='save_driver'){
            if(!is_string($a['p_cnh_number'])||!preg_match('/^[0-9]{11}$/D',$a['p_cnh_number']))throw new ApiException('CNH deve conter 11 números.',422);
            $a['p_cnh_category']=self::choice($a['p_cnh_category'],['A','B','AB','C','AC','D','AD','E','AE'],'Categoria da CNH');$a['p_cnh_expires_at']=self::date($a['p_cnh_expires_at'],'Validade da CNH',0,3653);
        }
        if($name==='submit_approval'){$a['p_kind']=self::choice($a['p_kind'],['driver','admin'],'Tipo de solicitação');$a['p_justification']=Validation::text($a['p_justification'],10,2000,'Justificativa');}
        if($name==='review_account'){$a['p_status']=self::choice($a['p_status'],['in_review','approved','rejected','suspended'],'Decisão');$a['p_reason']=Validation::text($a['p_reason'],3,2000,'Justificativa');}
        if($name==='review_document'){$a['p_status']=self::choice($a['p_status'],['verified','rejected'],'Decisão do documento');$a['p_reason']=Validation::text($a['p_reason'],3,2000,'Justificativa');}
        if($name==='cancel_delivery')$a['p_reason']=Validation::text($a['p_reason'],3,2000,'Motivo de cancelamento');
        if($name==='advance_delivery'){
            $a['p_status']=self::choice($a['p_status'],['collected','in_transit','near_destination','delivered'],'Etapa da entrega');$a['p_note']=Validation::text($a['p_note'],0,2000,'Observação');
            $a['p_recipient_name']=($a['p_recipient_name']??null)===null?null:Validation::text($a['p_recipient_name'],3,160,'Nome do recebedor');if($a['p_status']==='delivered'&&$a['p_recipient_name']===null)throw new ApiException('Informe o nome de quem recebeu a entrega.',422);
        }
        if($name==='track_delivery'){$a['p_code']=strtoupper(Validation::text($a['p_code'],3,40,'Código de rastreio'));if(!preg_match('/^[A-Z0-9-]+$/D',$a['p_code']))throw new ApiException('Código de rastreio inválido.',422);}
        if($name==='quote_delivery'){
            $a['p_category_id']=self::slug($a['p_category_id']);$a['p_items']=self::items($a['p_items']);$a['p_distance_km']=self::number($a['p_distance_km'],0.001,10000,'Distância');$a['p_urgent']=self::bool($a['p_urgent'],'Urgência');$a['p_protection']=self::bool($a['p_protection'],'Proteção');$a['p_extras']=self::number($a['p_extras'],0,5,'Serviços extras',true);$a['p_tolls']=self::number($a['p_tolls'],0,10000,'Pedágios');
        }
        if($name==='quote_delivery'&&isset($a['p_scheduled_at'])){
            $stamp=Validation::text($a['p_scheduled_at'],10,40,'Agendamento');if(!preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})?$/D',$stamp))throw new ApiException('Use data e horário de agendamento válidos.',422);try{$date=new \DateTimeImmutable($stamp);$errors=\DateTimeImmutable::getLastErrors();}catch(\Throwable $e){throw new ApiException('Agendamento inválido.',422);}
            if(is_array($errors)&&($errors['warning_count']||$errors['error_count']))throw new ApiException('Agendamento inválido.',422);$a['p_scheduled_at']=$date->format('c');
        }
        if($name==='confirm_pickup_vehicle'){$a['p_matches']=self::bool($a['p_matches'],'Conferência do veículo');$a['p_note']=Validation::text($a['p_note'],$a['p_matches']?0:3,2000,'Observação da conferência');}
        if($name==='update_pricing_settings')$a['p_values']=self::pricing($a['p_values']);
        if($name==='create_delivery'){if(!is_array($a['p_payload']))throw new ApiException('Dados da entrega inválidos.',422);$a['p_payload']=self::delivery($a['p_payload']);}
        if($name==='update_tariff'){
            $a['p_category_id']=self::slug($a['p_category_id']);$v=$a['p_values'];if(!is_array($v)||!$v)throw new ApiException('Informe os parâmetros da categoria.',422);
            self::keys($v,['base_price','price_per_km','weight_price','volume_price','operational_fee','protection_fee','active','name','description','protection','max_weight_kg','max_volume_m3','length_cm','width_cm','height_cm','fuel_km_per_litre']);
            foreach($v as$key=>&$value){if($key==='active')$value=self::bool($value,'Categoria ativa');elseif(in_array($key,['name','description','protection'],true))$value=Validation::text($value,$key==='name'?2:0,$key==='name'?100:1000,$key==='name'?'Nome':'Descrição');else{$max=match($key){'max_weight_kg'=>100000,'max_volume_m3'=>1000,'length_cm','width_cm','height_cm'=>10000,'fuel_km_per_litre'=>200,default=>1000000};$value=self::number($value,in_array($key,['max_weight_kg','max_volume_m3','length_cm','width_cm','height_cm'],true)?0.000001:0,$max,'Parâmetro '.$key);}}
            unset($value);$a['p_values']=$v;
        }
        return$a;
    }
    public static function pricing(mixed $v): array {
        if(!is_array($v)||!$v)throw new ApiException('Informe as configurações de preço.',422);
        self::keys($v,['fuel_price_per_litre','peak_multiplier','peak_hours','peak_weekdays','timezone','urgent_multiplier','extra_service_fee','max_extra_services','tolls_enabled','max_distance_km','route_required','commission_percent']);
        foreach($v as$key=>&$value){
            if(in_array($key,['route_required','tolls_enabled'],true))$value=self::bool($value,$key);
            elseif($key==='timezone')$value=self::choice($value,['America/Sao_Paulo'],'Fuso horário');
            elseif($key==='peak_weekdays'){if(!is_array($value)||!array_is_list($value)||count($value)>7)throw new ApiException('Dias de pico inválidos.',422);$value=array_values(array_unique(array_map(fn($d)=>self::number($d,1,7,'Dia da semana',true),$value)));}
            elseif($key==='peak_hours'){if(!is_array($value)||!array_is_list($value)||count($value)>8)throw new ApiException('Intervalos de pico inválidos.',422);foreach($value as&$pair){if(!is_array($pair)||!array_is_list($pair)||count($pair)!==2)throw new ApiException('Use pares de hora inicial/final.',422);$pair=[self::number($pair[0],0,23,'Hora inicial',true),self::number($pair[1],1,24,'Hora final',true)];if($pair[0]>=$pair[1])throw new ApiException('Hora final deve ser maior que a inicial.',422);}unset($pair);}
            else{$min=in_array($key,['peak_multiplier','urgent_multiplier'],true)?1:($key==='max_distance_km'?0.001:0);$max=match($key){'fuel_price_per_litre'=>100,'peak_multiplier','urgent_multiplier'=>5,'max_extra_services'=>5,'max_distance_km'=>10000,'extra_service_fee'=>1000,'commission_percent'=>100,default=>1000000};$value=self::number($value,$min,$max,$key,$key==='max_extra_services');if($key==='commission_percent'&&abs((float)$value*100-round((float)$value*100))>0.000001)throw new ApiException('Comissão deve ter até duas casas decimais.',422);}
        }unset($value);return$v;
    }
    public static function slug(mixed $v): string {if(!is_string($v)||!preg_match('/^[a-z][a-z0-9_]{1,49}$/D',$v))throw new ApiException('Categoria de veículo inválida.',422);return$v;}
}
