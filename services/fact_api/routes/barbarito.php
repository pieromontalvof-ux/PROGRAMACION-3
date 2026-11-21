<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\BarbaritoController;

Route::prefix('barbarito')->middleware(\App\Http\Middleware\BarbaritoAccess::class)->group(function () {
    Route::get('/health', fn () => ['servicio' => 'fact_api', 'modo' => 'DEMO']);
    Route::post('/documents', [BarbaritoController::class, 'store']);
    Route::get('/documents/{id}', [BarbaritoController::class, 'show'])->whereUuid('id');
    Route::get('/documents/{id}/pdf', [BarbaritoController::class, 'pdf'])->whereUuid('id');
});
