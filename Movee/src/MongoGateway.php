<?php
declare(strict_types=1);
namespace Movee;
require_once __DIR__.'/MongoValidation.php';
require_once __DIR__.'/MongoDomain.php';
use MongoDB\Driver\{Manager,Query,Command,BulkWrite,Session,ReadConcern,WriteConcern,ReadPreference};
use MongoDB\BSON\Decimal128;
/** Native-driver persistence adapter. Supabase remains the password/OTP and private object service. */
class MongoGateway extends Supabase {
    use MongoDomain;
    private Manager $manager; private string $database; private ?Session $transaction=null;
    private ?string $actorToken=null; private ?array $authUser=null; private ?array $currentProfile=null; private array $freshUploads=[];
    private const COLLECTIONS=['profiles','driver_profiles','approval_requests','approval_history','addresses','vehicle_categories','vehicles','documents','deliveries','delivery_items','delivery_events','payments','notifications','reviews','delivery_proofs','support_tickets','audit_logs','outbox','system_settings','route_quotes'];
    public function __construct(Config $config) {
        parent::__construct($config);
        if(!extension_loaded('mongodb')||!extension_loaded('bcmath'))throw new ApiException('A variante MongoDB exige as extensões PHP mongodb e bcmath. Consulte docs/MONGODB.md.',503,'mongodb_not_configured');
        $uri=$config->get('MONGODB_URI');$this->database=$config->get('MONGODB_DATABASE','movee');
        if($uri===''||!preg_match('/^[a-zA-Z][a-zA-Z0-9_-]{0,62}$/D',$this->database))throw new ApiException('Configure MONGODB_URI e MONGODB_DATABASE no servidor.',503,'mongodb_not_configured');
        try{$this->manager=new Manager($uri,['serverSelectionTimeoutMS'=>5000,'connectTimeoutMS'=>5000]);}catch(\Throwable){throw new ApiException('Configuração MongoDB inválida.',503,'mongodb_not_configured');}
    }
    public function call(string $path,string $method='GET',mixed $body=null,?string $token=null,bool $service=false,array $headers=[],bool $raw=false): mixed {
        if(str_starts_with($path,'/auth/v1/')){
            $out=parent::call($path,$method,$body,$token,$service,$headers,$raw);
            if($path==='/auth/v1/user'&&is_array($out)&&isset($out['id']))$this->authUser=$out;
            return $out;
        }
        if($service)$this->requireService();else if($token||!($path==='/rest/v1/vehicle_categories'||str_starts_with($path,'/rest/v1/vehicle_categories?')))$this->identity($token);
        if(str_starts_with($path,'/storage/v1/'))return $this->storageCall($path,$method,$body,$token,$service,$headers,$raw);
        if(!str_starts_with($path,'/rest/v1/'))throw new ApiException('Rota do adaptador não permitida.',403);
        if(str_starts_with($path,'/rest/v1/rpc/'))return $this->rpc(rawurldecode(substr(explode('?',$path)[0],13)),is_array($body)?$body:[],$token??'',$service);
        $parts=parse_url($path);$table=rawurldecode(substr($parts['path'],9));
        if(!in_array($table,self::COLLECTIONS,true))throw new ApiException('Coleção não permitida.',403);
        parse_str($parts['query']??'',$args);$filter=$this->parseFilters($args);$scope=$service?[]:$this->scope($table,$token);$filter=$this->combine($filter,$scope);
        if($method==='GET'){
            $options=['limit'=>min(max((int)($args['limit']??100),1),100),'skip'=>min(max((int)($args['offset']??0),0),1000000)];
            if(isset($args['order'])){foreach(explode(',',$args['order']) as $sort){[$key,$direction]=array_pad(explode('.',$sort),2,'asc');if(!in_array($key,['created_at','id','scheduled_at'],true)||!in_array($direction,['asc','desc'],true))throw new ApiException('Ordenação inválida.',422);$options['sort'][$key]=$direction==='desc'?-1:1;}}
            $rows=$this->rows($table,$filter,$options);
            if(isset($args['select'])&&$args['select']!=='*'){$fields=explode(',',$args['select']);foreach($fields as$f)if(!preg_match('/^[a-z_]+$/D',$f))throw new ApiException('Seleção inválida.',422);$rows=array_map(static fn($r)=>array_intersect_key($r,array_flip($fields)),$rows);}
            return $this->clean($rows);
        }
        if(!in_array($method,['POST','PATCH','DELETE'],true)||($method!=='DELETE'&&!is_array($body)))throw new ApiException('Operação MongoDB inválida.',422);
        return $this->clean($this->atomic(fn()=>$this->writeData($table,$method,$body??[],$filter,$service)));
    }
    public function rpc(string $name,array $args,string $token='',bool $service=false): mixed {
        $serviceNames=['record_demo_payment','prepare_provider_payment','confirm_provider_payment','bootstrap_admin','claim_outbox','finish_outbox','store_route_quote'];
        if(in_array($name,$serviceNames,true)){if(!$service)throw new ApiException('Operação restrita ao serviço.',403);$this->requireService();}
        elseif($service)throw new ApiException('RPC de serviço não permitido.',403);
        elseif($name!=='quote_delivery'||$token!=='')$this->identity($token);
        $readOnly=['quote_delivery','available_deliveries','track_delivery','admin_report','assigned_vehicle','get_pricing_settings'];
        $f=fn()=>$this->domain($name,$args,$service);
        return $this->clean(in_array($name,$readOnly,true)?$f():$this->atomic($f));
    }
    protected function fetchAuth(string $token): array {return parent::call('/auth/v1/user','GET',null,$token);}
    protected function fetchAuthById(string $id): array {return parent::call('/auth/v1/admin/users/'.$id,'GET',null,null,true);}
    private function requireService(): void {if($this->config->get('SUPABASE_SERVICE_ROLE_KEY')==='')throw new ApiException('Credencial privada de serviço não configurada.',503);}
    private function identity(?string $token): array {
        if(!$token)throw new ApiException('Entre para continuar.',401);
        if($this->actorToken!==$token){$this->authUser=null;$this->currentProfile=null;$this->actorToken=$token;}
        if($this->authUser===null)$this->authUser=$this->fetchAuth($token);
        if(empty($this->authUser['id']))throw new ApiException('Sessão inválida.',401);
        // Auth metadata and a phone confirmation never replace e-mail ownership.
        if(empty($this->authUser['email'])||!is_string($this->authUser['email_confirmed_at']??null)||$this->authUser['email_confirmed_at']===''){
            $this->currentProfile=null;
            throw new ApiException('Confirme seu e-mail pelo link recebido antes de entrar.',403,'confirmation_required');
        }
        $id=Validation::uuid($this->authUser['id']);$p=$this->one('profiles',['id'=>$id]);
        if(!$p){
            // Metadata never grants permissions. Only immutable initial account attributes are copied.
            $m=$this->authUser['user_metadata']??[];$role=$m['requested_role']??'client';if(!in_array($role,['client','seller','driver','admin'],true)||($m['terms']??false)!==true)throw new ApiException('Cadastro Auth incompleto para Movee. Cadastre-se pela aplicação.',422);
            $now=$this->now();$p=['id'=>$id,'full_name'=>Validation::fullName($m['full_name']??''),'cpf_cnpj'=>Validation::taxId($m['cpf_cnpj']??'',$role==='seller'),'phone'=>MongoValidation::phone($m['phone']??''),'birth_date'=>Validation::birth($m['birth_date']??''),'role'=>'client','requested_role'=>$role,'terms_accepted_at'=>$now,'verification_channel'=>($m['verification_channel']??'email')==='sms'?'sms':'email','created_at'=>$now,'updated_at'=>$now];
            try{$this->atomic(function()use($p,$role,$id){$this->insert('profiles',$p);if($role==='driver')$this->insert('driver_profiles',['id'=>$id,'cnh_number'=>null,'cnh_category'=>null,'cnh_expires_at'=>null,'status'=>'pending','created_at'=>$this->now()]);$this->notify($id,'Bem-vindo ao Movee','Complete os documentos do seu cadastro.','account.created');});}catch(ApiException $e){$existing=$this->one('profiles',['id'=>$id]);if(!$existing)throw $e;$p=$existing;}
        }
        $this->currentProfile=$p;
        if(!empty($this->authUser['email_confirmed_at'])&&empty($p['_confirmation_notified'])){
            $this->atomic(function()use($id){$this->lockProfile($id);$latest=$this->one('profiles',['id'=>$id]);if(empty($latest['_confirmation_notified'])){$this->update('profiles',['id'=>$id],['_confirmation_notified'=>true]);$this->notify($id,'Canal confirmado','Confirmação registrada. Complete o perfil para continuar.','account.confirmed');}});
        }
        return $p;
    }
    private function uid(): string {return $this->currentProfile['id']??throw new ApiException('Autenticação necessária.',401);}
    private function admin(): bool {return ($this->currentProfile['role']??'')==='admin';}
    private function assertAdmin(): void {if(!$this->admin())throw new ApiException('Acesso administrativo necessário.',403);}
    private function scope(string $table,?string $token): array {
        if($table==='vehicle_categories')return $token&&$this->admin()?[]:['active'=>true];
        $u=$this->uid();if($this->admin()&&!in_array($table,['addresses','notifications'],true))return [];
        return match($table){
            'profiles','driver_profiles'=>['id'=>$u],
            'approval_requests','addresses','documents','payments','notifications','support_tickets'=>['user_id'=>$u],
            'vehicles'=>['driver_id'=>$u],
            'deliveries'=>['$or'=>[['client_id'=>$u],['driver_id'=>$u]]],
            'reviews'=>['$or'=>[['client_id'=>$u],['driver_id'=>$u]]],
            'delivery_items','delivery_events','delivery_proofs'=>['delivery_id'=>['$in'=>array_column($this->rows('deliveries',['$or'=>[['client_id'=>$u],['driver_id'=>$u]]],['projection'=>['id'=>1]]),'id')]],
            'approval_history'=>['request_id'=>['$in'=>array_column($this->rows('approval_requests',['user_id'=>$u],['projection'=>['id'=>1]]),'id')]],
            default=>throw new ApiException('Consulta sem permissão.',403)
        };
    }
    private function parseFilters(array $args): array {
        $out=[];foreach($args as$k=>$v){if(in_array($k,['select','order','limit','offset'],true))continue;if(!preg_match('/^[a-z_]+$/D',$k)||!is_string($v)||!preg_match('/^(eq|lt)\.(.*)$/sD',$v,$m)||strlen($m[2])>300)throw new ApiException('Filtro MongoDB inválido.',422);$value=match($m[2]){'true'=>true,'false'=>false,'null'=>null,default=>$m[2]};$out[$k]=$m[1]==='lt'?['$lt'=>$value]:$value;}return $out;
    }
    private function combine(array $a,array $b): array {return !$a?$b:(!$b?$a:['$and'=>[$a,$b]]);}
    private function now(): string {return (new \DateTimeImmutable('now',new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.v\Z');}
    private function uuid(): string {$x=random_bytes(16);$x[6]=chr((ord($x[6])&15)|64);$x[8]=chr((ord($x[8])&63)|128);$h=bin2hex($x);return substr($h,0,8).'-'.substr($h,8,4).'-'.substr($h,12,4).'-'.substr($h,16,4).'-'.substr($h,20);}
    private function rows(string $table,array $filter=[],array $options=[]): array {
        $q=new Query($filter,$options);$cursor=$this->manager->executeQuery($this->database.'.'.$table,$q,$this->transaction?['session'=>$this->transaction]:[]);$cursor->setTypeMap(['root'=>'array','document'=>'array','array'=>'array']);return $cursor->toArray();
    }
    private function one(string $table,array $filter): ?array {return $this->rows($table,$filter,['limit'=>1])[0]??null;}
    private function insert(string $table,array $row): array { $row['id']??=$this->uuid();$row['_id']=$row['id'];$row['created_at']??=$this->now();$b=new BulkWrite();$b->insert($row);$this->bulk($table,$b);return $row; }
    private function update(string $table,array $filter,array $values,bool $multi=false): void { $b=new BulkWrite();$b->update($filter,['$set'=>$values],['multi'=>$multi]);$this->bulk($table,$b); }
    private function remove(string $table,array $filter): void {$b=new BulkWrite();$b->delete($filter,['limit'=>1]);$this->bulk($table,$b);}
    private function bulk(string $table,BulkWrite $b): void {try{$this->manager->executeBulkWrite($this->database.'.'.$table,$b,$this->transaction?['session'=>$this->transaction]:[]);}catch(\MongoDB\Driver\Exception\BulkWriteException $e){if($e->getCode()===11000)throw new ApiException('Já existe um registro com esses dados.',409,'duplicate');if($e->getCode()===121)throw new ApiException('Dados recusados pela validação da coleção.',422,'validation_error');throw $e;}}
    private function lockProfile(string $id): void {$b=new BulkWrite();$b->update(['id'=>$id],['$inc'=>['_rev'=>1]]);$this->bulk('profiles',$b);}
    private function atomic(callable $f): mixed {
        if($this->transaction)return $f();
        for($attempt=0;$attempt<4;$attempt++){
            $s=$this->manager->startSession();$this->transaction=$s;
            try{$s->startTransaction(['readConcern'=>new ReadConcern('snapshot'),'writeConcern'=>new WriteConcern('majority'),'readPreference'=>new ReadPreference(ReadPreference::PRIMARY)]);$v=$f();for($c=0;;$c++){try{$s->commitTransaction();break;}catch(\MongoDB\Driver\Exception\RuntimeException $e){if($c<3&&$e->hasErrorLabel('UnknownTransactionCommitResult'))continue;throw $e;}}$this->transaction=null;return $v;}
            catch(\Throwable $e){try{if($s->isInTransaction())$s->abortTransaction();}catch(\Throwable){}$this->transaction=null;if($e instanceof \MongoDB\Driver\Exception\RuntimeException&&$e->hasErrorLabel('TransientTransactionError')&&$attempt<3)continue;if($e instanceof ApiException)throw $e;error_log('Movee MongoDB failure: '.get_class($e));throw new ApiException('O MongoDB não concluiu a operação. Verifique conexão, inicialização e replica set.',503,'mongodb_unavailable');}
        }throw new ApiException('Conflito simultâneo. Tente novamente.',409);
    }
    private function clean(mixed $v): mixed {if($v instanceof Decimal128)return(string)$v;if(is_array($v)){$o=[];foreach($v as$k=>$x){if(is_string($k)&&str_starts_with($k,'_'))continue;$o[$k]=$this->clean($x);}return $o;}return $v;}
    private function dec(mixed $v,int $scale=6): Decimal128 {return new Decimal128(bcadd(MongoValidation::decimal($v),'0',$scale));}
    private function notify(string $u,string $title,string $body,string $event): void {$this->insert('notifications',['user_id'=>$u,'title'=>$title,'body'=>$body,'read_at'=>null]);$this->insert('outbox',['event'=>$event,'payload'=>['user_id'=>$u,'title'=>$title,'body'=>$body],'status'=>'pending','attempts'=>0,'locked_at'=>null,'last_error'=>null,'available_at'=>$this->now()]);}
    private function audit(string $action,string $entity,string $id,array $details=[]): void {$this->insert('audit_logs',['actor_id'=>$this->currentProfile['id']??null,'action'=>$action,'entity'=>$entity,'entity_id'=>$id,'details'=>$details]);}
    private function event(array $d,string $note): void {$this->insert('delivery_events',['delivery_id'=>$d['id'],'status'=>$d['status'],'note'=>$note]);}
    private function storageCall(string $path,string $method,mixed $body,?string $token,bool $service,array $headers,bool $raw): mixed {
        $this->requireService();$base='/storage/v1/object/';$plain=rawurldecode($path);
        if(!str_starts_with($plain,$base)||str_contains($plain,'..')||str_contains($plain,"\0"))throw new ApiException('Armazenamento não permitido.',403);
        if($service&&$method==='POST'&&$raw&&!empty($this->authUser['id'])&&str_starts_with($plain,$base.'movee-documents/'.$this->authUser['id'].'/'))$this->freshUploads[substr($plain,strlen($base.'movee-documents/'))]=true;
        if(!$service){
            $u=$this->uid();$sign=str_starts_with($plain,$base.'sign/movee-documents/');
            if($sign){$name=substr($plain,strlen($base.'sign/movee-documents/'));$doc=$this->one('documents',['storage_path'=>$name]);if(!$doc||($doc['user_id']!==$u&&!$this->admin()))throw new ApiException('Documento sem permissão.',403);if($method!=='POST')throw new ApiException('Operação não permitida.',403);$body=['expiresIn'=>60];}
            elseif($method==='POST'&&str_starts_with($plain,$base.'movee-documents/'.$u.'/')){$name=substr($plain,strlen($base.'movee-documents/'));if(!preg_match('~^'.preg_quote($u,'~').'/[a-f0-9]{40}\.(jpg|png|pdf)$~D',$name))throw new ApiException('Caminho de upload inválido.',422);$this->freshUploads[$name]=true;}
            elseif($method==='DELETE'&&$plain===$base.'movee-documents'){foreach(($body['prefixes']??[])as$name)if(!isset($this->freshUploads[$name]))throw new ApiException('Remoção de documento não autorizada.',403);}
            else throw new ApiException('Acesso direto ao Storage não permitido.',403);
        }
        return parent::call($path,$method,$body,null,true,$headers,$raw);
    }
    private function writeData(string $table,string $method,array $data,array $filter,bool $service): array {
        if($service){if(!in_array($table,['documents','audit_logs'],true))throw new ApiException('Escrita de serviço não permitida.',403);if($method==='POST'&&$table==='audit_logs')return[$this->insert($table,$data+['actor_id'=>null])];if($method==='DELETE'&&$table==='documents'){$old=$this->one($table,$filter);if($old)$this->remove($table,$filter);return$old?[$old]:[];}throw new ApiException('Escrita de serviço inválida.',403);}
        $u=$this->uid();$this->lockProfile($u);$this->currentProfile=$this->one('profiles',['id'=>$u]);$old=$method==='POST'?null:$this->one($table,$filter);if($method!=='POST'&&!$old)return [];
        $allowed=match($table){'addresses'=>['label','postal_code','street','number','complement','neighborhood','city','state','reference','is_default','user_id'],'vehicles'=>['category_id','brand','model','plate','year','active','driver_id'],'documents'=>['user_id','vehicle_id','kind','storage_path','mime_type','size_bytes'],'notifications'=>['read_at'],'reviews'=>['delivery_id','client_id','driver_id','rating','comment'],'support_tickets'=>['user_id','delivery_id','subject','message','status','admin_reply'],default=>throw new ApiException('Escrita não permitida.',403)};
        if(array_diff(array_keys($data),$allowed))throw new ApiException('Campo protegido ou desconhecido.',403);
        if($table==='vehicles'&&$old&&$this->one('deliveries',['vehicle_id'=>$old['id'],'status'=>['$nin'=>['delivered','cancelled']]]))throw new ApiException('Veículo vinculado a entrega ativa não pode ser alterado ou removido.',422);
        if($method==='DELETE'){
            if(!in_array($table,['addresses','vehicles'],true))throw new ApiException('Remoção não permitida.',403);
            if($table==='vehicles'){if($this->one('deliveries',['vehicle_id'=>$old['id']]))throw new ApiException('Veículo vinculado a entrega não pode ser removido; desative-o.',409);foreach($this->rows('documents',['vehicle_id'=>$old['id']])as$d)$this->remove('documents',['id'=>$d['id']]);}
            $this->remove($table,['id'=>$old['id']]);return[$old];
        }
        $r=array_merge($old??[],$data);
        if($table==='addresses'){
            if(($r['user_id']??$u)!==$u)throw new ApiException('Titular não permitido.',403);$r=MongoValidation::address($r,true)+['user_id'=>$u];
            if($method==='POST'&&count($this->rows('addresses',['user_id'=>$u]))>=3)throw new ApiException('Limite de três endereços atingido.',422);
            if($r['is_default'])$this->update('addresses',['user_id'=>$u],['is_default'=>false],true);
        }elseif($table==='vehicles'){
            if(($r['driver_id']??$u)!==$u||!$this->one('driver_profiles',['id'=>$u]))throw new ApiException('Cadastro de entregador necessário.',403);
            $r['driver_id']=$u;$r['category_id']=Validation::text($r['category_id']??'',2,40,'Categoria');if(!$this->one('vehicle_categories',['id'=>$r['category_id']]))throw new ApiException('Categoria inexistente.',422);
            $r['brand']=Validation::text($r['brand']??'',2,80,'Marca');$r['model']=Validation::text($r['model']??'',2,80,'Modelo');$r['year']=MongoValidation::integer($r['year']??0,1980,(int)date('Y')+1);$r['active']=MongoValidation::boolean($r['active']??true);
            $r['plate']=isset($r['plate'])&&$r['plate']!==''?strtoupper(preg_replace('/[^A-Za-z0-9]/','',(string)$r['plate'])):null;if(($r['category_id']!=='bicycle'&&!$r['plate'])||($r['plate']&&!preg_match('/^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$/D',$r['plate'])))throw new ApiException('Placa inválida.',422);
            if($old&&$this->one('documents',['vehicle_id'=>$old['id'],'status'=>'verified']))foreach(['category_id','brand','model','plate','year']as$k)if($r[$k]!==$old[$k])throw new ApiException('Veículo verificado: solicite suporte para alterar documentação.',422);
        }elseif($table==='documents'){
            if($method!=='POST'||($r['user_id']??'')!==$u||!isset($this->freshUploads[$r['storage_path']??'']))throw new ApiException('Documento deve ser enviado pela operação de upload.',403);
            if(!in_array($r['kind']??'',['identity','cnh','vehicle'],true)||!in_array($r['mime_type']??'',['image/jpeg','image/png','application/pdf'],true))throw new ApiException('Tipo de documento inválido.',422);
            $r['size_bytes']=MongoValidation::integer($r['size_bytes']??0,100,5242880);$r['status']='pending';$r['vehicle_id']??=null;
            if(($r['kind']==='vehicle')!==($r['vehicle_id']!==null))throw new ApiException('Vínculo do documento inválido.',422);if($r['vehicle_id']&&!$this->one('vehicles',['id'=>$r['vehicle_id'],'driver_id'=>$u]))throw new ApiException('Veículo não autorizado.',403);
        }elseif($table==='notifications'){if($method!=='PATCH')throw new ApiException('Operação inválida.',403);$r['read_at']=$this->now();}
        elseif($table==='reviews'){
            if($method!=='POST')throw new ApiException('Avaliação imutável.',403);$d=$this->one('deliveries',['id'=>Validation::uuid($r['delivery_id']??''),'client_id'=>$u,'status'=>'delivered']);if(!$d)throw new ApiException('Avalie somente sua entrega concluída.',422);$r=['delivery_id'=>$d['id'],'client_id'=>$u,'driver_id'=>$d['driver_id'],'rating'=>MongoValidation::integer($r['rating']??0,1,5),'comment'=>Validation::text($r['comment']??'',0,1000,'Comentário')];
        }elseif($table==='support_tickets'){
            if($method==='POST'){$r=['user_id'=>$u,'delivery_id'=>$r['delivery_id']??null,'subject'=>Validation::text($r['subject']??'',5,150,'Assunto'),'message'=>Validation::text($r['message']??'',10,4000,'Mensagem'),'status'=>'open','admin_reply'=>''];if($r['delivery_id']&&!$this->one('deliveries',$this->combine(['id'=>Validation::uuid($r['delivery_id'])],['$or'=>[['client_id'=>$u],['driver_id'=>$u]]])))throw new ApiException('Entrega não vinculada à conta.',422);}
            else{$this->assertAdmin();if(array_diff(array_keys($data),['status','admin_reply']))throw new ApiException('Campo de suporte protegido.',403);if(!in_array($r['status']??'',['open','in_progress','closed'],true))throw new ApiException('Status inválido.',422);$r['admin_reply']=Validation::text($r['admin_reply']??'',0,5000,'Resposta');$this->audit('support.update','support_tickets',$old['id'],['status'=>$r['status']]);if($r['admin_reply']!==$old['admin_reply'])$this->notify($old['user_id'],'Seu suporte recebeu uma resposta','Acesse a central de ajuda.','support.replied');}
        }
        if($method==='POST')return[$this->insert($table,$r)];unset($r['_id'],$r['id']);$this->update($table,['id'=>$old['id']],$r);return[$this->one($table,['id'=>$old['id']])];
    }
}
