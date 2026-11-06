'use strict';
(async()=>{
 const M=Movee,page=document.body.dataset.page;
 // Link secrets stay in memory and leave the URL before session or asset-driven requests.
 const query=new URLSearchParams(location.search),rawLinkToken=query.get('token_hash');
 const fragmentCredentials=/(?:access_token|refresh_token|token_hash)=/i.test(location.hash);
 const originalType=query.get('type');
 let linkToken=rawLinkToken;
 if(page==='verify'&&(rawLinkToken!==null||fragmentCredentials)){
  const clean=new URLSearchParams();
  if(originalType==='recovery')clean.set('type','recovery');
  if(query.has('next'))clean.set('next',M.safeNext(query.get('next')));
  history.replaceState(null,'',location.pathname+(clean.size?'?'+clean.toString():''));
 }
 const s=await M.init();
 const {digits,validCPF,validCNPJ,validPhone,strong,capital}=M.validators;
 function busy(form,value,label){const b=form.querySelector('[type=submit]');if(!b)return;if(value){b.dataset.label=b.innerHTML;b.disabled=true;b.textContent=label||'Aguarde…';}else{b.disabled=false;b.innerHTML=b.dataset.label||'Continuar';}}
 function bindSubmit(id,handler){const f=document.getElementById(id);if(!f)return;f.addEventListener('submit',async ev=>{ev.preventDefault();if(!f.reportValidity())return;busy(f,true);try{await handler(f);}catch(e){M.notice(e.message,'error');}finally{busy(f,false);}});}
 const next=M.safeNext(query.get('next'));
 const remember=value=>{try{sessionStorage.setItem('movee.verification',JSON.stringify(value));}catch{/* link confirmation works without browser storage */}};
 if(page==='login'){
  if(next==='admin.html'){document.querySelector('.auth-card h2').textContent='Acesso administrativo';document.querySelector('.auth-card>p').textContent='Entre com uma conta administrativa já aprovada.';}
  bindSubmit('login-form',async f=>{try{await M.api('login',{email:f.email.value.trim(),password:f.password.value});const current=await M.api('session');if(!current.user)throw new Error('Confirme seu e-mail antes de entrar na conta.');const role=current.profile?.role;location.href=next==='painel.html'?(role==='admin'?'admin.html':role==='driver'?'entregador.html':'painel.html'):next;}catch(error){if(error.code==='confirmation_required'||/confirme.*e-mail|e-mail.*confirmad/i.test(error.message)){remember({email:f.email.value.trim(),channel:'email',next});const help=document.getElementById('login-confirmation-help');if(help)help.hidden=false;const link=document.getElementById('login-confirmation-link');if(link)link.href='verificar.html?next='+encodeURIComponent(next);}throw error;}});
 }
 if(page==='register'){
  const q=new URLSearchParams(location.search).get('tipo');const type=({cliente:'client',entregador:'driver',administrador:'admin',vendedor:'seller'})[q]||'client';
  const labels={client:'cliente',driver:'entregador',admin:'administrador',seller:'vendedor'};
  document.getElementById('register-title').textContent=(type==='admin'?'Solicitar cadastro de ':'Criar conta de ')+labels[type];document.title='Cadastro de '+labels[type]+' — Movee';
  document.querySelectorAll('[data-account]').forEach(a=>{if(a.dataset.account===type)a.setAttribute('aria-current','page');});
  if(type==='driver'){document.getElementById('register-headline').innerHTML='Seu veículo.<br>Novos caminhos.';document.getElementById('register-description').textContent='Cadastre-se para análise e prepare seu perfil para encontrar entregas compatíveis com seu veículo.';document.getElementById('driver-note').hidden=false;}
  if(type==='seller'){document.getElementById('register-headline').innerHTML='Seu negócio.<br>Mais conexões.';document.getElementById('register-description').textContent='Organize as entregas do seu negócio, salve o endereço da loja e acompanhe os pedidos em um só lugar.';document.getElementById('tax-label').textContent='CPF ou CNPJ';document.getElementById('cpf_cnpj').placeholder='CPF ou CNPJ do cadastro';document.getElementById('tax-help').textContent='Aceitamos CPF ou CNPJ válido. Informe o documento do responsável ou da empresa.';document.getElementById('cpf_cnpj').removeAttribute('inputmode');}
  if(type==='admin'){document.getElementById('register-headline').innerHTML='Acesso com<br>responsabilidade.';document.getElementById('register-description').textContent='Solicite acesso administrativo. A aprovação depende da análise dos seus documentos e da sua justificativa.';document.getElementById('admin-justification-field').hidden=false;document.getElementById('justification').required=true;}
  const f=document.getElementById('register-form');let step=0;
  f.full_name.addEventListener('blur',()=>f.full_name.value=capital(f.full_name.value));
  const today=new Date();today.setMinutes(today.getMinutes()-today.getTimezoneOffset());const oldest=new Date(today),youngest=new Date(today);oldest.setFullYear(oldest.getFullYear()-120);youngest.setFullYear(youngest.getFullYear()-18);f.birth_date.max=youngest.toISOString().slice(0,10);f.birth_date.min=oldest.toISOString().slice(0,10);
  f.phone.addEventListener('input',()=>{const raw=digits(f.phone.value);const d=(raw.startsWith('55')&&raw.length>11?raw.slice(2):raw).slice(0,11);f.phone.value=d.length>2?'('+d.slice(0,2)+') '+(d.length>7?d.slice(2,-4)+'-'+d.slice(-4):d.slice(2)):d;});
  f.password.addEventListener('input',()=>{const v=f.password.value;const r=[v.length>=10,/[A-Z]/.test(v)&&/[a-z]/.test(v),/\d/.test(v),/[^A-Za-z0-9\s]/.test(v)];document.querySelectorAll('.requirements li').forEach((el,i)=>el.classList.toggle('met',r[i]));});
  if(!s.sms_enabled){document.getElementById('sms-option').disabled=true;document.getElementById('sms-help').textContent='A confirmação por SMS estará disponível quando o serviço for configurado. Por enquanto, use o e-mail.';}
  f.querySelectorAll('[name=channel]').forEach(r=>r.addEventListener('change',()=>{document.getElementById('sms-help').textContent=f.channel.value==='sms'?'Por segurança, confirme primeiro o e-mail de acesso. Depois de entrar, envie o código adicional por SMS para confirmar o telefone.':'Você receberá um link de confirmação no e-mail informado. O código da mensagem também pode ser utilizado.';}));
  function validate(current){const section=f.querySelector(`[data-register-step="${current}"]`);for(const input of section.querySelectorAll('input,textarea,select')){input.setCustomValidity('');if(!input.reportValidity())return false;}
   const errors=current===0?[[f.full_name,M.validators.validName(f.full_name.value),'Informe nome e sobrenome válidos.'],[f.cpf_cnpj,validCPF(f.cpf_cnpj.value)||(type==='seller'&&validCNPJ(f.cpf_cnpj.value)),'Informe um '+(type==='seller'?'CPF ou CNPJ':'CPF')+' válido.'],[f.phone,validPhone(f.phone.value),'Informe um telefone brasileiro válido, com DDD.']]:current===1?[[f.password,strong(f.password.value),'Use 10 caracteres ou mais, incluindo maiúscula, minúscula, número e símbolo.'],[f.password_confirm,f.password.value===f.password_confirm.value,'As senhas precisam ser iguais.']]:[];
   for(const [input,valid,message]of errors){if(!valid){input.setCustomValidity(message);input.reportValidity();input.addEventListener('input',()=>input.setCustomValidity(''),{once:true});return false;}}return true;
  }
  function show(){f.querySelectorAll('[data-register-step]').forEach((el,i)=>el.hidden=i!==step);document.querySelectorAll('#register-steps li').forEach((el,i)=>{el.classList.toggle('active',i===step);el.classList.toggle('done',i<step);if(i===step)el.setAttribute('aria-current','step');else el.removeAttribute('aria-current');});if(step===2){document.getElementById('registration-review').innerHTML=`<strong>${M.escape(capital(f.full_name.value))}</strong><br>${M.escape(f.email.value)}<br>${M.escape(f.phone.value)}<br><span class="muted">Conta de ${labels[type]} · ${f.channel.value==='sms'?'E-mail + confirmação por SMS':'Confirmação por e-mail'}</span>`;}}
  f.querySelectorAll('[data-next-step]').forEach(b=>b.addEventListener('click',()=>{if(validate(step)){step++;show();}}));f.querySelectorAll('[data-prev-step]').forEach(b=>b.addEventListener('click',()=>{step--;show();}));
  f.addEventListener('submit',async ev=>{ev.preventDefault();if(step!==2||!f.terms.reportValidity())return;if(!s.configured){M.notice('O servidor ainda precisa ser conectado ao Supabase. Siga as instruções de configuração do projeto.','warning');return;}busy(f,true,'Criando sua conta…');try{const response=await M.api('register',{email:f.email.value.trim(),password:f.password.value,channel:f.channel.value,phone:f.phone.value,metadata:{full_name:capital(f.full_name.value),cpf_cnpj:f.cpf_cnpj.value.toUpperCase().replace(/[^A-Z0-9]/g,''),phone:f.phone.value,birth_date:f.birth_date.value,requested_role:type,terms:true}});remember({email:f.email.value.trim(),phone:f.phone.value,channel:f.channel.value,...(query.has('next')?{next}:{} )});if(type==='admin')try{sessionStorage.setItem('movee.adminJustification',f.justification.value.trim());}catch{/* justification can be completed in the authenticated profile */}location.href='verificar.html'+(query.has('next')?'?next='+encodeURIComponent(next):'');}catch(e){M.notice(e.message,'error');}finally{busy(f,false);}});
 }
 if(page==='recover')bindSubmit('recover-form',async f=>{await M.api('recover',{email:f.email.value.trim()});remember({email:f.email.value.trim(),channel:'email',...(query.has('next')?{next}:{})});const link=document.getElementById('recover-verification-link');if(link){link.hidden=false;link.href='verificar.html?type=recovery'+(query.has('next')?'&next='+encodeURIComponent(next):'');}M.notice('Se houver uma conta elegível, enviaremos um link e um código de recuperação. Confira também a pasta de spam.','success');});
 if(page==='verify'){
  let pending={};try{pending=JSON.parse(sessionStorage.getItem('movee.verification')||'{}');if(!pending||typeof pending!=='object'||Array.isArray(pending))pending={};}catch{/* another device or storage unavailable */}
  const f=document.getElementById('verify-form'),type=originalType==='recovery'?'recovery':'signup';
  const continuation=(query.has('next')||pending.next)?M.safeNext(query.get('next')||pending.next):'perfil.html';
  const linkPanel=document.getElementById('email-link-panel'),linkButton=document.getElementById('confirm-email-link');
  const success=document.getElementById('confirmation-success');
  f.email.value=pending.email||s.user?.email||'';f.phone.value=pending.phone||s.profile?.phone||'';
  const validLink=typeof linkToken==='string'&&/^[A-Za-z0-9_-]{40,128}$/.test(linkToken)&&(!originalType||['signup','recovery'].includes(originalType));
  function showCode(){f.hidden=false;f.email.focus();}
  function afterVerified(result,channel){
   if(!result?.user)throw new Error('A confirmação não retornou uma sessão válida. Tente entrar após confirmar o e-mail.');
   const notice=document.getElementById('notice');notice.hidden=true;notice.textContent='';
   M.session=result;Object.assign(s,result);
   f.hidden=true;linkPanel.hidden=true;success.hidden=false;
   const title=document.getElementById('confirmation-success-title'),description=document.getElementById('confirmation-success-description'),go=document.getElementById('confirmation-continue');
   if(type==='recovery'){
    title.textContent='Seu acesso foi confirmado.';description.textContent='Agora escolha uma nova senha para sua conta.';
    go.hidden=true;document.getElementById('reset-form').hidden=false;
    document.getElementById('new-password').focus();return;
   }
   const needsPhone=channel==='email'&&s.sms_enabled&&(pending.channel==='sms'||s.profile?.verification_channel==='sms')&&!s.user?.phone_confirmed;
   title.textContent=channel==='sms'?'Telefone confirmado.':'E-mail confirmado!';
   description.textContent=needsPhone?'Seu e-mail está confirmado. Agora conclua a confirmação adicional do telefone por SMS.':channel==='sms'?'Seu telefone foi confirmado. Continue para concluir os dados da sua conta.':'Seu e-mail foi confirmado e sua conta está pronta para concluir o cadastro.';
   go.hidden=false;go.textContent=needsPhone?'Confirmar meu telefone':'Continuar para minha conta';
   go.href=needsPhone?'verificar.html?channel=sms&next='+encodeURIComponent(continuation):continuation;
   if(!needsPhone)try{sessionStorage.removeItem('movee.verification');}catch{/* no retained verification state */}
   success.focus();
  }
  if(type==='recovery'){
   document.getElementById('verify-title').textContent='Recupere seu acesso.';
   document.getElementById('verify-description').textContent='Abra o link recebido por e-mail ou informe o código de recuperação para escolher uma nova senha.';
   document.getElementById('verify-sms-option').disabled=true;
   linkButton.textContent='Confirmar recuperação';
  }
  if(!s.user||!s.sms_enabled)document.getElementById('verify-sms-option').disabled=true;
  const change=()=>{const sms=f.channel.value==='sms';document.getElementById('verify-email-field').hidden=sms;document.getElementById('verify-phone-field').hidden=!sms;f.email.required=!sms;f.phone.required=sms;document.getElementById('verify-description').textContent=sms?'Informe seu telefone e solicite o código por SMS. Depois, confirme o código recebido.':type==='recovery'?'Abra o link de recuperação recebido por e-mail ou digite o código da mensagem.':'Abra seu e-mail e clique em “Confirmar meu e-mail”. Se preferir, informe aqui o código da mensagem.';};
  f.channel.addEventListener('change',change);
  if(s.user&&s.sms_enabled&&(query.get('channel')==='sms'||pending.channel==='sms')){f.channel.value='sms';change();}
  else change();
  if(validLink){
   f.hidden=true;linkPanel.hidden=false;document.getElementById('verify-title').textContent=type==='recovery'?'Confirme a recuperação.':'Confirme seu e-mail.';
   document.getElementById('verify-description').textContent=type==='recovery'?'Você abriu o link do e-mail. Confirme abaixo para definir uma nova senha.':'Você abriu o link do e-mail. Clique abaixo para confirmar seu endereço e liberar o acesso à sua conta.';
  }else if(rawLinkToken!==null||fragmentCredentials){
   linkToken=null;M.notice(fragmentCredentials?'Este formato de link não é aceito. Solicite um novo e-mail de confirmação.':'Este link de confirmação é inválido. Solicite outro e-mail ou use o código da mensagem.','error');
  }
  document.getElementById('use-confirmation-code').addEventListener('click',showCode);
  linkButton.addEventListener('click',async()=>{
   if(!linkToken)return;linkButton.disabled=true;
   try{const result=await M.api('verify',{channel:'email',type,token_hash:linkToken});linkToken=null;afterVerified(result,'email');}
   catch(error){f.hidden=false;if(error.code==='confirmation_invalid'){linkToken=null;linkPanel.hidden=true;}M.notice(error.code==='confirmation_invalid'?'Este link é inválido, expirou ou já foi utilizado. Solicite outro e-mail ou entre se já confirmou sua conta.':error.message,'error');}
   finally{linkButton.disabled=false;}
  });
  bindSubmit('verify-form',async()=>{const result=await M.api('verify',{channel:f.channel.value,email:f.email.value.trim(),phone:f.phone.value,token:f.token.value.trim(),type});afterVerified(result,f.channel.value);});
  document.getElementById('resend-code').addEventListener('click',async ev=>{
   const sms=f.channel.value==='sms';if(!(sms?f.phone:f.email).reportValidity())return;
   const b=ev.currentTarget;b.disabled=true;
   try{if(type==='recovery')await M.api('recover',{email:f.email.value.trim()});else await M.api('resend',{channel:f.channel.value,email:f.email.value.trim(),phone:f.phone.value});
    remember({email:f.email.value.trim(),phone:f.phone.value,channel:sms?'sms':pending.channel||'email',...(continuation!=='perfil.html'?{next:continuation}:{})});
    M.notice(sms?'Solicitação de SMS enviada. Aguarde o código no telefone informado.':'Se houver uma conta elegível, enviaremos outro e-mail com o link e o código. Confira também a pasta de spam.','success');
   }catch(error){M.notice(error.message,'error');}finally{b.disabled=false;}
  });
  bindSubmit('reset-form',async form=>{const password=document.getElementById('new-password').value;if(!strong(password))throw new Error('Use uma senha com ao menos 10 caracteres, maiúscula, minúscula, número e símbolo.');if(password!==document.getElementById('new-password-confirm').value)throw new Error('As senhas precisam ser iguais.');await M.api('reset_password',{password});M.notice('Sua senha foi atualizada. Entre novamente para continuar.','success');location.href='login.html';});
 }
})();
