<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require dirname(__DIR__).'/src/bootstrap.php';
$c = new Movee\Config();
$backend = $c->get('APP_DATA_BACKEND', 'supabase');
$checks = [
    'PHP 8.2 ou superior' => PHP_VERSION_ID >= 80200,
    'Extensão fileinfo' => extension_loaded('fileinfo'),
    'Extensão mbstring' => extension_loaded('mbstring'),
    'Extensão openssl' => extension_loaded('openssl'),
    'Extensão curl' => extension_loaded('curl'),
    'APP_KEY com pelo menos 32 caracteres' => strlen($c->get('APP_KEY')) >= 32,
    'SUPABASE_URL configurada' => (bool) preg_match('~^https://[a-z0-9.-]+$~iD', $c->get('SUPABASE_URL')) && !str_contains($c->get('SUPABASE_URL'),'SEU-PROJETO'),
    'Chave publicável de Auth configurada' => $c->get('SUPABASE_PUBLISHABLE_KEY') !== '',
    'Chave privada de serviço configurada' => $c->get('SUPABASE_SERVICE_ROLE_KEY') !== '',
];
if ($backend === 'mongodb') {
    $checks['Extensão mongodb'] = extension_loaded('mongodb');
    $checks['Extensão bcmath'] = extension_loaded('bcmath');
    $checks['URI MongoDB configurada'] = $c->get('MONGODB_URI') !== '';
}
echo "Movee · verificação local de configuração ($backend)\n";
foreach ($checks as $label => $ok) echo ($ok ? '[OK] ' : '[PENDENTE] ').$label."\n";
echo "Nenhuma credencial foi exibida. Esta checagem não testa conexão, autenticação nem provedores externos.\n";
exit(in_array(false, $checks, true) ? 1 : 0);
