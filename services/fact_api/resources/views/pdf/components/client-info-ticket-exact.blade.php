{{-- PDF Ticket Client Info Component (Exact Design Match) --}}
{{-- Props: $client, $fecha_emision --}}

<div class="client-section">
    {{-- Client Name --}}
    <div class="client-name">{{ strtoupper($client['razon_social'] ?? 'CAMILO SANCHEZ') }}</div>
    
    {{-- Separator --}}
    <div class="client-separator">---</div>
    
    {{-- Document Number --}}
    <div class="client-details">{{ ($client['tipo_documento'] ?? '') === '6' ? 'RUC' : 'Documento' }} {{ $client['numero_documento'] ?? '' }}</div>
    
    {{-- Date and Time --}}
    <div class="client-details">
        FECHA: {{ $fecha_emision }}
    </div>
</div>
