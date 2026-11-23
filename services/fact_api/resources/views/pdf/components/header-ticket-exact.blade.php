{{-- PDF Ticket Header Component (Exact Design Match) --}}
{{-- Props: $company, $document, $tipo_documento_nombre --}}

@php
    $logoPath = public_path(($is_demo ?? false) ? 'logo_barbarian.png' : 'logo_factura.png');
@endphp

<div class="header">
    {{-- Logo --}}
    @if(file_exists($logoPath))
        <div class="logo-section-ticket">
            <img src="data:image/png;base64,{{ base64_encode(file_get_contents($logoPath)) }}" alt="Logo" class="logo-img-ticket">
        </div>
    @endif

    {{-- Company Name --}}
    <div class="company-name">{{ strtoupper($company->razon_social ?? 'EMPRESA DEMO SAC') }}</div>
    
    {{-- RUC --}}
    <div class="company-ruc">RUC: {{ $company->ruc ?? '20100100100' }}</div>
    
    {{-- Company Details --}}
    <div class="company-details">
        {{ $company->direccion ?? 'CALLE LAS NORMAS 123' }}<br>
        {{ $company->distrito ?? '' }} {{ $company->codigo_postal ?? '' }}<br>
        @if($company->email)Correo: {{ $company->email }}<br>@endif
        @if($company->website)Web: {{ $company->website }}@endif
    </div>

    {{-- Document Title --}}
    <div class="document-title">{{ strtoupper($tipo_documento_nombre ?? 'BOLETA DE VENTA ELECTRONICA') }}</div>
    
    {{-- Document Number --}}
    <div class="document-number">{{ $document->numero_completo }}</div>
</div>
