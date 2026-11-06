<?php
declare(strict_types=1);
namespace Movee;
final class Application {
    private Supabase $db;
    public function __construct(private Config $config, ?Supabase $gateway = null) { $this->db=$gateway ?? Gateway::make($config); }
    public function dispatch(string $action,array $input): mixed {
        if($action==='session')return $this->session();
        Security::csrf($this->config);
        return match($action){
            'login'=>$this->login($input), 'register'=>$this->register($input), 'verify'=>$this->verify($input),
            'logout'=>$this->logout(), 'recover'=>$this->recover($input), 'reset_password'=>$this->resetPassword($input),
            'resend'=>$this->resend($input), 'route'=>$this->route($input), 'data'=>$this->data($input), 'rpc'=>$this->rpc($input),
            'upload'=>$this->upload($input), 'document'=>$this->document($input), 'payment'=>$this->payment($input),
            default=>throw new ApiException('Operação desconhecida.',404,'unknown_action')
        };
    }
    private function token(): string {
        if(empty($_SESSION['access_token']))throw new ApiException('Entre na sua conta para continuar.',401,'login_required');
        if(($_SESSION['expires_at']??0)<time()+60){
            try{$this->storeAuth($this->db->call('/auth/v1/token?grant_type=refresh_token','POST',['refresh_token'=>$_SESSION['refresh_token']??'']));}
            catch(ApiException $e){$this->clearAuth();if($e->errorCode==='confirmation_required')throw $e;throw new ApiException('Sua sessão expirou. Entre novamente.',401,'login_required');}
        }
        return $_SESSION['access_token'];
    }
    private function clearAuth(): void { unset($_SESSION['access_token'],$_SESSION['refresh_token'],$_SESSION['expires_at'],$_SESSION['auth_user'],$_SESSION['recovery_verified_at']); }
    /** Only the canonical Auth field is trusted; editable user metadata is never proof. */
    private function confirmedUser(mixed $u): array {
        if(!is_array($u)||!is_string($u['id']??null)||$u['id']===''){$this->clearAuth();throw new ApiException('Sessão inválida. Entre novamente.',401,'login_required');}
        if(empty($u['email'])||!is_string($u['email_confirmed_at']??null)||$u['email_confirmed_at']===''){
            $this->clearAuth();throw new ApiException('Confirme seu e-mail pelo link recebido antes de entrar. Você também pode solicitar um novo e-mail de confirmação.',403,'confirmation_required');
        }
        return $u;
    }
    private function user(): array { $token=$this->token();$u=$this->confirmedUser($this->db->call('/auth/v1/user','GET',null,$token));$_SESSION['auth_user']=$u;return $u; }
    private function storeAuth(array $auth): void {
        if(!is_string($auth['access_token']??null)||$auth['access_token']===''||!is_string($auth['refresh_token']??null)||$auth['refresh_token']==='')throw new ApiException('Não foi possível iniciar uma sessão. Confirme sua conta.',422);
        // Re-fetch Auth even when a token response contains an apparently confirmed user.
        $u=$this->confirmedUser($this->db->call('/auth/v1/user','GET',null,$auth['access_token']));
        if(session_status()===PHP_SESSION_ACTIVE)session_regenerate_id(true);
        $_SESSION['access_token']=$auth['access_token'];$_SESSION['refresh_token']=$auth['refresh_token'];$_SESSION['expires_at']=$auth['expires_at']??time()+(int)($auth['expires_in']??3600);$_SESSION['auth_user']=$u;
    }
    public function session(): array {
        $out=['user'=>null,'profile'=>null,'csrf'=>$_SESSION['csrf'],'configured'=>$this->config->configured(),'payment_mode'=>$this->config->get('PAYMENT_MODE','demo'),'sms_enabled'=>$this->config->bool('SMS_ENABLED'),'route_enabled'=>$this->config->get('GEOAPIFY_API_KEY')!=='','pricing_config'=>null,'confirmation_required'=>false];
        if(!$out['configured']||empty($_SESSION['access_token']))return $out;
        try{
            $u=$this->user();$out['user']=['id'=>$u['id'],'email'=>$u['email']??'','email_confirmed'=>!empty($u['email_confirmed_at']),'phone_confirmed'=>!empty($u['phone_confirmed_at'])];
            $p=$this->db->call('/rest/v1/profiles?id=eq.'.rawurlencode($u['id']).'&select=*','GET',null,$this->token());$out['profile']=$p[0]??null;
            if(($out['profile']['role']??'')==='admin')$out['pricing_config']=$this->db->rpc('get_pricing_settings',[],$this->token());
        }catch(ApiException $e){if($e->status!==401&&$e->errorCode!=='confirmation_required')throw $e;$this->clearAuth();$out['user']=null;$out['profile']=null;$out['pricing_config']=null;$out['confirmation_required']=$e->errorCode==='confirmation_required';}
        return $out;
    }
    private function login(array $v): array {
        Security::rate($this->config,'login',10);$email=Validation::email($v['email']??'');$password=Validation::text($v['password']??'',1,128,'Senha');
        $this->clearAuth();$r=$this->db->call('/auth/v1/token?grant_type=password','POST',['email'=>$email,'password'=>$password]);$this->storeAuth($r);return $this->session();
    }
    private function register(array $v): array {
        Security::rate($this->config,'register',5,3600);$m=$v['metadata']??[];
        if(!is_array($m))throw new ApiException('Dados de cadastro inválidos.',422);
        Fields::keys($m,['full_name','cpf_cnpj','phone','birth_date','requested_role','terms'],['full_name','cpf_cnpj','phone','birth_date','requested_role','terms']);
        $channel=$v['channel']??'email';if(!in_array($channel,['email','sms'],true)||($channel==='sms'&&!$this->config->bool('SMS_ENABLED')))throw new ApiException('Canal de confirmação não disponível.',422);
        $role=$m['requested_role']??'client';if(!in_array($role,['client','seller','driver','admin'],true))throw new ApiException('Tipo de conta inválido.',422);
        if(($m['terms']??false)!==true)throw new ApiException('Aceite os termos e a política de privacidade.',422);
        $metadata=['full_name'=>Validation::fullName($m['full_name']??''),'cpf_cnpj'=>Validation::taxId($m['cpf_cnpj']??'', $role==='seller'),'phone'=>Validation::e164($m['phone']??$v['phone']??''),'birth_date'=>Validation::birth($m['birth_date']??''),'requested_role'=>$role,'terms'=>true,'verification_channel'=>$channel];
        $this->clearAuth();$r=$this->db->call('/auth/v1/signup?redirect_to='.rawurlencode($this->config->url().'/verificar.html'),'POST',['email'=>Validation::email($v['email']??''),'password'=>Validation::password($v['password']??''),'data'=>$metadata]);
        // An auto-confirmed signup indicates an unsafe Auth configuration for this product.
        if(is_array($r)&&(!empty($r['access_token'])||!empty($r['session'])||!empty($r['user']['email_confirmed_at'])||!empty($r['email_confirmed_at'])))throw new ApiException('A confirmação de e-mail precisa estar ativada no Supabase Auth. O servidor não iniciou sua sessão. Solicite a correção da configuração antes de continuar.',503,'confirmation_not_configured');
        return ['requires_verification'=>true,'channel'=>$channel,'message'=>$channel==='sms'?'Abra o e-mail e confirme o endereço pelo link. Depois, confirme o telefone por SMS.':'Abra o e-mail recebido e clique no link para confirmar seu endereço antes de entrar.'];
    }
    private function verify(array $v): array {
        Security::rate($this->config,'verify',15);Fields::keys($v,['action','channel','type','email','phone','token','token_hash']);
        $channel=Fields::choice($v['channel']??'email',['email','sms'],'Canal');$type=Fields::choice($v['type']??'signup',['signup','recovery'],'Tipo de confirmação');
        if($channel==='sms'){
            if($type==='recovery'||array_key_exists('token_hash',$v))throw new ApiException('A confirmação por link e a recuperação devem usar e-mail.',422);
            $token=Validation::text($v['token']??'',6,128,'Código');if(!preg_match('/^[A-Za-z0-9_-]+$/D',$token))throw new ApiException('Código inválido.',422);
            if(!$this->config->bool('SMS_ENABLED'))throw new ApiException('O envio de SMS não está configurado.',503);
            $u=$this->user();$phone=Validation::e164($v['phone']??($u['new_phone']??$u['phone']??''));
            $r=$this->db->call('/auth/v1/verify','POST',['phone'=>$phone,'token'=>$token,'type'=>'phone_change'],$this->token());
        }else{
            if(array_key_exists('token_hash',$v)){
                $hash=Validation::text($v['token_hash'],40,128,'Link de confirmação');
                if(!preg_match('/^[A-Za-z0-9_-]+$/D',$hash)||!empty($v['token']))throw new ApiException('Link de confirmação inválido. Solicite um novo e-mail.',422,'confirmation_invalid');
                $r=$this->db->call('/auth/v1/verify','POST',['token_hash'=>$hash,'type'=>$type]);
            }else{
                $token=Validation::text($v['token']??'',6,128,'Código');if(!preg_match('/^[A-Za-z0-9_-]+$/D',$token))throw new ApiException('Código inválido.',422);
                $r=$this->db->call('/auth/v1/verify','POST',['email'=>Validation::email($v['email']??''),'token'=>$token,'type'=>$type]);
            }
        }
        if(!empty($r['access_token']))$this->storeAuth($r);
        elseif($channel!=='sms')throw new ApiException('Não foi possível confirmar este link ou código. Solicite um novo e-mail.',422,'confirmation_invalid');
        if($type==='recovery')$_SESSION['recovery_verified_at']=time();
        return $this->session();
    }
    private function resend(array $v): array {
        Security::rate($this->config,'resend',4,900);
        if(($v['channel']??'email')==='sms'){
            if(!$this->config->bool('SMS_ENABLED'))throw new ApiException('SMS não configurado.',503);
            $this->user();$this->db->call('/auth/v1/user','PUT',['phone'=>Validation::e164($v['phone']??'')],$this->token());
        }else $this->db->call('/auth/v1/resend','POST',['type'=>'signup','email'=>Validation::email($v['email']??'')]);
        return ['sent'=>true,'message'=>'Se os dados corresponderem a uma conta elegível, uma nova confirmação será enviada ao canal escolhido.'];
    }
    private function recover(array $v): array {
        Security::rate($this->config,'recover',4,900);
        $this->db->call('/auth/v1/recover?redirect_to='.rawurlencode($this->config->url().'/verificar.html?type=recovery'),'POST',['email'=>Validation::email($v['email']??'')]);
        return ['sent'=>true,'message'=>'Se houver uma conta com esse e-mail, você receberá as instruções.'];
    }
    private function resetPassword(array $v): array {
        if(time()-(int)($_SESSION['recovery_verified_at']??0)>600)throw new ApiException('Valide um código de recuperação antes de definir a nova senha.',403);
        $this->user();$this->db->call('/auth/v1/user','PUT',['password'=>Validation::password($v['password']??'')],$this->token());unset($_SESSION['recovery_verified_at']);return ['updated'=>true];
    }
    private function logout(): array {
        if(!empty($_SESSION['access_token']))try{$this->db->call('/auth/v1/logout','POST',null,$_SESSION['access_token']);}catch(ApiException $e){}
        $_SESSION=['csrf'=>bin2hex(random_bytes(32))];session_regenerate_id(true);return ['logged_out'=>true];
    }
    private const TABLES=[
      'profiles'=>['list'=>[], 'filters'=>['id','role','requested_role']],
      'driver_profiles'=>['list'=>[], 'filters'=>['id','status']],
      'approval_requests'=>['list'=>[], 'filters'=>['id','user_id','kind','status']],
      'approval_history'=>['list'=>[], 'filters'=>['id','request_id']],
      'addresses'=>['list'=>[], 'insert'=>['label','postal_code','street','number','complement','neighborhood','city','state','reference','is_default'],'update'=>['label','postal_code','street','number','complement','neighborhood','city','state','reference','is_default'],'delete'=>[],'filters'=>['id','user_id','is_default']],
      'vehicle_categories'=>['list'=>[], 'filters'=>['id','active']],
      'vehicles'=>['list'=>[], 'insert'=>['category_id','brand','model','plate','year','active'],'update'=>['category_id','brand','model','plate','year','active'],'delete'=>[],'filters'=>['id','driver_id','active']],
      'documents'=>['list'=>[], 'filters'=>['id','user_id','kind','status','vehicle_id']],
      'deliveries'=>['list'=>[], 'filters'=>['id','client_id','driver_id','status','code']],
      'delivery_items'=>['list'=>[], 'filters'=>['id','delivery_id']],
      'delivery_events'=>['list'=>[], 'filters'=>['id','delivery_id']],
      'payments'=>['list'=>[], 'filters'=>['id','delivery_id','user_id','status']],
      'notifications'=>['list'=>[],'update'=>['read_at'],'filters'=>['id','user_id']],
      'reviews'=>['list'=>[],'insert'=>['delivery_id','rating','comment'],'filters'=>['id','delivery_id','client_id','driver_id']],
      'delivery_proofs'=>['list'=>[],'filters'=>['id','delivery_id']],
      'support_tickets'=>['list'=>[],'insert'=>['delivery_id','subject','message'],'update'=>['status','admin_reply'],'filters'=>['id','user_id','status']],
      'audit_logs'=>['list'=>[],'filters'=>['id','actor_id','entity','action']]
    ];
    private function data(array $v): mixed {
        $table=$v['table']??'';$op=$v['op']??'list';if(!is_string($table))throw new ApiException('Tabela inválida.',422);$spec=self::TABLES[$table]??null;
        if(!$spec||!is_string($op)||!array_key_exists($op,$spec)||$op==='filters')throw new ApiException('Consulta não permitida.',403);
        $u=$table==='vehicle_categories'&&$op==='list'&&empty($_SESSION['access_token'])?null:$this->user();$token=$u?$this->token():null;
        $filters=$v['filters']??[];if(!is_array($filters)||count($filters)>8)throw new ApiException('Filtros inválidos.',422);
        $query=['select'=>'*'];
        foreach($filters as $key=>$value){if(!in_array($key,$spec['filters'],true)||!is_scalar($value)||strlen((string)$value)>100)throw new ApiException('Filtro inválido.',422);$query[$key]='eq.'.(is_bool($value)?($value?'true':'false'):(string)$value);}
        if($op==='list'){$query['limit']=(string)Fields::number($v['limit']??100,1,100,'Limite da página',true);$query['offset']=(string)Fields::number($v['offset']??0,0,1000000,'Posição da página',true);$query['order']=$table==='vehicle_categories'?'id.asc':'created_at.desc,id.desc';return $this->db->call('/rest/v1/'.$table.'?'.http_build_query($query),'GET',null,$token);}
        Security::rate($this->config,'write',120,60);
        $id=isset($v['id'])?Validation::uuid($v['id']):null;
        if(in_array($op,['update','delete'],true)&&!$id)throw new ApiException('Identificador obrigatório.',422);
        $d=$v['data']??[];if(!is_array($d)||array_is_list($d)&&$d!==[])throw new ApiException('Dados inválidos.',422);
        if(array_diff(array_keys($d),$spec[$op]))throw new ApiException('Há campos protegidos ou desconhecidos na operação.',403);
        $d=Fields::table($table,$op,$d);
        if($op==='insert'){
            if($table==='addresses'||$table==='support_tickets')$d['user_id']=$u['id'];
            if($table==='vehicles')$d['driver_id']=$u['id'];
            if($table==='reviews'){
                $d['client_id']=$u['id'];$delivery=$this->db->call('/rest/v1/deliveries?id=eq.'.Validation::uuid($d['delivery_id']??'').'&select=id,driver_id,client_id,status','GET',null,$token);
                if(empty($delivery[0])||$delivery[0]['client_id']!==$u['id']||$delivery[0]['status']!=='delivered')throw new ApiException('Avaliações estão disponíveis após uma entrega concluída.',422);$d['driver_id']=$delivery[0]['driver_id'];
            }
        }
        if($table==='notifications'&&$op==='update')$d['read_at']=gmdate('c');
        $method=['insert'=>'POST','update'=>'PATCH','delete'=>'DELETE'][$op];$url='/rest/v1/'.$table.($id?'?id=eq.'.rawurlencode($id):'');
        $r=$this->db->call($url,$method,$op==='delete'?null:$d,$token,false,['Prefer'=>'return=representation']);
        return $r[0]??$r;
    }
    private const RPCS=[
      'complete_profile'=>['p_full_name','p_cpf_cnpj','p_phone','p_birth_date','p_requested_role','p_terms'],
      'save_driver'=>['p_cnh_number','p_cnh_category','p_cnh_expires_at'], 'submit_approval'=>['p_kind','p_justification'],
      'quote_delivery'=>['p_category_id','p_items','p_distance_km','p_urgent','p_protection','p_extras','p_tolls','p_scheduled_at','p_route_token'],
      'create_delivery'=>['p_payload'], 'accept_delivery'=>['p_delivery_id','p_vehicle_id'],
      'advance_delivery'=>['p_delivery_id','p_status','p_note','p_recipient_name','p_vehicle_id'], 'cancel_delivery'=>['p_delivery_id','p_reason'],
      'track_delivery'=>['p_code'], 'review_account'=>['p_request_id','p_status','p_reason'],
      'review_document'=>['p_document_id','p_status','p_reason'], 'update_tariff'=>['p_category_id','p_values'],
      'available_deliveries'=>[], 'admin_report'=>[], 'admin_monthly_revenue'=>['p_year'], 'confirm_pickup_vehicle'=>['p_delivery_id','p_matches','p_note'],'assigned_vehicle'=>['p_delivery_id'],'get_pricing_settings'=>[],'update_pricing_settings'=>['p_values']
    ];
    private function rpc(array $v): mixed {
        $u=$this->user();$name=$v['name']??'';$args=$v['args']??[];
        if(!is_string($name)||!array_key_exists($name,self::RPCS)||!is_array($args)||array_diff(array_keys($args),self::RPCS[$name]))throw new ApiException('Operação não permitida.',403);
        Fields::keys($args,self::RPCS[$name],array_values(array_diff(self::RPCS[$name],['p_recipient_name','p_scheduled_at','p_route_token'])));
        $args=Fields::rpc($name,$args);
        if($name==='quote_delivery'){
            $token=$args['p_route_token']??null;if($token==='')$token=null;unset($args['p_route_token']);
            if($this->config->get('GEOAPIFY_API_KEY')!==''||$token!==null){$proof=(new RouteService($this->config,$this->db))->verifyForQuote($args['p_category_id'],$u['id'],$token);$args['p_distance_km']=$proof['distance'];$args['p_route_id']=$proof['route_id'];}
        }
        if($name==='create_delivery'){
            $p=&$args['p_payload'];$token=$p['route_token']??null;if($token==='')$token=null;unset($p['route_token']);
            if($this->config->get('GEOAPIFY_API_KEY')!==''||$token!==null){$proof=(new RouteService($this->config,$this->db))->verify($p['pickup'],$p['destination'],$p['category_id'],$u['id'],$token);$p['distance_km']=$proof['distance'];$p['route_id']=$proof['route_id'];$p['pickup']=RouteService::canonical($p['pickup']);$p['destination']=RouteService::canonical($p['destination']);}
            unset($p);
        }
        Security::rate($this->config,'rpc',120,60);
        if($name==='complete_profile'){
            $args['p_full_name']=Validation::fullName($args['p_full_name']??'');$args['p_birth_date']=Validation::birth($args['p_birth_date']??'');
            $args['p_requested_role']=Fields::choice($args['p_requested_role'],['client','seller','driver','admin'],'Tipo de conta');if(($args['p_terms']??false)!==true)throw new ApiException('Aceite os termos e a política de privacidade.',422);
            $args['p_cpf_cnpj']=Validation::taxId($args['p_cpf_cnpj']??'',($args['p_requested_role']??'')==='seller');$args['p_phone']=Validation::e164($args['p_phone']??'');
        }
        return $this->db->rpc($name,$args,$this->token());
    }
    private function route(array $v): array {
        Security::rate($this->config,'route',20,900);$u=$this->user();
        if(!is_array($v['pickup']??null)||!is_array($v['destination']??null))throw new ApiException('Informe coleta e destino completos.',422);
        return (new RouteService($this->config,$this->db))->calculate($v['pickup'],$v['destination'],Fields::slug($v['category_id']??''),$u['id']);
    }
    private function upload(array $v): mixed {
        Security::rate($this->config,'upload',20,3600);$u=$this->user();$kind=$v['kind']??'';
        if(!in_array($kind,['identity','cnh','vehicle'],true))throw new ApiException('Tipo de documento inválido.',422);
        $f=$_FILES['file']??null;if(!$f||!is_array($f)||($f['error']??1)!==UPLOAD_ERR_OK||!is_uploaded_file($f['tmp_name']))throw new ApiException('Envie um arquivo válido de até 5 MB.',422);
        $size=filesize($f['tmp_name']);if($size<100||$size>5*1024*1024)throw new ApiException('O documento deve ter entre 100 bytes e 5 MB.',422);
        $bytes=file_get_contents($f['tmp_name']);$mime=(new \finfo(FILEINFO_MIME_TYPE))->buffer($bytes);$ext=['image/jpeg'=>'jpg','image/png'=>'png','application/pdf'=>'pdf'][$mime]??null;
        if(!$ext)throw new ApiException('Envie apenas JPEG, PNG ou PDF. SVG e arquivos executáveis são bloqueados.',422);
        if($ext==='pdf'){
            if(!str_starts_with($bytes,'%PDF-')||!str_contains(substr($bytes,-2048),'%%EOF')||preg_match('~/(JavaScript|JS|Launch|EmbeddedFile|RichMedia|OpenAction|AA)\b~i',$bytes))throw new ApiException('PDF inválido ou com conteúdo ativo. Envie uma imagem ou um PDF simples.',422);
        }else{
            $image=@getimagesize($f['tmp_name']);if(!$image||$image[0]>15000||$image[1]>15000||$image['mime']!==$mime)throw new ApiException('A imagem não pôde ser validada ou excede as dimensões permitidas.',422);
        }
        $vehicleId=$kind==='vehicle'?Validation::uuid($v['vehicle_id']??''):null;
        if($vehicleId){$vehicle=$this->db->call('/rest/v1/vehicles?id=eq.'.$vehicleId.'&select=id,driver_id','GET',null,$this->token());if(empty($vehicle[0])||$vehicle[0]['driver_id']!==$u['id'])throw new ApiException('Veículo não autorizado.',403);}
        $path=$u['id'].'/'.bin2hex(random_bytes(20)).'.'.$ext;
        $this->db->call('/storage/v1/object/movee-documents/'.$path,'POST',$bytes,null,true,['Content-Type'=>$mime,'x-upsert'=>'false'],true);
        try{
            $r=$this->db->call('/rest/v1/documents','POST',['user_id'=>$u['id'],'vehicle_id'=>$vehicleId,'kind'=>$kind,'storage_path'=>$path,'mime_type'=>$mime,'size_bytes'=>$size],$this->token(),false,['Prefer'=>'return=representation']);return $r[0]??$r;
        }catch(\Throwable $e){try{$this->db->call('/storage/v1/object/movee-documents','DELETE',['prefixes'=>[$path]],null,true);}catch(\Throwable $ignore){}throw $e;}
    }
    private function document(array $v): array {
        $this->user();$id=Validation::uuid($v['id']??'');$path=$this->db->rpc('log_document_access',['p_document_id'=>$id],$this->token());
        if(!is_string($path)||$path==='')throw new ApiException('Documento não encontrado ou sem permissão.',404);$r=$this->db->call('/storage/v1/object/sign/movee-documents/'.implode('/',array_map('rawurlencode',explode('/',$path))),'POST',['expiresIn'=>60],null,true);
        $signed=$r['signedURL']??$r['signedUrl']??'';if($signed===''||!str_starts_with($signed,'/'))throw new ApiException('Não foi possível autorizar o documento.',502);
        return ['url'=>rtrim($this->config->get('SUPABASE_URL'),'/').'/storage/v1'.$signed,'expires_in'=>60];
    }
    private function payment(array $v): mixed {
        Security::rate($this->config,'payment',15,900);$u=$this->user();$id=Validation::uuid($v['delivery_id']??'');$method=$v['method']??'';
        if(!in_array($method,['pix','credit','debit'],true))throw new ApiException('Forma de pagamento inválida.',422);
        $rows=$this->db->call('/rest/v1/deliveries?id=eq.'.$id.'&select=id,code,client_id,price,status','GET',null,$this->token());$d=$rows[0]??null;
        if(!$d||$d['client_id']!==$u['id'])throw new ApiException('Entrega não encontrada.',404);
        if(!in_array($d['status'],['awaiting_payment','awaiting_driver'],true))throw new ApiException('Esta entrega não pode receber um pagamento.',422);
        $mode=$this->config->get('PAYMENT_MODE','demo');
        if($mode==='demo')return $this->db->rpc('record_demo_payment',['p_delivery_id'=>$id,'p_method'=>$method],'',true);
        if($mode!=='live'||$this->config->get('MERCADOPAGO_ACCESS_TOKEN')===''||$this->config->get('MERCADOPAGO_WEBHOOK_SECRET')==='')throw new ApiException('O provedor de pagamento real não foi configurado.',503,'payment_not_configured');
        if(!str_starts_with($this->config->url(),'https://'))throw new ApiException('Pagamentos reais exigem APP_URL com HTTPS público.',503);
        $existing=$this->db->call('/rest/v1/payments?delivery_id=eq.'.$id.'&status=eq.confirmed&select=*','GET',null,$this->token());if($existing)return $existing[0];
        $exclude=match($method){'pix'=>[['id'=>'credit_card'],['id'=>'debit_card'],['id'=>'ticket']],'credit'=>[['id'=>'debit_card'],['id'=>'bank_transfer'],['id'=>'ticket']],'debit'=>[['id'=>'credit_card'],['id'=>'bank_transfer'],['id'=>'ticket']]};
        $body=['items'=>[['id'=>$id,'title'=>'Entrega Movee '.$d['code'],'quantity'=>1,'currency_id'=>'BRL','unit_price'=>(float)$d['price']]],'external_reference'=>$id,'notification_url'=>$this->config->url().'/api/webhook.php','back_urls'=>['success'=>$this->config->url().'/pagamentos.html','pending'=>$this->config->url().'/pagamentos.html','failure'=>$this->config->url().'/pagamento.html?id='.$id],'auto_return'=>'approved','payment_methods'=>['excluded_payment_types'=>$exclude],'metadata'=>['movee_delivery_id'=>$id]];
        $r=Http::request('POST','https://api.mercadopago.com/checkout/preferences',['Authorization'=>'Bearer '.$this->config->get('MERCADOPAGO_ACCESS_TOKEN'),'X-Idempotency-Key'=>'movee-'.$id.'-'.$method],$body);
        if($r['status']<200||$r['status']>=300||empty($r['data']['id'])||empty($r['data']['init_point']))throw new ApiException('O provedor não conseguiu abrir o pagamento. Tente novamente.',502);
        $checkout=$r['data']['init_point'];$host=parse_url($checkout,PHP_URL_HOST);
        if(!is_string($host)||!preg_match('/(^|\.)mercadopago\.(com|com\.br)$/D',$host)||!str_starts_with($checkout,'https://'))throw new ApiException('O provedor retornou uma URL inválida.',502);
        $p=$this->db->rpc('prepare_provider_payment',['p_delivery_id'=>$id,'p_method'=>$method,'p_preference_id'=>$r['data']['id']],'',true);
        return (is_array($p)?$p:[])+['checkout_url'=>$checkout,'is_demo'=>false];
    }
}
