<?php
declare(strict_types=1);
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
require dirname(__DIR__).'/src/bootstrap.php';
use Movee\{Config,Gateway,Http,Validation};
try{
    $c=new Config();if($c->get('RESEND_API_KEY')===''||$c->get('MAIL_FROM')==='')throw new RuntimeException('Configure RESEND_API_KEY e MAIL_FROM. A fila permanece pendente até a configuração.');
    $db=Gateway::make($c);$rows=$db->rpc('claim_outbox',['p_limit'=>20],'',true);$sent=0;$failed=0;
    foreach($rows as$row){
        try{
            $p=$row['payload'];$admin=$row['event']==='approval.admin_notice';
            if($admin){$to=Validation::email($c->get('ADMIN_NOTIFICATION_EMAIL','MoveeEntregas@gmail.com'));$subject='Nova solicitação administrativa · Movee';$body='Há uma nova solicitação de acesso administrativo para análise. Entre no painel protegido para consultar os documentos.';$path='/admin.html';}
            else{
                $id=Validation::uuid($p['user_id']??'');$user=$db->call('/auth/v1/admin/users/'.$id,'GET',null,null,true);$to=Validation::email($user['email']??'');
                $subject=Validation::text($p['title']??'Atualização Movee',1,200,'Assunto');$body=Validation::text($p['body']??'Consulte sua conta para mais detalhes.',1,4000,'Mensagem');$path='/notificacoes.html';
            }
            $link=$c->url().$path;$text=$body."\n\nAcesse sua conta: ".$link."\n\nMovee · Mensagem automática. Não envie documentos por e-mail.";
            $r=Http::request('POST','https://api.resend.com/emails',['Authorization'=>'Bearer '.$c->get('RESEND_API_KEY'),'Idempotency-Key'=>'movee-outbox-'.$row['id']],['from'=>$c->get('MAIL_FROM'),'to'=>[$to],'subject'=>$subject,'text'=>$text]);
            if($r['status']<200||$r['status']>=300)throw new RuntimeException('O serviço de e-mail recusou o envio.');
            $db->rpc('finish_outbox',['p_id'=>$row['id'],'p_success'=>true,'p_error'=>null],'',true);$sent++;
        }catch(Throwable $e){$db->rpc('finish_outbox',['p_id'=>$row['id'],'p_success'=>false,'p_error'=>'Falha de entrega de e-mail. Confira configuração do provedor e destinatário no servidor.'],'',true);$failed++;}
    }
    fwrite(STDOUT,"E-mails enviados: $sent; falhas para nova tentativa: $failed.\n");
}catch(Throwable $e){fwrite(STDERR,$e->getMessage()."\n");exit(1);}
