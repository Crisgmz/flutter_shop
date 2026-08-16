import 'printing_models.dart';

class QuotePrintSource {
  const QuotePrintSource({
    required this.quoteId,
    required this.branchId,
    required this.quoteCode,
    required this.clientName,
    required this.issuedAt,
    required this.validUntil,
    required this.branchName,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    this.branchAddress,
    this.branchPhone,
    this.branchEmail,
    this.branchTaxId,
    this.branchLogoBytes,
    this.bankInfo,
    this.signatoryName,
    this.signatoryTitle,
    this.observation,
    this.clientLegalName,
    this.clientDocument,
    this.clientAddress,
    this.clientPhone,
    this.clientEmail,
    this.notes,
    this.quoteTerms,
    this.receiptTypeLabel,
    this.ncf,
    this.ncfValidUntil,
    this.showItbis = true,
    this.logoOnLeft = false,
    this.qrBytes,
  });

  final String quoteId;
  final String branchId;
  final String quoteCode;
  final String clientName;
  final DateTime issuedAt;
  final DateTime validUntil;
  final String branchName;
  final String? branchAddress;
  final String? branchPhone;
  final String? branchEmail;
  final String? branchTaxId;
  final List<int>? branchLogoBytes;
  final String? bankInfo;
  final String? signatoryName;
  final String? signatoryTitle;
  final String? observation;
  final String? clientLegalName;
  final String? clientDocument;
  final String? clientAddress;
  final String? clientPhone;
  final String? clientEmail;
  final String? notes;

  /// Términos y condiciones de la cotización (texto legal al pie, junto a los
  /// totales). Configurable por negocio.
  final String? quoteTerms;

  /// Etiqueta del comprobante cuando la cotización se emite con NCF
  /// reservado. Si es null se imprime "Cotización".
  final String? receiptTypeLabel;
  final String? ncf;
  final DateTime? ncfValidUntil;
  final bool showItbis;

  /// Logo y bloque fiscal a la izquierda del A4 en vez de la derecha.
  /// Espeja `app_settings.invoice_logo_position`.
  final bool logoOnLeft;
  final List<int>? qrBytes;
  final List<QuotePrintItemSource> items;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
}

class QuotePrintItemSource {
  const QuotePrintItemSource({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.sku,
    this.notes,
    this.lineDiscount = 0,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;
  final String? sku;

  /// Nota libre de la línea (se imprime bajo la descripción).
  final String? notes;

  /// Descuento aplicado a la línea (monto). 0 = sin descuento.
  final double lineDiscount;
}

class QuotePrintDocumentAdapter {
  const QuotePrintDocumentAdapter();

  PrintDocumentData toDocumentData(QuotePrintSource source) {
    // Mismo criterio que el recibo de venta: `quotations.subtotal` es la suma
    // de los `line_subtotal`, o sea que ya viene NETA de descuento. Para poder
    // mostrar la fila "Descuento" sin restar dos veces se imprime el subtotal
    // BRUTO: bruto − descuento + ITBIS = total.
    final discount = _round2(
      source.items.fold<double>(0, (sum, item) => sum + item.lineDiscount),
    );
    final grossSubtotal = _round2(source.subtotal + discount);

    return PrintDocumentData(
      documentType: PrintDocumentType.quote,
      documentNumber: source.quoteCode,
      issuedAt: source.issuedAt,
      branch: PrintBranchIdentity(
        name: source.branchName,
        address: _nullIfBlank(source.branchAddress),
        phone: _nullIfBlank(source.branchPhone),
        email: _nullIfBlank(source.branchEmail),
        taxId: _nullIfBlank(source.branchTaxId),
        logoBytes: source.branchLogoBytes,
        bankInfo: _nullIfBlank(source.bankInfo),
        signatoryName: _nullIfBlank(source.signatoryName),
        signatoryTitle: _nullIfBlank(source.signatoryTitle),
      ),
      customer: PrintParty(
        name: _nullIfBlank(source.clientLegalName) ?? source.clientName,
        document: _nullIfBlank(source.clientDocument),
        address: _nullIfBlank(source.clientAddress),
        phone: _nullIfBlank(source.clientPhone),
        email: _nullIfBlank(source.clientEmail),
      ),
      receiptTypeLabel: _nullIfBlank(source.receiptTypeLabel) ?? 'Cotización',
      ncf: _nullIfBlank(source.ncf),
      ncfValidUntil: source.ncfValidUntil,
      paymentTermsLabel: 'CONTADO',
      logoOnLeft: source.logoOnLeft,
      showTax: source.showItbis &&
          source.items.any((i) => i.lineTax > 0.0049),
      qrBytes: source.qrBytes,
      observation: _nullIfBlank(source.observation),
      referenceNumber: 'Vigencia: ${_dateLabel(source.validUntil)}',
      notes: _nullIfBlank(source.notes),
      legalFooterText: _nullIfBlank(source.quoteTerms),
      footerMessage: 'Gracias por su preferencia',
      items: source.items
          .map(
            (item) => PrintDocumentItem(
              description: item.description,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              lineSubtotal: item.lineSubtotal,
              lineTax: item.lineTax,
              lineTotal: item.lineTotal,
              lineDiscount: item.lineDiscount,
              sku: _nullIfBlank(item.sku),
              notes: _nullIfBlank(item.notes),
            ),
          )
          .toList(growable: false),
      payments: const [],
      totals: PrintTotals(
        subtotal: grossSubtotal,
        discount: discount,
        tax: source.taxAmount,
        total: source.totalAmount,
      ),
      extra: <String, dynamic>{
        'source_table': 'quotations',
        'source_id': source.quoteId,
        'branch_id': source.branchId,
      },
    );
  }
}

String _dateLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

String? _nullIfBlank(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
