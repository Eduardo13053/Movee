<?php
declare(strict_types=1);
namespace Movee;
/** Decimal business validation shared by the native MongoDB adapter. */
final class MongoValidation {
    public const STATES='AC|AL|AP|AM|BA|CE|DF|ES|GO|MA|MT|MS|MG|PA|PB|PR|PE|PI|RJ|RN|RS|RO|RR|SC|SP|SE|TO';
    public static function decimal(mixed $v,string $min='0',string $max='1000000000000',int $scale=12): string {
        if($v instanceof \MongoDB\BSON\Decimal128)$v=(string)$v;
        if(!is_scalar($v)||is_bool($v))throw new ApiException('Valor decimal inválido.',422);
        $s=(string)$v;
        if(!preg_match('/^-?(?:0|[1-9]\d{0,20})(?:\.\d{1,12})?$/D',$s)||bccomp($s,$min,$scale)<0||bccomp($s,$max,$scale)>0)throw new ApiException('Valor numérico fora do intervalo permitido.',422);
        return $s;
    }
    public static function integer(mixed $v,int $min,int $max): int {
        if(!is_scalar($v)||is_bool($v)||!preg_match('/^-?\d+$/D',(string)$v)||strlen((string)$v)>12||(int)$v<$min||(int)$v>$max)throw new ApiException('Valor inteiro inválido.',422);
        return (int)$v;
    }
    public static function boolean(mixed $v): bool { if(!is_bool($v))throw new ApiException('Valor booleano inválido.',422);return $v; }
    public static function round(string $n,int $scale=2): string {
        $delta='0.'.str_repeat('0',$scale).'5';return bcadd($n,bccomp($n,'0',12)<0?'-'.$delta:$delta,$scale);
    }
    public static function weight(mixed $value,mixed $unit): string {
        $v=self::decimal($value,'0.000000000001','14000000000');
        $kg=match($unit){'mg'=>bcdiv($v,'1000000',12),'g'=>bcdiv($v,'1000',12),'kg'=>$v,'t'=>bcmul($v,'1000',12),default=>throw new ApiException('Unidade de peso inválida.',422)};
        return self::decimal($kg,'0.000001','14000');
    }
    public static function phone(mixed $v): string {
        $n=Validation::digits($v);if(in_array(strlen($n),[12,13],true)&&str_starts_with($n,'55'))$n=substr($n,2);
        $ddd=['11','12','13','14','15','16','17','18','19','21','22','24','27','28','31','32','33','34','35','37','38','41','42','43','44','45','46','47','48','49','51','53','54','55','61','62','63','64','65','66','67','68','69','71','73','74','75','77','79','81','82','83','84','85','86','87','88','89','91','92','93','94','95','96','97','98','99'];
        if(!in_array(substr($n,0,2),$ddd,true)||!preg_match('/^[1-9]{2}(?:[2-5]\d{7}|9\d{8})$/D',$n))throw new ApiException('Telefone brasileiro inválido.',422);return $n;
    }
    public static function address(mixed $v,bool $saved=false): array {
        if(!is_array($v)||array_is_list($v))throw new ApiException('Endereço inválido.',422);
        $out=[];foreach(['street'=>[2,200],'number'=>[1,30],'neighborhood'=>[2,100],'city'=>[2,100]]as$k=>$range)$out[$k]=Validation::text($v[$k]??'',...[$range[0],$range[1],$k]);
        $out['postal_code']=Validation::digits($v['postal_code']??'');if(!preg_match('/^\d{8}$/D',$out['postal_code']))throw new ApiException('CEP inválido.',422);
        $out['state']=strtoupper(Validation::text($v['state']??'',2,2,'UF'));if(!preg_match('/^('.self::STATES.')$/D',$out['state']))throw new ApiException('Estado inválido.',422);
        foreach(['complement'=>100,'reference'=>250]as$k=>$max)$out[$k]=Validation::text($v[$k]??'',0,$max,$k);
        if($saved){$out['label']=Validation::text($v['label']??'',2,50,'Identificação');$out['is_default']=self::boolean($v['is_default']??false);}return $out;
    }
    public static function date(mixed $v): string {
        if(!is_string($v)||!preg_match('/^\d{4}-\d{2}-\d{2}$/D',$v))throw new ApiException('Data inválida.',422);
        $d=\DateTimeImmutable::createFromFormat('!Y-m-d',$v);if(!$d||$d->format('Y-m-d')!==$v)throw new ApiException('Data inválida.',422);return $v;
    }
    public static function timestamp(mixed $v): string {
        if(!is_string($v)||strlen($v)>40||!preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})?$/D',$v))throw new ApiException('Data e horário inválidos.',422);
        try{$d=new \DateTimeImmutable($v,new \DateTimeZone('America/Sao_Paulo'));}catch(\Throwable){throw new ApiException('Data e horário inválidos.',422);}return $d->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z');
    }
}
