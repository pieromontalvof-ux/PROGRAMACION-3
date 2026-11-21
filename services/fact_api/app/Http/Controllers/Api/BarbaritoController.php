<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\{Company,Branch,Client,Invoice,Boleta};
use App\Services\BarbaritoPdfService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB,Storage};

class BarbaritoController extends Controller {
    private function responseData($row): array {
        return ['id'=>$row->id,'numero'=>$row->number,'estado'=>$row->state,'payload_hash'=>$row->payload_hash];
    }
    public function show(string $id) {
        $row=DB::table('barbarito_documents')->find($id);
        abort_unless($row,404);
        return $this->responseData($row);
    }
    public function store(Request $request) {
        $request->validate([
            'version'=>'required|in:1','origen'=>'required|in:VENTA,COMPRA',
            'referencia'=>'required|string|max:40','id_local'=>'required|integer|min:1',
            'empresa.nombre'=>'required|string|max:200','tipo'=>'required|in:01,03',
            'serie'=>'required|string|max:10','fecha'=>'required|date_format:Y-m-d',
            'moneda'=>'required|in:PEN,USD','tercero.nombre'=>'required|string|max:200',
            'tercero.documento'=>'present|string|max:30','tercero.tipo'=>'required|in:0,1,4,6,7',
            'lineas'=>'required|array|min:1|max:500','lineas.*.nombre'=>'required|string|max:200',
            'lineas.*.codigo'=>'required|string|max:30','lineas.*.cantidad'=>'required|numeric|gt:0',
            'lineas.*.unidad'=>'required|string|max:20','lineas.*.afectacion'=>'required|string|max:30',
            'lineas.*.subtotal'=>'required|numeric|min:0','lineas.*.igv'=>'required|numeric|min:0',
            'lineas.*.total'=>'required|numeric|min:0','subtotal'=>'required|numeric|min:0',
            'igv'=>'required|numeric|min:0','total'=>'required|numeric|min:0',
        ]);
        $id=(string)$request->header('Idempotency-Key');
        abort_unless(preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i',$id),422);
        $payload=$request->json()->all();
        $canonical=$this->canonical($payload);
        $hash=hash('sha256',json_encode($canonical,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
        $cents=fn($v)=>(int)round((float)$v*100);
        foreach(['subtotal','igv','total'] as $field) {
            abort_unless(array_sum(array_map(fn($l)=>$cents($l[$field]),$payload['lineas']))===$cents($payload[$field]),422);
        }
        foreach($payload['lineas'] as $line) {
            abort_unless($cents($line['subtotal'])+$cents($line['igv'])===$cents($line['total']),422);
        }
        return DB::transaction(function () use($id,$payload,$hash) {
            // Company-wide lock serializes series allocation, retries and first-time setup.
            DB::select("SELECT pg_advisory_xact_lock(hashtext('barbarito-demo-documents'))");
            $existing=DB::table('barbarito_documents')->find($id);
            if($existing) {
                abort_unless(hash_equals($existing->payload_hash,$hash),409,'Identificador usado con otros datos.');
                return $this->responseData($existing);
            }
            $company=Company::firstOrCreate(['ruc'=>'00000000000'],[
                'razon_social'=>$payload['empresa']['nombre'],'nombre_comercial'=>$payload['empresa']['nombre'],
                'direccion'=>'Entorno de pruebas','ubigeo'=>'150101','distrito'=>'Lima','provincia'=>'Lima','departamento'=>'Lima',
                'usuario_sol'=>'NO_CONFIGURADO','clave_sol'=>'NO_CONFIGURADO',
                'endpoint_beta'=>'','endpoint_produccion'=>'','modo_produccion'=>false]);
            $branch=Branch::firstOrCreate(['company_id'=>$company->id,'codigo'=>(string)$payload['id_local']],[
                'nombre'=>'Local '.$payload['id_local'],'direccion'=>'Entorno de pruebas','ubigeo'=>'150101',
                'distrito'=>'Lima','provincia'=>'Lima','departamento'=>'Lima']);
            $client=Client::firstOrCreate(['company_id'=>$company->id,'tipo_documento'=>$payload['tercero']['tipo'],
                'numero_documento'=>$payload['tercero']['documento'] ?: 'SIN_DOCUMENTO'],
                ['razon_social'=>$payload['tercero']['nombre'],'direccion'=>$payload['tercero']['direccion']??'']);
            DB::table('clients')->where('id',$client->id)->update([
                $payload['origen']==='COMPRA'?'barbarito_supplier':'barbarito_customer'=>true]);
            $native=null;$nativeType=null;
            if($payload['origen']==='VENTA') {
                $class=$payload['tipo']==='01'?Invoice::class:Boleta::class;
                $nativeType=$payload['tipo']==='01'?'invoice':'boleta';
                $seq=(int)$class::where('company_id',$company->id)->where('serie',$payload['serie'])->max('correlativo')+1;
                abort_if($seq>99999999,422);
                $details=array_map(fn($l)=>['cod_producto'=>$l['codigo'],'descripcion'=>$l['nombre'],
                    'unidad'=>$l['unidad'],'cantidad'=>$l['cantidad'],'mto_valor_unitario'=>(float)$l['subtotal']/(float)$l['cantidad'],
                    'mto_valor_venta'=>$l['subtotal'],'igv'=>$l['igv'],'total_impuestos'=>$l['igv'],
                    'mto_precio_unitario'=>(float)$l['total']/(float)$l['cantidad']],$payload['lineas']);
                $native=$class::create(['company_id'=>$company->id,'branch_id'=>$branch->id,'client_id'=>$client->id,
                    'tipo_documento'=>$payload['tipo'],'serie'=>$payload['serie'],'correlativo'=>str_pad($seq,8,'0',STR_PAD_LEFT),
                    'numero_completo'=>$payload['serie'].'-'.str_pad($seq,8,'0',STR_PAD_LEFT),
                    'fecha_emision'=>$payload['fecha'],'moneda'=>$payload['moneda'],'detalles'=>$details,
                    'valor_venta'=>$payload['subtotal'],'sub_total'=>$payload['subtotal'],'mto_igv'=>$payload['igv'],
                    'total_impuestos'=>$payload['igv'],'mto_imp_venta'=>$payload['total'],'estado_sunat'=>'DEMO',
                    'usuario_creacion'=>'barbarito']);
                $number=$native->numero_completo;
            } else {
                abort_unless(isset($payload['numero_proveedor'],$payload['orden_compra']),422);
                $number=$payload['numero_proveedor'];
            }
            DB::table('barbarito_documents')->insert(['id'=>$id,'company_id'=>$company->id,'branch_id'=>$branch->id,
                'origin'=>$payload['origen'],'source_reference'=>$payload['referencia'],
                'native_id'=>$native?->id,'native_type'=>$nativeType,'number'=>$number,'payload_hash'=>$hash,
                'payload'=>json_encode($payload),'state'=>'DEMO_GENERADO','created_at'=>now(),'updated_at'=>now()]);
            return $this->responseData(DB::table('barbarito_documents')->find($id));
        });
    }
    private function canonical($value) {
        if(!is_array($value)) return $value;
        if(!array_is_list($value)) ksort($value);
        foreach($value as &$item) $item=$this->canonical($item);
        return $value;
    }
    public function pdf(Request $request,string $id) {
        $format=$request->query('format','A4');
        abort_unless(in_array($format,['A4','80mm'],true),422);
        return DB::transaction(function () use ($id,$format) {
        DB::select('SELECT pg_advisory_xact_lock(hashtext(?))',['barbarito-pdf:'.$id.':'.$format]);
        $row=DB::table('barbarito_documents')->find($id);abort_unless($row,404);
        $path='barbarito/'.$row->company_id.'/'.$row->branch_id.'/'.$row->origin.'/'.$id.'/'.$format.'.pdf';
        // Private local disk; no storage:link and no user-supplied path.
        $file=DB::table('barbarito_files')->where('document_id',$id)->where('format',$format)->first();
        if(!$file || !Storage::disk('local')->exists($path)) {
            $bytes=app(BarbaritoPdfService::class)->renderSnapshot(json_decode($row->payload,true),$row->number,$format);
            $temporary=$path.'.'.bin2hex(random_bytes(8)).'.tmp';
            Storage::disk('local')->put($temporary,$bytes);
            Storage::disk('local')->move($temporary,$path);
            DB::table('barbarito_files')->updateOrInsert(['document_id'=>$id,'format'=>$format],
                ['path'=>$path,'sha256'=>hash('sha256',$bytes),'bytes'=>strlen($bytes)]);
        }
        return Storage::disk('local')->download($path,$row->number.'_'.$format.'.pdf',[
            'Cache-Control'=>'private, no-store','X-Content-Type-Options'=>'nosniff']);
        });
    }
}
