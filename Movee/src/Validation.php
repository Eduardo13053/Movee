<?php
declare(strict_types=1);
namespace Movee;
final class Validation {
    public static function digits(mixed $v): string { return preg_replace('/\D/', '', is_scalar($v) ? (string)$v : '') ?? ''; }
    public static function cpf(mixed $v): bool {
        if (!is_scalar($v) || preg_match('/[^0-9.\-\s]/', (string)$v)) return false;
        $s = self::digits($v);
        if (strlen($s) !== 11 || preg_match('/^(\d)\1{10}$/D', $s)) return false;
        for ($i = 9; $i < 11; $i++) { $sum = 0; for ($j = 0; $j < $i; $j++) $sum += (int)$s[$j] * ($i + 1 - $j); $remainder = $sum % 11; $d = $remainder < 2 ? 0 : 11 - $remainder; if ((int)$s[$i] !== $d) return false; }
        return true;
    }
    public static function cnpj(mixed $v): bool {
        if (!is_scalar($v) || preg_match('/[^A-Za-z0-9.\/\-\s]/', (string)$v)) return false;
        $s = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)$v) ?? '');
        if (!preg_match('/^[A-Z0-9]{12}[0-9]{2}$/D', $s) || preg_match('/^(.)\\1{13}$/D', $s)) return false;
        foreach ([[5,4,3,2,9,8,7,6,5,4,3,2], [6,5,4,3,2,9,8,7,6,5,4,3,2]] as $n=>$weights) {
            $sum=0; foreach($weights as $i=>$w) $sum+=(ord($s[$i])-48)*$w;
            $r=$sum%11; if((int)$s[12+$n]!==($r<2?0:11-$r))return false;
        }
        return true;
    }
    public static function taxId(mixed $v, bool $seller = false): string {
        if (!self::cpf($v) && !($seller && self::cnpj($v))) throw new ApiException($seller ? 'CPF ou CNPJ inválido.' : 'CPF inválido.',422);
        return strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)$v) ?? '');
    }
    public static function phone(mixed $v): bool {
        if(!is_scalar($v)||preg_match('/[^0-9+() .\-]/',(string)$v))return false;
        $s=self::digits($v);if(!preg_match('/^[1-9]{2}(?:[2-5]\d{7}|9\d{8})$/D',$s))return false;
        return in_array(substr($s,0,2),['11','12','13','14','15','16','17','18','19','21','22','24','27','28','31','32','33','34','35','37','38','41','42','43','44','45','46','47','48','49','51','53','54','55','61','62','63','64','65','66','67','68','69','71','73','74','75','77','79','81','82','83','84','85','86','87','88','89','91','92','93','94','95','96','97','98','99'],true);
    }
    public static function e164(mixed $v): string {
        if(!is_scalar($v)||preg_match('/[^0-9+() .\-]/',(string)$v))throw new ApiException('Telefone contém caracteres inválidos.',422);
        $s = self::digits($v); if (str_starts_with($s, '55') && in_array(strlen($s), [12, 13], true)) $s = substr($s, 2);
        if (!self::phone($s)) throw new ApiException('Informe um telefone brasileiro válido com DDD.', 422);
        return '+55' . $s;
    }
    public static function uuid(mixed $v): string {
        if (!is_string($v) || !preg_match('/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/Di', $v)) throw new ApiException('Identificador inválido.', 422);
        return $v;
    }
    public static function text(mixed $v, int $min, int $max, string $label): string {
        if (!is_scalar($v)) throw new ApiException("$label inválido.", 422);
        $v = trim((string)$v); $len = function_exists('mb_strlen') ? mb_strlen($v) : strlen($v);
        if ($len < $min || $len > $max || preg_match('/[\x00-\x08\x0b\x0c\x0e-\x1f]/', $v)) throw new ApiException("$label deve ter de $min a $max caracteres.", 422);
        return $v;
    }
    public static function password(mixed $v): string {
        if (!is_string($v) || strlen($v) < 10 || strlen($v) > 128 || !preg_match('/[a-z]/', $v) || !preg_match('/[A-Z]/', $v) || !preg_match('/[0-9]/', $v) || !preg_match('/[^a-zA-Z0-9]/', $v) || preg_match('/\s/', $v)) throw new ApiException('Use uma senha de 10 a 128 caracteres, com maiúscula, minúscula, número e símbolo, sem espaços.', 422);
        return $v;
    }
    public static function fullName(mixed $v): string {
        $v = self::text($v, 4, 140, 'Nome');
        if (!preg_match('/^\p{L}[\p{L}\p{M}\'’-]*(?:\s+\p{L}[\p{L}\p{M}\'’-]*)+$/uD', $v)) throw new ApiException('Informe nome e sobrenome válidos.', 422);
        if (!function_exists('mb_convert_case')) return $v;
        $v = mb_convert_case(preg_replace('/\s+/u', ' ', $v), MB_CASE_TITLE, 'UTF-8');
        return preg_replace_callback('/\s(Da|Das|De|Do|Dos|E)\s/u', static fn($m) => strtolower($m[0]), $v) ?? $v;
    }
    public static function email(mixed $v): string { if (!is_string($v) || strlen($v)>254 || !filter_var(trim($v), FILTER_VALIDATE_EMAIL)) throw new ApiException('Informe um e-mail válido.', 422); return strtolower(trim($v)); }
    public static function birth(mixed $v): string {
        if (!is_string($v) || !preg_match('/^\d{4}-\d{2}-\d{2}$/D', $v)) throw new ApiException('Data de nascimento inválida.', 422);
        $d = \DateTimeImmutable::createFromFormat('!Y-m-d', $v); $today = new \DateTimeImmutable('today');
        if (!$d || $d->format('Y-m-d') !== $v || $d > $today->modify('-18 years') || $d < $today->modify('-120 years')) throw new ApiException('É necessário ter pelo menos 18 anos. Confira a data de nascimento.', 422);
        return $v;
    }
}
