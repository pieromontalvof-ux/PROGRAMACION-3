<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\{Company,Branch,Client,Invoice,Boleta};
use App\Services\BarbaritoPdfService;
use App\Services\{DocumentService,PdfService};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB,Storage};

class BarbaritoController extends Controller {
    private const PDF_TEMPLATE_VERSION='native-v3';
    private function responseData($row): array {
        $payload=json_decode($row->payload,true);
        $class=$row->native_type==='invoice'?Invoice::class:Boleta::class;
        $total=$row->native_id?$class::findOrFail($row->native_id)->mto_imp_venta:$payload['total'];
        return ['id'=>$row->id,'numero'=>$row->number,'estado'=>$row->state,'payload_hash'=>$row->payload_hash,
            'native_type'=>$row->native_type,'native_id'=>$row->native_id,'total'=>number_format((float)$total,2,'.','')];
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
            'lineas.*.tasa_igv'=>'required|numeric|min:0|max:100',
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
                $details=array_map(fn($l)=>['cod_producto'=>$l['codigo'],'descripcion'=>$l['nombre'],
                    'unidad'=>$l['unidad'],'cantidad'=>$l['cantidad'],'mto_valor_unitario'=>(float)$l['subtotal']/(float)$l['cantidad'],
                    'tip_afe_igv'=>match($l['afectacion']) {'GRAVADO'=>'10','EXONERADO'=>'20','INAFECTO'=>'30',default=>abort(422)},
                    'porcentaje_igv'=>$l['tasa_igv']??18,'precio_incluye_igv'=>true,
                    'mto_total_linea'=>$l['total']],$payload['lineas']);
                // Continue any documents created before adopting the native allocator.
                // Company/series numbering is shared across branches in the native schema.
                $latest=(int)$class::where('company_id',$company->id)->where('serie',$payload['serie'])
                    ->selectRaw('COALESCE(MAX(CAST(correlativo AS BIGINT)),0) AS last')->value('last');
                $counter=$branch->correlatives()->firstOrCreate(['tipo_documento'=>$payload['tipo'],'serie'=>$payload['serie']],
                    ['correlativo_actual'=>$latest]);
                if($counter->correlativo_actual<$latest)$counter->update(['correlativo_actual'=>$latest]);
                abort_if(max($latest,$counter->correlativo_actual)>=99999999,422);
                $data=['company_id'=>$company->id,'branch_id'=>$branch->id,'serie'=>$payload['serie'],
                    'client'=>['tipo_documento'=>$client->tipo_documento,'numero_documento'=>$client->numero_documento,
                        'razon_social'=>$payload['tercero']['nombre'],'direccion'=>$payload['tercero']['direccion']??''],
                    'fecha_emision'=>$payload['fecha'],'moneda'=>$payload['moneda'],'detalles'=>$details,
                    'usuario_creacion'=>'barbarito'];
                $service=app(DocumentService::class);
                $native=$payload['tipo']==='01'?$service->createInvoice($data):$service->createBoleta($data);
                abort_unless((int)round($native->mto_imp_venta*100)===(int)round($payload['total']*100),422,'Importe incompatible.');
                abort_unless((int)round($native->valor_venta*100)===(int)round($payload['subtotal']*100)
                    && (int)round($native->mto_igv*100)===(int)round($payload['igv']*100),422,'Desglose de impuestos incompatible.');
                foreach($native->detalles as $index=>$line) {
                    abort_unless((int)round($line['mto_valor_venta']*100)===(int)round($payload['lineas'][$index]['subtotal']*100)
                        && (int)round($line['igv']*100)===(int)round($payload['lineas'][$index]['igv']*100),422,'Desglose de línea incompatible.');
                }
                $native->update(['estado_sunat'=>'DEMO']);
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
        $path='barbarito/'.$row->company_id.'/'.$row->branch_id.'/'.$row->origin.'/'.$id.'/'.
            ($row->origin==='VENTA'?self::PDF_TEMPLATE_VERSION.'/':'').$format.'.pdf';
        // Private local disk; no storage:link and no user-supplied path.
        $file=DB::table('barbarito_files')->where('document_id',$id)->where('format',$format)->first();
        if(!$file || $file->path!==$path || !Storage::disk('local')->exists($path)) {
            $payload=json_decode($row->payload,true);
            if($row->origin==='VENTA') {
                $class=$row->native_type==='invoice'?Invoice::class:Boleta::class;
                $native=$class::findOrFail($row->native_id);
                foreach(['GRAVADO'=>'mto_oper_gravadas','EXONERADO'=>'mto_oper_exoneradas','INAFECTO'=>'mto_oper_inafectas'] as $kind=>$field) {
                    $native->$field=array_sum(array_map(fn($l)=>$l['afectacion']===$kind?(float)$l['subtotal']:0,$payload['lineas']));
                }
                // Historical identity comes from the immutable source, not today's client profile.
                $native->setRelation('client',new Client(['razon_social'=>$payload['tercero']['nombre'],
                    'tipo_documento'=>$payload['tercero']['tipo'],'numero_documento'=>$payload['tercero']['documento'],
                    'direccion'=>$payload['tercero']['direccion']??'']));
                $company=clone $native->company;
                $company->razon_social=str_replace(' · DEMOSTRACIÓN','',$payload['empresa']['nombre']);
                $native->setRelation('company',$company);
                $pdf=app(PdfService::class);
                $native->leyendas=[['code'=>'1000','value'=>strtoupper($pdf->numeroALetras($payload['total']).' '.($payload['moneda']==='PEN'?'SOLES':'DÓLARES AMERICANOS'))]];
                $bytes=$row->native_type==='invoice'?$pdf->generateInvoicePdf($native,$format):$pdf->generateBoletaPdf($native,$format);
            } else {
                // A supplier's invoice is received, never issued by our sales service.
                $bytes=app(BarbaritoPdfService::class)->renderSnapshot($payload,$row->number,$format);
            }
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
