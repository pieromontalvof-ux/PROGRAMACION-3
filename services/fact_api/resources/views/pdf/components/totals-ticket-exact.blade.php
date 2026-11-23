{{-- PDF Ticket Totals Component (Exact Design Match) --}}
{{-- Props: $document, $totales, $total_en_letras --}}

<div class="totals-section">
    {{-- Subtotal --}}
    <div class="total-line">
        <span class="total-text">TOTAL GRAVADO</span>
        <span class="total-dots">........................</span>
        <span class="total-value">({{ $totales['moneda'] }}) {{ number_format($document->mto_oper_gravadas ?? 0, 2) }}</span>
    </div>
    @foreach(['mto_oper_exoneradas'=>'TOTAL EXONERADO','mto_oper_inafectas'=>'TOTAL INAFECTO'] as $field=>$label)
        @if(($document->$field ?? 0)>0)
            <div class="total-line">
                <span class="total-text">{{ $label }}</span>
                <span class="total-dots">........................</span>
                <span class="total-value">({{ $totales['moneda'] }}) {{ number_format($document->$field,2) }}</span>
            </div>
        @endif
    @endforeach
    
    {{-- IGV --}}
    <div class="total-line">
        <span class="total-text">I.G.V</span>
        <span class="total-dots">..............................</span>
        <span class="total-value">({{ $totales['moneda'] }}) {{ $totales['igv_formatted'] }}</span>
    </div>
    
    {{-- Total Final --}}
    <div class="total-line total-final">
        <span class="total-text">TOTAL</span>
        <span class="total-dots">.................................</span>
        <span class="total-value">({{ $totales['moneda'] }}) {{ $totales['total_formatted'] }}</span>
    </div>
</div>

{{-- Total en Letras --}}
<div class="total-letras">
    SON: {{ strtoupper($total_en_letras) }} {{ strtoupper($totales['moneda_nombre']) }}
</div>

{{-- Payment Info --}}
<div class="payment-info">
    <div><strong>FORMA DE PAGO:</strong> {{ $document->forma_pago_tipo ?? 'CONTADO' }}</div>
    <div><strong>COND.VENTA:</strong> {{ $document->condicion_venta ?? 'CONTADO' }}</div>
</div>

{{-- Observations --}}
@if(!empty($document->observaciones))
    <div class="payment-info">
        <div><strong>Observaciones:</strong></div>
        <div>{{ $document->observaciones }}</div>
    </div>
@endif
