<?php
declare(strict_types=1);
/** Deterministic BFF tests; no Supabase, SMTP, SMS or provider network requests. */
require dirname(__DIR__).'/src/bootstrap.php';
use Movee\{Config,Application,Supabase,ApiException};
putenv('APP_URL=http://127.0.0.1:8080');putenv('APP_KEY='.str_repeat('e',64));putenv('SUPABASE_URL=https://confirmation-test.supabase.co');putenv('SUPABASE_PUBLISHABLE_KEY=TEST_NOT_A_REAL_KEY');putenv('SMS_ENABLED=true');
if(session_status()!==PHP_SESSION_ACTIVE){ini_set('session.save_path',sys_get_temp_dir());session_start();}
final class ConfirmationGateway extends Supabase {
    public array $calls=[];public array $user;public array $signupResponse=[];public array $consumed=[];public int $profileReads=0;
    public function __construct(Config $c,bool $confirmed=true){parent::__construct($c);$this->user=['id'=>'22222222-2222-4222-8222-222222222222','email'=>'pessoa@example.test','email_confirmed_at'=>$confirmed?'2026-01-01T12:00:00Z':null,'phone_confirmed_at'=>null,'user_metadata'=>[]];}
    public function auth():array{return ['access_token'=>'auth-token-from-provider','refresh_token'=>'refresh-token-from-provider','expires_in'=>3600,'user'=>array_replace($this->user,['email_confirmed_at'=>'2026-01-01T12:00:00Z'])];}
    public function call(string $path,string $method='GET',mixed $body=null,?string $token=null,bool $service=false,array $headers=[],bool $raw=false):mixed{
        $this->calls[]=[$path,$method,$body,$token,$service];
        if($path==='/auth/v1/user'&&$method==='GET')return $this->user;
        if(str_starts_with($path,'/auth/v1/token?'))return $this->auth();
        if(str_starts_with($path,'/auth/v1/signup'))return $this->signupResponse;
        if($path==='/auth/v1/verify'){
            if(($body['type']??'')==='phone_change'){return ['user'=>$this->user];}
            if(isset($body['token_hash'])){
                if($body['token_hash']!==str_repeat('a',64)||isset($this->consumed[$body['token_hash']]))throw new ApiException('Este link é inválido, expirou ou já foi utilizado.',422,'confirmation_invalid');
                $this->consumed[$body['token_hash']]=true;
            }elseif(($body['token']??'')!=='654321')throw new ApiException('Código inválido.',422,'confirmation_invalid');
            $this->user['email_confirmed_at']='2026-01-01T12:00:00Z';return $this->auth();
        }
        if(str_starts_with($path,'/rest/v1/profiles')){$this->profileReads++;return [['id'=>$this->user['id'],'role'=>'client','full_name'=>'Pessoa Teste']];}
        if($path==='/auth/v1/user'&&$method==='PUT')return $this->user;
        if(str_starts_with($path,'/auth/v1/recover')||$path==='/auth/v1/resend'||$path==='/auth/v1/logout')return [];
        throw new RuntimeException('Unexpected test request: '.$path);
    }
    public function rpc(string $name,array $args,string $token='',bool $service=false):mixed{throw new RuntimeException('Domain RPC must not run in authentication test');}
}
$results=[];$serial=0;
function example(bool $confirmed=true,bool $signedIn=false):array{
 global $serial;$serial++;$_SERVER['REMOTE_ADDR']='confirmation-fixture-'.$serial;unset($_SERVER['HTTP_ORIGIN']);$_SERVER['HTTP_X_CSRF_TOKEN']=str_repeat('b',64);
 $_SESSION=['csrf'=>str_repeat('b',64)];if($signedIn)$_SESSION+=['access_token'=>'old-access','refresh_token'=>'old-refresh','expires_at'=>time()+3600,'auth_user'=>['id'=>'old-user']];
 $c=new Config('/not-a-real-env');$g=new ConfirmationGateway($c,$confirmed);return[new Application($c,$g),$g];
}
function test(string $name,callable $f):void{global $results;try{if($f()!==true)throw new RuntimeException('assertion failed');$results[]=[$name,true];}catch(Throwable $e){$results[]=[$name,false,$e->getMessage()];}}
function denied(callable $f,int $status,string $code=''):bool{try{$f();return false;}catch(ApiException $e){return $e->status===$status&&($code===''||$e->errorCode===$code);}}
function registration():array{return ['email'=>'pessoa@example.test','password'=>'Movee@2026x','channel'=>'email','metadata'=>['full_name'=>'Pessoa Teste','cpf_cnpj'=>'52998224725','phone'=>'11987654321','birth_date'=>'1990-01-01','requested_role'=>'client','terms'=>true]];}

test('Login blocks canonical unconfirmed email',function(){[$a,$g]=example(false);return denied(fn()=>$a->dispatch('login',['email'=>'pessoa@example.test','password'=>'correct-password']),403,'confirmation_required')&&!isset($_SESSION['access_token']);});
test('Token response pretending confirmed cannot bypass canonical Auth',function(){[$a,$g]=example(false);return $g->auth()['user']['email_confirmed_at']!==null&&denied(fn()=>$a->dispatch('login',['email'=>'pessoa@example.test','password'=>'correct-password']),403,'confirmation_required');});
test('Editable metadata does not confirm email',function(){[$a,$g]=example(false);$g->user['user_metadata']=['email_confirmed_at'=>'2026-01-01','email_confirmed'=>true];return denied(fn()=>$a->dispatch('login',['email'=>'pessoa@example.test','password'=>'correct-password']),403,'confirmation_required');});
test('Phone confirmation does not replace email confirmation',function(){[$a,$g]=example(false);$g->user['phone_confirmed_at']='2026-01-01';$g->user['confirmed_at']='2026-01-01';return denied(fn()=>$a->dispatch('login',['email'=>'pessoa@example.test','password'=>'correct-password']),403,'confirmation_required');});
test('Confirmed email can sign in and sees account',function(){[$a,$g]=example();$s=$a->dispatch('login',['email'=>'pessoa@example.test','password'=>'correct-password']);return $s['user']['email_confirmed']===true&&$s['profile']['role']==='client';});
test('Session response never exposes Auth access or refresh tokens',function(){[$a,$g]=example();$s=$a->dispatch('login',['email'=>'pessoa@example.test','password'=>'correct-password']);$json=json_encode($s);return !str_contains($json,'auth-token-from-provider')&&!str_contains($json,'refresh-token-from-provider')&&isset($_SESSION['access_token']);});
test('Existing unconfirmed protected session is cleared',function(){[$a,$g]=example(false,true);$s=$a->session();return $s['user']===null&&$s['profile']===null&&$s['confirmation_required']===true&&!isset($_SESSION['access_token'],$_SESSION['refresh_token']);});
test('Protected data operation checks confirmation before reading profiles',function(){[$a,$g]=example(false,true);return denied(fn()=>$a->dispatch('data',['table'=>'profiles','op'=>'list']),403,'confirmation_required')&&$g->profileReads===0;});
test('Protected domain RPC blocks before calling database',function(){[$a,$g]=example(false,true);return denied(fn()=>$a->dispatch('rpc',['name'=>'admin_report','args'=>[]]),403,'confirmation_required');});
test('Protected upload blocks before file processing',function(){[$a,$g]=example(false,true);return denied(fn()=>$a->dispatch('upload',['kind'=>'identity']),403,'confirmation_required');});
test('Protected document signing blocks before database request',function(){[$a,$g]=example(false,true);return denied(fn()=>$a->dispatch('document',['id'=>'33333333-3333-4333-8333-333333333333']),403,'confirmation_required');});
test('Protected payments block before creating financial record',function(){[$a,$g]=example(false,true);return denied(fn()=>$a->dispatch('payment',['delivery_id'=>'33333333-3333-4333-8333-333333333333','method'=>'pix']),403,'confirmation_required');});
test('Token refresh re-checks canonical email',function(){[$a,$g]=example(false,true);$_SESSION['expires_at']=time()-1;return denied(fn()=>$a->dispatch('data',['table'=>'profiles','op'=>'list']),403,'confirmation_required')&&!isset($_SESSION['access_token']);});
test('New signup requires verification and never creates login session',function(){[$a,$g]=example(false);$r=$a->dispatch('register',registration());return $r['requires_verification']===true&&!isset($_SESSION['access_token'])&&str_contains($r['message'],'link');});
test('Auto-confirm signup access token is rejected as configuration failure',function(){[$a,$g]=example();$g->signupResponse=$g->auth();return denied(fn()=>$a->dispatch('register',registration()),503,'confirmation_not_configured')&&!isset($_SESSION['access_token']);});
test('Auto-confirm signup nested session is rejected',function(){[$a,$g]=example();$g->signupResponse=['session'=>['access_token'=>'unexpected']];return denied(fn()=>$a->dispatch('register',registration()),503,'confirmation_not_configured');});
test('Already-confirmed signup user is not accepted silently',function(){[$a,$g]=example();$g->signupResponse=['user'=>$g->user];return denied(fn()=>$a->dispatch('register',registration()),503,'confirmation_not_configured');});
test('Email hash confirms from another device without email field',function(){[$a,$g]=example(false);$s=$a->dispatch('verify',['channel'=>'email','type'=>'signup','token_hash'=>str_repeat('a',64)]);return $s['user']['email_confirmed']===true&&isset($_SESSION['access_token']);});
test('Hash goes only to trusted Auth verification endpoint',function(){[$a,$g]=example(false);$a->dispatch('verify',['channel'=>'email','type'=>'signup','token_hash'=>str_repeat('a',64)]);$v=array_values(array_filter($g->calls,fn($c)=>$c[0]==='/auth/v1/verify'))[0];return $v[2]===['token_hash'=>str_repeat('a',64),'type'=>'signup'];});
test('Consumed email hash cannot be reused',function(){[$a,$g]=example(false);$payload=['channel'=>'email','type'=>'signup','token_hash'=>str_repeat('a',64)];$a->dispatch('verify',$payload);return denied(fn()=>$a->dispatch('verify',$payload),422,'confirmation_invalid');});
test('Invalid or expired email hash never signs in',function(){[$a,$g]=example(false);return denied(fn()=>$a->dispatch('verify',['channel'=>'email','type'=>'signup','token_hash'=>str_repeat('z',64)]),422,'confirmation_invalid')&&!isset($_SESSION['access_token']);});
test('Malformed hash length rejected before Auth',function(){[$a,$g]=example(false);$r=denied(fn()=>$a->dispatch('verify',['token_hash'=>'short']),422);return $r&&$g->calls===[];});
test('Malformed hash punctuation rejected before Auth',function(){[$a,$g]=example(false);$r=denied(fn()=>$a->dispatch('verify',['token_hash'=>str_repeat('<',64)]),422);return $r&&$g->calls===[];});
test('Ambiguous link plus OTP rejected',function(){[$a,$g]=example(false);return denied(fn()=>$a->dispatch('verify',['token_hash'=>str_repeat('a',64),'token'=>'654321']),422,'confirmation_invalid')&&$g->calls===[];});
test('Browser access and refresh tokens are never accepted as verification',function(){[$a,$g]=example(false);return denied(fn()=>$a->dispatch('verify',['access_token'=>'fragment-access','refresh_token'=>'fragment-refresh']),422)&&$g->calls===[];});
test('OTP email fallback remains valid',function(){[$a,$g]=example(false);$s=$a->dispatch('verify',['channel'=>'email','email'=>'pessoa@example.test','token'=>'654321','type'=>'signup']);return $s['user']['email_confirmed']===true;});
test('Recovery link creates a short-lived reset authorization',function(){[$a,$g]=example();$a->dispatch('verify',['channel'=>'email','type'=>'recovery','token_hash'=>str_repeat('a',64)]);return isset($_SESSION['recovery_verified_at'])&&$a->dispatch('reset_password',['password'=>'Movee@New2026'])['updated']===true;});
test('Invalid recovery link never grants reset authorization',function(){[$a,$g]=example();return denied(fn()=>$a->dispatch('verify',['channel'=>'email','type'=>'recovery','token_hash'=>str_repeat('z',64)]),422)&&!isset($_SESSION['recovery_verified_at']);});
test('SMS cannot use hash or recovery channel to bypass email',function(){[$a,$g]=example(false,true);return denied(fn()=>$a->dispatch('verify',['channel'=>'sms','type'=>'recovery','token'=>'654321']),422)&&denied(fn()=>$a->dispatch('verify',['channel'=>'sms','token_hash'=>str_repeat('a',64)]),422);});
test('Confirmation requires CSRF even for email-link hash',function(){[$a,$g]=example(false);$_SERVER['HTTP_X_CSRF_TOKEN']='incorrect';return denied(fn()=>$a->dispatch('verify',['token_hash'=>str_repeat('a',64)]),403,'csrf')&&$g->calls===[];});

foreach($results as $r)echo($r[1]?'PASS ':'FAIL ').$r[0].(isset($r[2])?' — '.$r[2]:'').PHP_EOL;
$failed=count(array_filter($results,fn($r)=>!$r[1]));echo count($results)." confirmation checks; $failed failures.\n";exit($failed?1:0);
