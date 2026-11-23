<?php
// Local regression check using the actual native service. All fixture writes roll back.
require __DIR__.'/../vendor/autoload.php';
$app=require __DIR__.'/../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
use App\Models\{Company,Branch};
use App\Services\DocumentService;
use Illuminate\Support\Facades\DB;

if (!config('barbarito.demo_only')) throw new RuntimeException('DEMO required.');
DB::beginTransaction();
try {
    $first=Company::where('ruc','00000000000')->firstOrFail();
    $second=$first->replicate();$second->ruc='00000000001';$second->save();
    $clients=[];
    foreach([$first,$second] as $company) {
        $branch=Branch::create(['company_id'=>$company->id,'codigo'=>'SMOKE','nombre'=>'Test rollback',
            'direccion'=>'Prueba','ubigeo'=>'150101','distrito'=>'Lima','provincia'=>'Lima','departamento'=>'Lima']);
        $document=app(DocumentService::class)->createBoleta([
            'company_id'=>$company->id,'branch_id'=>$branch->id,'serie'=>'TS00','fecha_emision'=>'2026-11-21','moneda'=>'PEN',
            'client'=>['tipo_documento'=>'1','numero_documento'=>'00000000','razon_social'=>'Prueba transaccional'],
            'detalles'=>[['cod_producto'=>'TEST','descripcion'=>'Prueba','cantidad'=>1,'unidad'=>'C62',
                'tip_afe_igv'=>'10','mto_valor_unitario'=>13.14,'porcentaje_igv'=>18,
                'precio_incluye_igv'=>true,'mto_total_linea'=>15.50]]]);
        if ((string)$document->mto_imp_venta!=='15.50' || (string)$document->mto_igv!=='2.36') {
            throw new RuntimeException('Tax-inclusive rounding failed.');
        }
        if ($document->client->company_id!==$company->id) throw new RuntimeException('Client scope failed.');
        $clients[]=$document->client_id;
    }
    if ($clients[0]===$clients[1]) throw new RuntimeException('Cross-company identity reused.');
    echo "OK: native tax-inclusive totals and same document in two separate companies.\n";
} finally {
    DB::rollBack();
}
