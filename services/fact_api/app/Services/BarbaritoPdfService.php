<?php
namespace App\Services;

use Dompdf\Dompdf;
use Dompdf\Options;

/** Uses upstream formatting and PDF engine with an immutable demo template. */
class BarbaritoPdfService extends PdfService {
    public function renderSnapshot(array $payload, string $number, string $format): string {
        $options = new Options();
        $options->set('isRemoteEnabled', false);
        $options->set('isPhpEnabled', false);
        $options->set('defaultFont', 'DejaVu Sans');
        $pdf = new Dompdf($options);
        $pdf->loadHtml(view('pdf.barbarito.document', [
            'payload'=>$payload, 'number'=>$number, 'format'=>$format,
            'letters'=>$this->numeroALetras($payload['total']),
        ])->render());
        // Tickets grow with item count instead of cutting off a fixed-height page.
        if ($format==='80mm') {
            $pdf->setPaper([0,0,$this->mmToPt(80),$this->mmToPt(max(220,120+count($payload['lineas'])*30))]);
        } else {
            $this->setPaperFormat($pdf, 'A4');
        }
        $pdf->render();
        return $pdf->output();
    }
}
