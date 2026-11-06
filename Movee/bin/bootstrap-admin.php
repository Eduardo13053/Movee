<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
require dirname(__DIR__).'/src/bootstrap.php';
use Movee\{Config,Gateway,Validation};
try{
    if($argc!==2)throw new RuntimeException('Uso: php bin/bootstrap-admin.php UUID_DO_USUARIO');
    $id=Validation::uuid($argv[1]);$db=Gateway::make(new Config());
    $db->rpc('bootstrap_admin',['p_user_id'=>$id],'',true);
    fwrite(STDOUT,"Primeiro administrador configurado. Operação registrada em auditoria.\n");
}catch(Throwable $e){fwrite(STDERR,$e->getMessage()."\n");exit(1);}
