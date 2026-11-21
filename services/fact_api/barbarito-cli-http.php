<?php
/** Local Windows HTTP adapter; production should use PHP-FPM with a web server. */
require __DIR__.'/vendor/autoload.php';
$input=json_decode(stream_get_contents(STDIN),true,512,JSON_THROW_ON_ERROR);
$app=require __DIR__.'/bootstrap/app.php';
$server=['HTTP_ACCEPT'=>'application/json','CONTENT_TYPE'=>'application/json',
    'HTTP_AUTHORIZATION'=>$input['authorization'],'HTTP_IDEMPOTENCY_KEY'=>$input['key'],
    'HTTP_X_REQUEST_ID'=>$input['key'],'SERVER_NAME'=>'127.0.0.1','SERVER_PORT'=>'8091'];
$request=Illuminate\Http\Request::create($input['uri'],$input['method'],[],[],[],$server,$input['body']);
$kernel=$app->make(Illuminate\Contracts\Http\Kernel::class);
$response=$kernel->handle($request);
ob_start();$response->sendContent();$bytes=ob_get_clean();
echo json_encode(['status'=>$response->getStatusCode(),'type'=>$response->headers->get('Content-Type'),
    'body'=>base64_encode($bytes)],JSON_THROW_ON_ERROR);
$kernel->terminate($request,$response);
