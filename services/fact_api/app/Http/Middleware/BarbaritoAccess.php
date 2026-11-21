<?php
namespace App\Http\Middleware;

class BarbaritoAccess {
    public function handle($request, \Closure $next) {
        $token=(string)config('barbarito.token');
        abort_unless(strlen($token)>=32 && hash_equals($token,(string)$request->bearerToken()),401);
        abort_unless(config('barbarito.demo_only'),503,'Este puente solo admite pruebas.');
        return $next($request);
    }
}
