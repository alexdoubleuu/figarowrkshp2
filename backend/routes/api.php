<?php

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    $db = false;
    $redis = false;

    try {
        DB::connection()->getPdo();
        $db = true;
    } catch (Throwable) {
        //
    }

    try {
        Redis::connection()->ping();
        $redis = true;
    } catch (Throwable) {
        //
    }

    return response()->json([
        'status' => 'ok',
        'db' => $db,
        'redis' => $redis,
    ]);
});
