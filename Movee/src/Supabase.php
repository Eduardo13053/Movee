<?php
declare(strict_types=1);
namespace Movee;
class Supabase {
    public function __construct(protected Config $config) {}
    public function call(string $path,string $method='GET',mixed $body=null,?string $token=null,bool $service=false,array $headers=[],bool $raw=false): mixed {
        if (!$this->config->configured()) throw new ApiException('Configure o Supabase no arquivo .env do servidor para usar esta funcionalidade.',503,'not_configured');
        $key=$this->config->get($service?'SUPABASE_SERVICE_ROLE_KEY':'SUPABASE_PUBLISHABLE_KEY');
        if ($key==='') throw new ApiException('A operação exige uma credencial privada configurada no servidor.',503,'service_not_configured');
        $url=rtrim($this->config->get('SUPABASE_URL'),'/');
        if (!preg_match('~^https://[a-z0-9.-]+(?::443)?$~iD',$url)) throw new ApiException('SUPABASE_URL inválida. Use a URL HTTPS do projeto.',503);
        $headers=['apikey'=>$key,'Authorization'=>'Bearer '.($token??$key)]+$headers;
        $r=Http::request($method,$url.$path,$headers,$body,$raw);
        if ($r['status']<200 || $r['status']>=300) {
            $data=is_array($r['data'])?$r['data']:[]; $message=(string)($data['msg']??$data['message']??$data['error_description']??$data['error']??'');
            if ($r['status']===429) throw new ApiException('Muitas tentativas. Aguarde alguns minutos.',429,'rate_limited');
            $authCode=(string)($data['error_code']??$data['code']??'');
            if ($authCode==='email_not_confirmed'||stripos($message,'email not confirmed')!==false) throw new ApiException('Confirme seu e-mail pelo link recebido antes de entrar.',403,'confirmation_required');
            if (str_starts_with($path,'/auth/v1/verify')&&($authCode==='otp_expired'||$r['status']===400||$r['status']===401||$r['status']===403||$r['status']===422)) throw new ApiException('Este link ou código é inválido, expirou ou já foi utilizado. Solicite um novo e-mail de confirmação.',422,'confirmation_invalid');
            if (stripos($message,'Invalid login')!==false) throw new ApiException('E-mail ou senha incorretos.',401,'invalid_credentials');
            if ($r['status']===401) throw new ApiException('Sessão expirada ou credenciais inválidas.',401,'unauthorized');
            if ($r['status']===403) throw new ApiException('Você não tem permissão para esta operação.',403,'forbidden');
            if (($data['code']??'')==='23505') throw new ApiException('Já existe um registro com esses dados.',409,'duplicate');
            if (($data['code']??'')==='23503') throw new ApiException('Este registro possui vínculos e não pode ser removido.',409,'referenced');
            // P0001 / 22023 are intentionally authored domain validation messages in our migrations.
            if (in_array($data['code']??'', ['P0001','22023','23514'],true) && strlen($message)<350) throw new ApiException($message,422,'validation_error');
            throw new ApiException($r['status']>=500?'O Supabase não conseguiu concluir a operação. Tente novamente.':'Não foi possível concluir. Confira os dados e as permissões da conta.', $r['status']>=500?502:422,'upstream_rejected');
        }
        return $r['data'];
    }
    public function rpc(string $name,array $args,string $token='',bool $service=false): mixed { return $this->call('/rest/v1/rpc/'.rawurlencode($name),'POST',$args,$service?null:$token,$service); }
}
