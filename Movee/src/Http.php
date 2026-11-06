<?php
declare(strict_types=1);
namespace Movee;
final class ApiException extends \RuntimeException {
    public function __construct(string $message, public readonly int $status = 400, public readonly string $errorCode = 'request_error') { parent::__construct($message); }
}
final class Http {
    /** No automatic redirects: authorization headers must never cross hosts. */
    public static function request(string $method, string $url, array $headers = [], mixed $body = null, bool $raw = false): array {
        if (!str_starts_with($url, 'https://')) throw new ApiException('O serviço externo exige HTTPS.', 503);
        $payload = $raw ? (string)$body : ($body === null ? '' : json_encode($body, JSON_THROW_ON_ERROR));
        $headers['Accept'] ??= 'application/json';
        if (!$raw && $body !== null) $headers['Content-Type'] = 'application/json';
        $headerLines = []; foreach ($headers as $key => $value) $headerLines[] = $key . ': ' . $value;
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST=>$method,CURLOPT_HTTPHEADER=>$headerLines,CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>25,CURLOPT_CONNECTTIMEOUT=>8,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_PROTOCOLS=>CURLPROTO_HTTPS,CURLOPT_MAXREDIRS=>0]);
            if ($body !== null) curl_setopt($ch,CURLOPT_POSTFIELDS,$payload);
            $response = curl_exec($ch); $status = (int)curl_getinfo($ch,CURLINFO_RESPONSE_CODE); curl_close($ch);
            if ($response === false) throw new ApiException('O serviço externo está indisponível. Tente novamente.', 502, 'upstream_unavailable');
        } else {
            $ctx = stream_context_create(['http'=>['method'=>$method,'header'=>implode("\r\n",$headerLines),'content'=>$payload,'timeout'=>25,'ignore_errors'=>true,'follow_location'=>0],'ssl'=>['verify_peer'=>true,'verify_peer_name'=>true]]);
            $response = @file_get_contents($url,false,$ctx); $status = 0;
            foreach ($http_response_header ?? [] as $h) if (preg_match('/^HTTP\/\S+\s+(\d+)/',$h,$m)) $status=(int)$m[1];
            if ($response === false) throw new ApiException('O serviço externo está indisponível. Tente novamente.',502,'upstream_unavailable');
        }
        $decoded = json_decode($response,true);
        return ['status'=>$status,'data'=>$decoded ?? $response];
    }
}
