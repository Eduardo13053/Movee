<?php
declare(strict_types=1);
ini_set('display_errors','0');
ini_set('log_errors','1');
require dirname(__DIR__,2).'/src/bootstrap.php';
use Movee\{Config,Security,Application,ApiException};
Security::headers();header('Content-Type: application/json; charset=utf-8');header('Cache-Control: no-store, private');
try{
    if(($_SERVER['REQUEST_METHOD']??'')!=='POST'){header('Allow: POST');throw new ApiException('Use POST para acessar a API.',405);}
    $config=new Config();Security::start($config);
    $length=(int)($_SERVER['CONTENT_LENGTH']??0);if($length>6*1024*1024)throw new ApiException('Arquivo ou requisição excede o limite.',413);
    $type=$_SERVER['CONTENT_TYPE']??'';
    if(str_starts_with($type,'multipart/form-data'))$input=$_POST;
    elseif(str_starts_with($type,'application/json')){ $raw=file_get_contents('php://input',false,null,0,262145);if(strlen($raw)>262144)throw new ApiException('Requisição muito grande.',413);$input=json_decode($raw,true,32,JSON_THROW_ON_ERROR);}
    else throw new ApiException('Formato de requisição inválido.',415);
    if(!is_array($input)||!is_string($input['action']??null))throw new ApiException('Requisição inválida.',422);
    $result=(new Application($config))->dispatch($input['action'],$input);
    echo json_encode(['ok'=>true,'data'=>$result],JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
}catch(ApiException $e){http_response_code($e->status);echo json_encode(['ok'=>false,'error'=>['message'=>$e->getMessage(),'code'=>$e->errorCode]],JSON_UNESCAPED_UNICODE);}
catch(JsonException $e){http_response_code(400);echo json_encode(['ok'=>false,'error'=>['message'=>'JSON inválido.','code'=>'invalid_json']]);}
catch(Throwable $e){http_response_code(500);error_log('Movee API unexpected error: '.get_class($e));echo json_encode(['ok'=>false,'error'=>['message'=>'Não foi possível concluir a operação. Tente novamente.','code'=>'server_error']],JSON_UNESCAPED_UNICODE);}
