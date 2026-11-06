<?php
declare(strict_types=1);
namespace Movee;
final class Config {
    private array $values = [];
    public function __construct(?string $path = null) {
        $path ??= dirname(__DIR__) . '/.env';
        if (is_file($path)) {
            foreach (file($path, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
                $line = trim($line);
                if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) continue;
                [$key, $value] = explode('=', $line, 2);
                $key = trim($key); $value = trim($value);
                if (!preg_match('/^[A-Z][A-Z0-9_]*$/D', $key)) continue;
                if (strlen($value) > 1 && in_array($value[0], ['"', "'"], true) && $value[-1] === $value[0]) $value = substr($value, 1, -1);
                $this->values[$key] = $value;
            }
        }
    }
    public function get(string $key, string $default = ''): string {
        $value = getenv($key);
        return $value !== false ? $value : ($this->values[$key] ?? $default);
    }
    public function bool(string $key, bool $default = false): bool { return filter_var($this->get($key, $default ? 'true' : 'false'), FILTER_VALIDATE_BOOLEAN); }
    public function configured(): bool { return $this->get('SUPABASE_URL') !== '' && $this->get('SUPABASE_PUBLISHABLE_KEY') !== '' && strlen($this->get('APP_KEY')) >= 32; }
    public function url(): string { return rtrim($this->get('APP_URL', 'http://127.0.0.1:8080'), '/'); }
}
