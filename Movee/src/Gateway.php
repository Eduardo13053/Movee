<?php
declare(strict_types=1);
namespace Movee;
final class Gateway {
    public static function make(Config $config): Supabase {
        if($config->get('APP_DATA_BACKEND','supabase')==='mongodb'){
            $autoload=dirname(__DIR__).'/vendor/autoload.php';if(is_file($autoload))require_once $autoload;
            $file=__DIR__.'/MongoGateway.php';if(is_file($file))require_once $file;
            if(!class_exists(MongoGateway::class))throw new ApiException('O adaptador MongoDB não foi instalado. Consulte docs/MONGODB.md.',503,'mongodb_not_configured');
            return new MongoGateway($config);
        }
        return new Supabase($config);
    }
}
