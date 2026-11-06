<?php
declare(strict_types=1);
namespace Movee;
final class Security {
    public static function headers(): void {
        header('X-Content-Type-Options: nosniff');header('Referrer-Policy: strict-origin-when-cross-origin');header('X-Frame-Options: DENY');
        header("Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'");
        header('Permissions-Policy: camera=(), microphone=(), geolocation=()');
        if ((!empty($_SERVER['HTTPS'])&&$_SERVER['HTTPS']!=='off')) header('Strict-Transport-Security: max-age=31536000');
    }
    public static function start(Config $config): void {
        ini_set('session.use_strict_mode','1');ini_set('session.use_only_cookies','1');
        $sessionPath=$config->get('SESSION_PATH',dirname(__DIR__).'/var/sessions');
        if(!is_dir($sessionPath)&&!mkdir($sessionPath,0700,true)&&!is_dir($sessionPath))throw new ApiException('Não foi possível preparar a sessão segura no servidor.',503);
        $resolved=realpath($sessionPath);$public=realpath(dirname(__DIR__).'/public');
        if(!$resolved||!is_writable($resolved)||($public&&($resolved===$public||str_starts_with($resolved,$public.DIRECTORY_SEPARATOR))))throw new ApiException('O diretório de sessões deve ser gravável e privado, fora de public/.',503);
        session_save_path($resolved);
        session_name('movee_session');session_set_cookie_params(['lifetime'=>0,'path'=>'/','secure'=>str_starts_with($config->url(),'https://'),'httponly'=>true,'samesite'=>'Lax']);session_start();
        $_SESSION['csrf']??=bin2hex(random_bytes(32));
        if (isset($_SESSION['last_activity'])&&time()-(int)$_SESSION['last_activity']>3600) { $_SESSION=['csrf'=>bin2hex(random_bytes(32))]; session_regenerate_id(true); }
        $_SESSION['last_activity']=time();
    }
    public static function csrf(Config $config): void {
        $origin=$_SERVER['HTTP_ORIGIN']??'';
        if ($origin!=='' && rtrim($origin,'/')!==$config->url()) throw new ApiException('Origem da requisição não autorizada.',403,'csrf');
        $token=$_SERVER['HTTP_X_CSRF_TOKEN']??'';
        if (!is_string($token)||!hash_equals($_SESSION['csrf']??'', $token)) throw new ApiException('Atualize a página e tente novamente.',403,'csrf');
    }
    public static function rate(Config $config,string $bucket,int $limit=10,int $window=900): void {
        $directory=dirname(__DIR__).'/var/rate';if(!is_dir($directory)&&!mkdir($directory,0700,true)&&!is_dir($directory))throw new ApiException('Proteção de acesso indisponível.',503);
        // REMOTE_ADDR only: client-controlled forwarding headers cannot bypass quotas.
        $key=hash_hmac('sha256',$bucket.'|'.($_SERVER['REMOTE_ADDR']??'cli'),$config->get('APP_KEY','unconfigured-local-only'));
        $fh=fopen($directory.'/'.$key.'.json','c+');if(!$fh||!flock($fh,LOCK_EX))throw new ApiException('Proteção de acesso indisponível.',503);
        $v=json_decode(stream_get_contents($fh)?:'{}',true);$now=time();if(!is_array($v)||$now-($v['start']??0)>$window)$v=['start'=>$now,'count'=>0];
        $v['count']++;ftruncate($fh,0);rewind($fh);fwrite($fh,json_encode($v));fflush($fh);flock($fh,LOCK_UN);fclose($fh);
        if($v['count']>$limit)throw new ApiException('Muitas tentativas. Aguarde alguns minutos antes de tentar novamente.',429,'rate_limited');
    }
}
