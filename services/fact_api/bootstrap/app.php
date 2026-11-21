<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Idempotency hashes describe exact JSON values, including empty documents.
        $middleware->convertEmptyStringsToNull(except: [fn ($request) => $request->is('api/barbarito/*')]);
        $middleware->trimStrings(except: [fn ($request) => $request->is('api/barbarito/*')]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
