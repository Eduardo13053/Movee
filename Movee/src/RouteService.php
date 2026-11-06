<?php
declare(strict_types=1);
namespace Movee;
/** Geocoding/routing credentials and trusted route evidence never leave the server. */
final class RouteService {
    public function __construct(private Config $config,private Supabase $db) {}
    public static function canonical(array $a): array {
        $a=Fields::address($a);$out=[];
        foreach(['postal_code','street','number','complement','neighborhood','city','state','reference']as$key)$out[$key]=trim((string)($a[$key]??''));
        return$out;
    }
    private static function addressHash(array $a): string { return hash('sha256',json_encode(self::canonical($a),JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)); }
    private function geocode(array $a): array {
        $text=$a['street'].', '.$a['number'].', '.$a['neighborhood'].', '.$a['city'].' - '.$a['state'].', '.$a['postal_code'].', Brasil';
        $query=http_build_query(['text'=>$text,'filter'=>'countrycode:br','limit'=>1,'format'=>'json','apiKey'=>$this->config->get('GEOAPIFY_API_KEY')],'','&',PHP_QUERY_RFC3986);
        $r=Http::request('GET','https://api.geoapify.com/v1/geocode/search?'.$query);
        if($r['status']!==200||!is_array($r['data']))throw new ApiException('O serviço de endereços está indisponível. Tente novamente.',502,'routing_unavailable');
        $p=$r['data']['results'][0]??null;
        if(!is_array($p)||!is_numeric($p['lat']??null)||!is_numeric($p['lon']??null))throw new ApiException('Não foi possível localizar um dos endereços. Confira rua, número, CEP e cidade.',422,'address_not_found');
        $lat=(float)$p['lat'];$lon=(float)$p['lon'];
        if(!is_finite($lat)||!is_finite($lon)||$lat< -90||$lat>90||$lon< -180||$lon>180||isset($p['country_code'])&&strtolower($p['country_code'])!=='br')throw new ApiException('O endereço retornado não pôde ser validado.',502,'invalid_route');
        if(isset($p['rank']['confidence'])&&(float)$p['rank']['confidence']<0.4)throw new ApiException('O endereço é impreciso. Acrescente número, bairro e CEP para calcular a rota.',422,'ambiguous_address');
        return[$lat,$lon];
    }
    public function calculate(array $pickup,array $destination,string $category,string $userId): array {
        if($this->config->get('GEOAPIFY_API_KEY')==='')throw new ApiException('O cálculo automático de rota ainda não foi configurado.',503,'routing_not_configured');
        if(strlen($this->config->get('APP_KEY'))<32)throw new ApiException('Configure uma APP_KEY segura antes de calcular rotas.',503);
        $category=Fields::slug($category);$userId=Validation::uuid($userId);$pickup=self::canonical($pickup);$destination=self::canonical($destination);
        $from=$this->geocode($pickup);$to=$this->geocode($destination);$mode=$category==='bicycle'?'bicycle':(str_contains($category,'truck')?'truck':'drive');
        $query=http_build_query(['waypoints'=>$from[0].','.$from[1].'|'.$to[0].','.$to[1],'mode'=>$mode,'format'=>'geojson','apiKey'=>$this->config->get('GEOAPIFY_API_KEY')],'','&',PHP_QUERY_RFC3986);
        $r=Http::request('GET','https://api.geoapify.com/v1/routing?'.$query);$p=$r['data']['features'][0]['properties']??null;
        if($r['status']!==200||!is_array($p)||!is_numeric($p['distance']??null)||!is_numeric($p['time']??null))throw new ApiException('Não foi possível calcular uma rota entre esses endereços.',422,'route_not_found');
        $distance=ceil((float)$p['distance'])/1000;$minutes=ceil((float)$p['time']/60);
        if(!is_finite($distance)||$distance<=0||$distance>10000||!is_finite($minutes)||$minutes<0||$minutes>30000)throw new ApiException('A rota está fora dos limites atendidos pela plataforma.',422,'route_out_of_range');
        $distance=number_format($distance,3,'.','');$expires=time()+1800;
        $id=$this->db->rpc('store_route_quote',['p_user_id'=>$userId,'p_category_id'=>$category,'p_pickup'=>$pickup,'p_destination'=>$destination,'p_distance_km'=>$distance,'p_duration_minutes'=>$minutes,'p_expires_at'=>gmdate('c',$expires)],'',true);
        if(is_array($id))$id=$id['id']??$id[0]['id']??null;$id=Validation::uuid($id);
        $claims=['v'=>1,'user'=>$userId,'category'=>$category,'distance'=>$distance,'minutes'=>$minutes,'expires'=>$expires,'pickup'=>self::addressHash($pickup),'destination'=>self::addressHash($destination),'route_id'=>$id];
        $body=rtrim(strtr(base64_encode(json_encode($claims,JSON_THROW_ON_ERROR)),'+/','-_'),'=');
        $signature=hash_hmac('sha256',$body,$this->config->get('APP_KEY'));
        return['distance_km'=>$distance,'duration_minutes'=>$minutes,'route_token'=>$body.'.'.$signature,'source'=>'geoapify','expires_at'=>gmdate('c',$expires)];
    }
    public function verifyForQuote(string $category,string $userId,mixed $token): array {
        if(!is_string($token)||strlen($token)>2048||substr_count($token,'.')!==1)throw new ApiException('Calcule novamente a rota antes de continuar.',422,'route_required');
        [$body,$signature]=explode('.',$token,2);
        if(!preg_match('/^[A-Za-z0-9_-]+$/D',$body)||!preg_match('/^[a-f0-9]{64}$/D',$signature)||!hash_equals(hash_hmac('sha256',$body,$this->config->get('APP_KEY')),$signature))throw new ApiException('A cotação de rota foi alterada. Calcule novamente.',422,'invalid_route_token');
        $json=base64_decode(strtr($body,'-_','+/'),true);$c=is_string($json)?json_decode($json,true):null;
        if(!is_array($c)||($c['v']??null)!==1||($c['user']??null)!==$userId||($c['category']??null)!==$category||!is_int($c['expires']??null)||$c['expires']<time())throw new ApiException('A rota expirou ou não corresponde a esta conta/veículo. Calcule novamente.',422,'expired_route_token');
        $c['route_id']=Validation::uuid($c['route_id']??'');$c['distance']=Fields::number($c['distance']??null,0.001,10000,'Distância da rota');return$c;
    }
    public function verify(array $pickup,array $destination,string $category,string $userId,mixed $token): array {
        $c=$this->verifyForQuote($category,$userId,$token);
        if(!hash_equals($c['pickup']??'',self::addressHash($pickup))||!hash_equals($c['destination']??'',self::addressHash($destination)))throw new ApiException('Os endereços mudaram. Calcule novamente a rota.',422,'route_address_changed');
        return$c;
    }
}
