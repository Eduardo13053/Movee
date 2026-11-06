<?php
declare(strict_types=1);
ini_set('display_errors','0');
ini_set('log_errors','1');
require dirname(__DIR__,2).'/src/bootstrap.php';
use Movee\{Config,Security,Gateway,Http,Validation,ApiException};
Security::headers();header('Content-Type: application/json');header('Cache-Control: no-store');
try{
    if(($_SERVER['REQUEST_METHOD']??'')!=='POST')throw new ApiException('Método inválido.',405);
    $c=new Config();if($c->get('PAYMENT_MODE')!=='live'||$c->get('MERCADOPAGO_WEBHOOK_SECRET')===''||$c->get('MERCADOPAGO_ACCESS_TOKEN')==='')throw new ApiException('Webhook não configurado.',503);
    if((int)($_SERVER['CONTENT_LENGTH']??0)>32768)throw new ApiException('Payload inválido.',413);
    $payload=json_decode(file_get_contents('php://input',false,null,0,32768),true)??[];
    $id=(string)($_GET['data_id']??$_GET['id']??$payload['data']['id']??'');
    if(!preg_match('/^[0-9]{1,30}$/D',$id))throw new ApiException('Identificador inválido.',400);
    $signature=$_SERVER['HTTP_X_SIGNATURE']??'';$requestId=$_SERVER['HTTP_X_REQUEST_ID']??'';$parts=[];
    foreach(explode(',',$signature)as$pair){$kv=explode('=',$pair,2);if(count($kv)===2)$parts[trim($kv[0])]=trim($kv[1]);}
    $ts=$parts['ts']??'';$sig=$parts['v1']??'';
    if(!ctype_digit($ts)||!preg_match('/^[a-f0-9]{64}$/Di',$sig)||$requestId===''||strlen($requestId)>200)throw new ApiException('Assinatura ausente ou inválida.',401);
    $seconds=strlen($ts)>10?(int)floor((int)$ts/1000):(int)$ts;
    if(abs(time()-$seconds)>300)throw new ApiException('Assinatura expirada.',401);
    $manifest='id:'.strtolower($id).';request-id:'.$requestId.';ts:'.$ts.';';
    if(!hash_equals(hash_hmac('sha256',$manifest,$c->get('MERCADOPAGO_WEBHOOK_SECRET')),strtolower($sig)))throw new ApiException('Assinatura inválida.',401);
    $type=$_GET['type']??$payload['type']??'payment';if($type!=='payment'){echo '{"received":true}';exit;}
    // Never trust webhook status, amount, payer or external_reference. Re-fetch using server credential.
    $r=Http::request('GET','https://api.mercadopago.com/v1/payments/'.rawurlencode($id),['Authorization'=>'Bearer '.$c->get('MERCADOPAGO_ACCESS_TOKEN')]);
    if($r['status']!==200||!is_array($r['data']))throw new ApiException('Provedor indisponível.',502);
    $p=$r['data'];if((string)($p['id']??'')!==$id)throw new ApiException('Transação divergente.',422);
    if(($p['status']??'')==='approved'){
        $deliveryId=Validation::uuid($p['external_reference']??'');
        if(($p['currency_id']??'')!=='BRL'||!is_numeric($p['transaction_amount']??null))throw new ApiException('Pagamento divergente.',422);
        Gateway::make($c)->rpc('confirm_provider_payment',['p_delivery_id'=>$deliveryId,'p_transaction_id'=>$id,'p_amount'=>$p['transaction_amount'],'p_currency'=>'BRL'],'',true);
    }
    echo '{"received":true}';
}catch(ApiException $e){http_response_code($e->status);echo json_encode(['received'=>false,'error'=>$e->errorCode]);}
catch(Throwable $e){http_response_code(500);error_log('Movee webhook failed: '.get_class($e));echo '{"received":false}';}
