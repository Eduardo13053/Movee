<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
require dirname(__DIR__).'/src/bootstrap.php';
use Movee\{Config,Gateway};
try{
    $c=new Config();$days=max(30,(int)$c->get('DOCUMENT_RETENTION_DAYS','180'));$cutoff=gmdate('c',time()-$days*86400);$db=Gateway::make($c);
    // Rejected documents only. Accepted identity/vehicle files remain required while the account is active.
    $rows=$db->call('/rest/v1/documents?status=eq.rejected&created_at=lt.'.rawurlencode($cutoff).'&select=id,storage_path&limit=100','GET',null,null,true);
    if(!in_array('--execute',$argv,true)){fwrite(STDOUT,count($rows)." documentos rejeitados elegíveis. Execute com --execute após revisar a política institucional de retenção.\n");exit;}
    $removed=0;
    foreach($rows as$row){
        $db->call('/storage/v1/object/movee-documents','DELETE',['prefixes'=>[$row['storage_path']]],null,true);
        $db->call('/rest/v1/documents?id=eq.'.rawurlencode($row['id']),'DELETE',null,null,true);
        $db->call('/rest/v1/audit_logs','POST',['action'=>'document.retention_delete','entity'=>'documents','entity_id'=>$row['id'],'details'=>['retention_days'=>$days]],null,true);$removed++;
    }
    fwrite(STDOUT,"Documentos rejeitados removidos: $removed. Repita para processar mais de 100. Backups seguem a retenção do provedor.\n");
}catch(Throwable $e){fwrite(STDERR,$e->getMessage()."\n");exit(1);}
