<?php
declare(strict_types=1);
require_once __DIR__.'/src/bootstrap.php';
Movee\Security::headers();
$path=parse_url($_SERVER['REQUEST_URI']??'/',PHP_URL_PATH);
if(!is_string($path)){http_response_code(400);exit('Requisição inválida.');}
$path=rawurldecode($path);
if($path==='/verificar.html'){header('Cache-Control: no-store, private');header('Referrer-Policy: no-referrer');}
if(str_contains($path,"\0")||str_contains($path,'\\')||preg_match('~(?:^|/)\.~',$path)){http_response_code(404);exit('Página não encontrada.');}
$base=realpath(__DIR__.'/public');$file=realpath($base.$path);
if($file!==false&&($file===$base||str_starts_with($file,$base.DIRECTORY_SEPARATOR))){
    if(is_dir($file))$file.='/index.html';
    if(is_file($file)){
        // Even development serves public/ only. PHP files execute normally; credentials stay outside docroot.
        if(str_ends_with($file,'.php')){require $file;return true;}
        $ext=strtolower(pathinfo($file,PATHINFO_EXTENSION));$mime=['html'=>'text/html; charset=utf-8','css'=>'text/css; charset=utf-8','js'=>'text/javascript; charset=utf-8','svg'=>'image/svg+xml','png'=>'image/png','jpg'=>'image/jpeg','webp'=>'image/webp','ico'=>'image/x-icon','json'=>'application/json'][$ext]??null;
        if(!$mime){http_response_code(404);exit('Arquivo não encontrado.');}
        header('Content-Type: '.$mime);readfile($file);return true;
    }
}
http_response_code(404);header('Content-Type: text/html; charset=utf-8');echo '<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Página não encontrada · Movee</title><body><h1>Este caminho ainda não existe.</h1><p><a href="/index.html">Voltar para o Movee</a></p></body></html>';
