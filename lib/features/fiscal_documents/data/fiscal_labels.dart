import '../../../shared/formatters/formatters.dart';
import 'fiscal_documents_repository.dart';

const fiscalReceiptLabels = <String, String>{
  'consumer_final': 'Consumidor Final',
  'fiscal_credit': 'Crédito Fiscal',
  'governmental': 'Gubernamental',
  'special': 'Especial',
  'export': 'Exportación',
  // E34: la emite sola la base al anular una e-CF aceptada (migración 107).
  'credit_note': 'Nota de Crédito',
  // Venta sin NCF (migración 110); se puede convertir en comprobante.
  'proforma': 'Proforma',
};

/// Comprobantes fiscales que se emiten al vender (y a los que se puede
/// convertir una proforma), en el orden del selector del POS.
const kSaleFiscalReceiptTypes = <String>[
  'consumer_final',
  'fiscal_credit',
  'governmental',
  'special',
  'export',
];

const _kPhysicalReceiptCodes = <String, String>{
  'consumer_final': 'B02',
  'fiscal_credit': 'B01',
  'governmental': 'B15',
  'special': 'B14',
  'export': 'B16',
};

const _kElectronicReceiptCodes = <String, String>{
  'consumer_final': 'E32',
  'fiscal_credit': 'E31',
  'governmental': 'E45',
  'special': 'E44',
  'export': 'E46',
};

/// Código DGII del comprobante según la modalidad de la empresa: física →
/// serie B (B02…), electrónica o híbrida → serie E (E32…), que es la que
/// `assign_next_ncf` consume. Null si el tipo no es fiscal.
String? fiscalReceiptCode(String receiptType, {required bool electronic}) =>
    (electronic ? _kElectronicReceiptCodes : _kPhysicalReceiptCodes)[
        receiptType];

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
