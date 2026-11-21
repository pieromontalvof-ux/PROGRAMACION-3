<!doctype html><html lang="es"><head><meta charset="utf-8"><style>
@page{margin:{{ $format==='80mm' ? '10px' : '35px' }}}body{font-family:DejaVu Sans,sans-serif;font-size:{{ $format==='80mm' ? '9px' : '11px' }};color:#163f35}h1{font-size:19px}h2{font-size:14px}.notice{border:2px solid #0c664b;padding:8px;font-weight:bold}table{border-collapse:collapse;width:100%;margin-top:15px}th,td{border-bottom:1px solid #ccc;padding:6px;text-align:left}th{background:#e5f1eb}.amount{text-align:right}.muted{color:#555;font-size:9px}
</style></head><body>
<h1>{{ $payload['empresa']['nombre'] }}</h1>
<div class="notice">DOCUMENTO DE PRUEBA · SIN VALIDEZ TRIBUTARIA</div>
<h2>{{ $payload['origen']==='COMPRA' ? 'Registro de factura recibida' : ($payload['tipo']==='01' ? 'Factura de prueba' : 'Boleta de prueba') }} — {{ $number }}</h2>
<p>Fecha: {{ $payload['fecha'] }} · Local: {{ $payload['id_local'] }} · Moneda: {{ $payload['moneda'] }}</p>
<p><b>{{ $payload['origen']==='COMPRA' ? 'Proveedor' : 'Cliente' }}:</b> {{ $payload['tercero']['nombre'] }}<br>Documento: {{ $payload['tercero']['documento'] ?: 'Sin documento' }}</p>
@if($payload['origen']==='COMPRA')<p>OC: {{ $payload['orden_compra'] }}<br>Vista interna; no sustituye el archivo original entregado por el proveedor.</p>@endif
<table><thead><tr><th>Producto / cantidad</th><th class="amount">Base</th><th class="amount">IGV</th><th class="amount">Total</th></tr></thead><tbody>
@foreach($payload['lineas'] as $line)<tr><td>{{ $line['nombre'] }}<br>{{ $line['cantidad'] }} {{ $line['unidad'] }} · {{ $line['afectacion'] }}</td><td class="amount">{{ number_format((float)$line['subtotal'],2) }}</td><td class="amount">{{ number_format((float)$line['igv'],2) }}</td><td class="amount">{{ number_format((float)$line['total'],2) }}</td></tr>@endforeach
</tbody></table><p class="amount">Subtotal: {{ $payload['subtotal'] }}<br>IGV: {{ $payload['igv'] }}<br><b>Total: {{ $payload['total'] }} {{ $payload['moneda'] }}</b></p><p>{{ $letters }}</p>
<p class="muted">Generado por fact_api para Barbarito. No enviado a SUNAT. No existe CDR de aceptación para este documento.</p>
</body></html>
