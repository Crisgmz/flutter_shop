import '../../../shared/formatters/formatters.dart';
import 'fiscal_documents_repository.dart';

const fiscalReceiptLabels = <String, String>{
  'consumer_final': 'Consumidor Final',
  'fiscal_credit': 'Crédito Fiscal',
  'governmental': 'Gubernamental',
  'special': 'Especial',
  'export': 'Exportación',
};

const fiscalStatusLabels = <String, String>{
  'pending': 'Pendiente',
  'sent': 'Enviado',
  'approved': 'Aprobado',
  'rejected': 'Rechazado',
  'voided': 'Anulado',
};

String fiscalReceiptLabel(String receiptType) =>
    fiscalReceiptLabels[receiptType] ?? _pretty(receiptType);

/// Estado para mostrar: "Anulado" si se anuló el comprobante o la venta.
String fiscalStatusLabel(FiscalDocument doc) => doc.isCancelled
    ? 'Anulado'
    : fiscalStatusLabels[doc.fiscalStatus] ?? doc.fiscalStatus;

/// "Efectivo", "Efectivo + Tarjeta", "Crédito"… según cómo se pagó la
/// factura al venderla. "—" si el comprobante no tiene venta.
String fiscalPaymentLabel(FiscalDocument doc) =>
    paymentBreakdownLabel(doc.paymentBreakdown);

/// Métodos de un desglose de pago, en palabras: "Efectivo + Crédito".
String paymentBreakdownLabel(Map<String, double> breakdown) {
  if (breakdown.isEmpty) return '—';
  return breakdown.keys.map(paymentMethodLabel).join(' + ');
}

String _pretty(String value) {
  if (value.isEmpty) return '—';
  return value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
