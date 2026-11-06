<?php
declare(strict_types=1);
require dirname(__DIR__).'/src/bootstrap.php';
use Movee\{Validation,Fields,Config,Application,Supabase,RouteService,ApiException};
// Pure validation and BFF boundary tests. No network, no real Auth users, no external credentials.
$results=[];
function check(string $name, callable $test): void { global $results; try { if($test()!==true)throw new RuntimeException('assertion failed');$results[]=[$name,true]; }catch(Throwable $e){$results[]=[$name,false,$e->getMessage()];} }
function rejects(callable $fn,int $status=422): bool {try{$fn();return false;}catch(ApiException $e){return $e->status===$status;}}
final class FakeGateway extends Supabase {
    public array $calls=[];
    public function call(string $path,string $method='GET',mixed $body=null,?string $token=null,bool $service=false,array $headers=[],bool $raw=false): mixed {
        $this->calls[]=[$path,$method,$body,$token,$service];
        if($path==='/auth/v1/user')return ['id'=>'11111111-1111-1111-1111-111111111111','email'=>'fake@example.test','email_confirmed_at'=>'2026-01-01'];
        if(str_starts_with($path,'/rest/v1/profiles'))return [['id'=>'11111111-1111-1111-1111-111111111111','role'=>'client']];
        if($method==='POST'&&str_starts_with($path,'/rest/v1/addresses'))return [$body];
        return [];
    }
    public function rpc(string $name,array $args,string $token='',bool $service=false): mixed { $this->calls[]=[$name,$args,$token,$service];return ['called'=>$name]; }
}
check('CPF: dígitos verificadores corretos',fn()=>Validation::cpf('529.982.247-25')&&Validation::cpf('16899535009'));
check('CPF: rejeita repetição e dígito alterado',fn()=>!Validation::cpf('00000000000')&&!Validation::cpf('11111111111')&&!Validation::cpf('52998224724'));
check('CPF: rejeita letras e tamanhos incorretos',fn()=>!Validation::cpf('abc52998224725')&&!Validation::cpf('5299822472'));
check('CNPJ: numérico válido',fn()=>Validation::cnpj('11.222.333/0001-81'));
check('CNPJ: alfanumérico 2026',fn()=>Validation::cnpj('12.ABC.345/01DE-35'));
check('CNPJ: rejeita DV e sequência repetida',fn()=>!Validation::cnpj('12ABC34501DE34')&&!Validation::cnpj('00000000000000'));
check('CPF/CNPJ: vendedor aceita CNPJ, cliente exige CPF',fn()=>Validation::taxId('11.222.333/0001-81',true)==='11222333000181'&&rejects(fn()=>Validation::taxId('11222333000181')));
check('Telefone: E164 brasileiro',fn()=>Validation::e164('(11) 99999-8888')==='+5511999998888'&&Validation::e164('+55 11 99999-8888')==='+5511999998888');
check('Telefone: rejeita DDD inválido',fn()=>rejects(fn()=>Validation::e164('(00) 99999-8888')));
check('Senha: complexidade real',fn()=>Validation::password('Movee@2026x')==='Movee@2026x'&&rejects(fn()=>Validation::password('12345678')));
check('Nome: sobrenome obrigatório',fn()=>rejects(fn()=>Validation::fullName('João'))&&Validation::fullName('João da Silva')!=='');
check('Nascimento: adulto e data real',fn()=>Validation::birth('1990-05-12')==='1990-05-12'&&rejects(fn()=>Validation::birth('2020-01-01'))&&rejects(fn()=>Validation::birth('1990-02-31')));
check('UUID: bloqueia expressão de consulta',fn()=>rejects(fn()=>Validation::uuid('or=(id.not.is.null)')));
check('E-mail: valida sintaxe',fn()=>Validation::email('Pessoa@Example.test')==='pessoa@example.test'&&rejects(fn()=>Validation::email('bad')));
$c=new Config('/nonexistent');$fake=new FakeGateway($c);$app=new Application($c,$fake);
$_SESSION=['csrf'=>str_repeat('a',64),'access_token'=>'fake-token','refresh_token'=>'fake-refresh','expires_at'=>time()+3600];$_SERVER['HTTP_X_CSRF_TOKEN']=str_repeat('a',64);
check('BFF: bloqueia tabela arbitrária',fn()=>rejects(fn()=>$app->dispatch('data',['table'=>'auth.users','op'=>'list']),403));
check('BFF: bloqueia papel próprio no perfil',fn()=>rejects(fn()=>$app->dispatch('data',['table'=>'profiles','op'=>'update','id'=>'11111111-1111-1111-1111-111111111111','data'=>['role'=>'admin']]),403));
check('BFF: bloqueia RPC de pagamento privilegiada',fn()=>rejects(fn()=>$app->dispatch('rpc',['name'=>'record_demo_payment','args'=>[]]),403));
check('BFF: bloqueia coluna de filtro desconhecida',fn()=>rejects(fn()=>$app->dispatch('data',['table'=>'addresses','op'=>'list','filters'=>['or'=>'true']]),422));
check('BFF: bloqueia argumento inesperado em RPC',fn()=>rejects(fn()=>$app->dispatch('rpc',['name'=>'admin_report','args'=>['role'=>'admin']]),403));
check('BFF: login exige CSRF',function()use($app){$_SERVER['HTTP_X_CSRF_TOKEN']='bad';$r=rejects(fn()=>$app->dispatch('login',['email'=>'fake@example.test','password'=>'any']),403);$_SERVER['HTTP_X_CSRF_TOKEN']=str_repeat('a',64);return$r;});
check('BFF: bloqueia origem externa',function()use($app){$_SERVER['HTTP_ORIGIN']='https://evil.example';$r=rejects(fn()=>$app->dispatch('data',['table'=>'profiles','op'=>'list']),403);unset($_SERVER['HTTP_ORIGIN']);return$r;});
check('BFF: nega redefinir senha sem recuperação confirmada',fn()=>rejects(fn()=>$app->dispatch('reset_password',['password'=>'Movee@2026x']),403));
check('Número: rejeita NaN e infinito',fn()=>rejects(fn()=>Fields::number('NaN',0,10,'Número'))&&rejects(fn()=>Fields::number(INF,0,10,'Número')));
check('Quantidade: exige inteiro limitado',fn()=>rejects(fn()=>Fields::number(1.5,1,10000,'Quantidade',true))&&rejects(fn()=>Fields::number(10001,1,10000,'Quantidade',true)));
check('Telefone: rejeita letras e DDD inexistente',fn()=>rejects(fn()=>Validation::e164('abc11999998888'))&&rejects(fn()=>Validation::e164('20999998888')));
check('CNPJ: rejeita símbolos estranhos',fn()=>!Validation::cnpj('%11222333000181%'));
$address=['postal_code'=>'01001-000','street'=>'Praça da Sé','number'=>'s/n','neighborhood'=>'Sé','city'=>'São Paulo','state'=>'SP'];
check('Endereço: normaliza CEP',fn()=>Fields::address($address)['postal_code']==='01001000');
check('Endereço: obrigatórios ausentes',fn()=>rejects(fn()=>Fields::address(['city'=>'São Paulo'])));
check('Endereço: limita número e referência',fn()=>rejects(fn()=>Fields::address($address+['reference'=>str_repeat('a',251)]))&&rejects(fn()=>Fields::address(array_replace($address,['number'=>str_repeat('1',31)]))));
check('Endereço: CEP e estado inválidos',fn()=>rejects(fn()=>Fields::address(array_replace($address,['postal_code'=>'abc01001000'])))&&rejects(fn()=>Fields::address(array_replace($address,['state'=>'ZZ']))));
check('Endereço: alteração parcial legítima',fn()=>Fields::address(['is_default'=>true],true)===['is_default'=>true]);
check('Veículo: bicicleta dispensa placa',fn()=>Fields::table('vehicles','insert',['category_id'=>'bicycle','brand'=>'Teste','model'=>'Urbana','year'=>2025,'plate'=>''])['plate']===null);
check('Veículo: placa e ano inválidos',fn()=>rejects(fn()=>Fields::table('vehicles','insert',['category_id'=>'motorcycle','brand'=>'Teste','model'=>'Urbana','year'=>2025,'plate'=>'X']))&&rejects(fn()=>Fields::table('vehicles','insert',['category_id'=>'motorcycle','brand'=>'Teste','model'=>'Urbana','year'=>1800,'plate'=>'ABC1D23'])));
$item=['description'=>'Caixa de livros','quantity'=>1,'weight'=>1000,'unit'=>'g','length_cm'=>20,'width_cm'=>20,'height_cm'=>20];
check('Mercadoria: aceita peso e dimensões válidos',fn()=>Fields::items([$item])[0]['unit']==='g');
check('Mercadoria: rejeita peso negativo e unidade inventada',fn()=>rejects(fn()=>Fields::items([array_replace($item,['weight'=>-1])]))&&rejects(fn()=>Fields::items([array_replace($item,['unit'=>'lb'])])));
check('Mercadoria: quantidade fracionada e dimensão zero',fn()=>rejects(fn()=>Fields::items([array_replace($item,['quantity'=>1.5])]))&&rejects(fn()=>Fields::items([array_replace($item,['length_cm'=>0])])));
check('Mercadoria: rejeita campos desconhecidos',fn()=>rejects(fn()=>Fields::items([$item+['price'=>0.01]])));
check('Avaliação: restringe nota e comentário',fn()=>rejects(fn()=>Fields::table('reviews','insert',['delivery_id'=>'11111111-1111-1111-1111-111111111111','rating'=>6]))&&rejects(fn()=>Fields::table('reviews','insert',['delivery_id'=>'11111111-1111-1111-1111-111111111111','rating'=>5,'comment'=>str_repeat('a',1001)])));
check('Suporte: exige mensagem útil',fn()=>rejects(fn()=>Fields::table('support_tickets','insert',['subject'=>'Ajuda','message'=>'oi'])));
check('CNH: exige 11 números e categoria real',fn()=>rejects(fn()=>Fields::rpc('save_driver',['p_cnh_number'=>'123','p_cnh_category'=>'B','p_cnh_expires_at'=>'2030-01-01']))&&rejects(fn()=>Fields::rpc('save_driver',['p_cnh_number'=>'12345678901','p_cnh_category'=>'Z','p_cnh_expires_at'=>'2030-01-01'])));
check('Rastreio: rejeita HTML e tamanho excessivo',fn()=>rejects(fn()=>Fields::rpc('track_delivery',['p_code'=>'<script>']))&&rejects(fn()=>Fields::rpc('track_delivery',['p_code'=>str_repeat('a',41)])));
check('Tarifa: rejeita preço infinito e campo privilegiado',fn()=>rejects(fn()=>Fields::rpc('update_tariff',['p_category_id'=>'motorcycle','p_values'=>['base_price'=>INF]]))&&rejects(fn()=>Fields::rpc('update_tariff',['p_category_id'=>'motorcycle','p_values'=>['role'=>'admin']])));
check('BFF: campos obrigatórios do RPC identificados',fn()=>rejects(fn()=>$app->dispatch('rpc',['name'=>'save_driver','args'=>[]])));
check('BFF: pedido com preço injetado rejeitado',fn()=>rejects(fn()=>$app->dispatch('rpc',['name'=>'create_delivery','args'=>['p_payload'=>['price'=>0.01]]])));
check('Combustível: tarifa aceita consumo configurável',fn()=>Fields::rpc('update_tariff',['p_category_id'=>'motorcycle','p_values'=>['fuel_km_per_litre'=>35]])['p_values']['fuel_km_per_litre']===35);
check('Combustível: rejeita consumo negativo e excessivo',fn()=>rejects(fn()=>Fields::rpc('update_tariff',['p_category_id'=>'motorcycle','p_values'=>['fuel_km_per_litre'=>-1]]))&&rejects(fn()=>Fields::rpc('update_tariff',['p_category_id'=>'motorcycle','p_values'=>['fuel_km_per_litre'=>201]])));
check('Pico: valida multiplicador e horas',fn()=>Fields::pricing(['peak_multiplier'=>1.2,'peak_hours'=>[[7,9],[17,20]],'peak_weekdays'=>[1,2,3,4,5]])['peak_multiplier']===1.2);
check('Pico: rejeita intervalo invertido e fator negativo',fn()=>rejects(fn()=>Fields::pricing(['peak_hours'=>[[20,7]]]))&&rejects(fn()=>Fields::pricing(['peak_multiplier'=>-1])));
check('Combustível: preço e roteamento com tipos corretos',fn()=>Fields::pricing(['fuel_price_per_litre'=>6.2,'route_required'=>true])['route_required']===true&&rejects(fn()=>Fields::pricing(['route_required'=>'true'])));
check('Veículo: conferência exige booleano real',fn()=>rejects(fn()=>Fields::rpc('confirm_pickup_vehicle',['p_delivery_id'=>'11111111-1111-1111-1111-111111111111','p_matches'=>'sim','p_note'=>''])));
check('Veículo: divergência exige motivo',fn()=>rejects(fn()=>Fields::rpc('confirm_pickup_vehicle',['p_delivery_id'=>'11111111-1111-1111-1111-111111111111','p_matches'=>false,'p_note'=>''])));
check('Veículo: avanço exige veículo usado',fn()=>rejects(fn()=>$app->dispatch('rpc',['name'=>'advance_delivery','args'=>['p_delivery_id'=>'11111111-1111-1111-1111-111111111111','p_status'=>'collected','p_note'=>'']])));
putenv('APP_KEY=movee-test-key-0123456789-abcdefghijklmnop');$routeConfig=new Config('/nonexistent');$routes=new RouteService($routeConfig,$fake);
$canonical=RouteService::canonical($address);$addressHash=hash('sha256',json_encode($canonical,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR));
$claims=['v'=>1,'user'=>'11111111-1111-1111-1111-111111111111','category'=>'motorcycle','distance'=>'12.345','minutes'=>30,'expires'=>time()+1800,'pickup'=>$addressHash,'destination'=>$addressHash,'route_id'=>'22222222-2222-2222-2222-222222222222'];
$sign=static function(array $v)use($routeConfig){$body=rtrim(strtr(base64_encode(json_encode($v,JSON_THROW_ON_ERROR)),'+/','-_'),'=');return$body.'.'.hash_hmac('sha256',$body,$routeConfig->get('APP_KEY'));};$routeToken=$sign($claims);
check('Rota: valida prova assinada e endereços',fn()=>$routes->verify($address,$address,'motorcycle',$claims['user'],$routeToken)['distance']==='12.345');
check('Rota: token alterado rejeitado',fn()=>rejects(fn()=>$routes->verifyForQuote('motorcycle',$claims['user'],$routeToken.'a')));
check('Rota: outro usuário rejeitado',fn()=>rejects(fn()=>$routes->verifyForQuote('motorcycle','33333333-3333-3333-3333-333333333333',$routeToken)));
check('Rota: outra categoria rejeitada',fn()=>rejects(fn()=>$routes->verifyForQuote('large_truck',$claims['user'],$routeToken)));
check('Rota: expiração aplicada',fn()=>rejects(fn()=>$routes->verifyForQuote('motorcycle',$claims['user'],$sign(array_replace($claims,['expires'=>time()-1])))));
check('Rota: mudança de endereço exige recálculo',fn()=>rejects(fn()=>$routes->verify(array_replace($address,['number'=>'100']),$address,'motorcycle',$claims['user'],$routeToken)));
check('Rota: código vazio não inventa distância',fn()=>rejects(fn()=>$routes->verifyForQuote('motorcycle',$claims['user'],null)));
check('Rendimentos: ano inteiro válido',fn()=>Movee\Fields::rpc('admin_monthly_revenue',['p_year'=>2026])['p_year']===2026);
check('Rendimentos: ano fracionário rejeitado',fn()=>rejects(fn()=>Movee\Fields::rpc('admin_monthly_revenue',['p_year'=>2026.5])));
check('Rendimentos: ano fora do limite rejeitado',fn()=>rejects(fn()=>Movee\Fields::rpc('admin_monthly_revenue',['p_year'=>1999]))&&rejects(fn()=>Movee\Fields::rpc('admin_monthly_revenue',['p_year'=>2101])));
check('Rendimentos: ano booleano rejeitado',fn()=>rejects(fn()=>Movee\Fields::rpc('admin_monthly_revenue',['p_year'=>true])));
check('Rendimentos: BFF exige ano',fn()=>rejects(fn()=>$app->dispatch('rpc',['name'=>'admin_monthly_revenue','args'=>[]])));
check('Comissão: percentual30 aceito',fn()=>Movee\Fields::pricing(['commission_percent'=>30])['commission_percent']===30);
check('Comissão: limites0 e100 aceitos',fn()=>Movee\Fields::pricing(['commission_percent'=>0])['commission_percent']===0&&Movee\Fields::pricing(['commission_percent'=>100])['commission_percent']===100);
check('Comissão: negativo e acima100 rejeitados',fn()=>rejects(fn()=>Movee\Fields::pricing(['commission_percent'=>-1]))&&rejects(fn()=>Movee\Fields::pricing(['commission_percent'=>101])));
check('Comissão: precisão excessiva rejeitada',fn()=>rejects(fn()=>Movee\Fields::pricing(['commission_percent'=>'30.001'])));
foreach($results as$r)echo($r[1]?'PASS ':'FAIL ').$r[0].(isset($r[2])?' — '.$r[2]:'').PHP_EOL;
$failed=count(array_filter($results,fn($r)=>!$r[1]));echo count($results)." verificações; $failed falhas.\n";exit($failed?1:0);
