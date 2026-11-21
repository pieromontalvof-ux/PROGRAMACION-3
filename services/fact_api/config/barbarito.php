<?php
return [
    // Do not expose upstream public setup routes by changing a .env flag.
    'bridge_only' => true,
    'demo_only' => env('BARBARITO_DEMO_ONLY', true),
    'token' => env('BARBARITO_TOKEN', ''),
];
