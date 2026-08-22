import 'printing_models.dart';

class SalePrintSource {
  const SalePrintSource({
    required this.saleId,
    required this.branchId,
    required this.saleNumber,
    required this.status,
    required this.saleDate,
    required this.receiptType,
    required this.branchName,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    this.discountAmount = 0,
    this.serviceChargeAmount = 0,
    this.paidAmount = 0,
    this.balanceDue = 0,
    this.branchAddress,
    this.branchPhone,
    this.branchTaxId,
    this.branchLogoBytes,
    this.branchEmail,
    this.bankInfo,
    this.signatoryName,
    this.signatoryTitle,
    this.observation,
    this.clientName,
    this.clientDocument,
    this.clientAddress,
    this.clientPhone,
    this.clientEmail,
    this.cashierName,
    this.ncf,
    this.ncfValidUntil,
    this.notes,
    this.invoiceFooterNote,
    this.payments = const <SalePrintPaymentSource>[],
    this.cashRegisterName,
    this.priceTierLabel,
    this.changeAmount,
    this.showBarcode = true,
    this.showItbis = true,
    this.logoOnLeft = true,
    this.qrBytes,
    this.ecf,
  });

  final String saleId;
  final String branchId;
  final String saleNumber;
  final String status;
  final DateTime saleDate;
  final String receiptType;
  final String branchName;
  final String? branchAddress;
  final String? branchPhone;
  final String? branchTaxId;
  final List<int>? branchLogoBytes;
  final String? branchEmail;
  final String? bankInfo;
  final String? signatoryName;
  final String? signatoryTitle;
  final String? observation;
  final String? clientName;
  final String? clientDocument;
  final String? clientAddress;
  final String? clientPhone;
  final String? clientEmail;
  final String? cashierName;
  final String? ncf;

  /// Vencimiento de la secuencia NCF (se imprime bajo el NCF en el A4).
  final DateTime? ncfValidUntil;
  final String? notes;

  /// Nota legal al pie de la factura (junto a los totales, abajo a la
  /// izquierda). Configurable por negocio.
  final String? invoiceFooterNote;
  final List<SalePrintItemSource> items;
  final List<SalePrintPaymentSource> payments;
  final double subtotal;
  final double discountAmount;
  final double serviceChargeAmount;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;

  /// Nombre/código de la caja registradora abierta en el momento de la venta.
  final String? cashRegisterName;

  /// Etiqueta del nivel de precio aplicado (ej. "Mayorista", "Minorista").
  final String? priceTierLabel;

  /// Cambio entregado al cliente (paid - total). Si null se omite.
  final double? changeAmount;

  /// Si false oculta el barcode del recibo (alineado con
  /// `app_settings.receipt_hide_barcode`).
  final bool showBarcode;

  /// Si false, nunca se muestra el ITBIS en el documento A4 (toggle de config).
  final bool showItbis;

  /// Logo a la izquierda del encabezado A4 en vez de la derecha.
  /// Espeja `app_settings.invoice_logo_position`.
  final bool logoOnLeft;

  /// Bytes del QR (descargado de company_qr_url). Null → fallback al asset.
  final List<int>? qrBytes;

  /// Datos e-CF (QR DGII, código de seguridad, firma digital). Solo cuando la
  /// venta lleva NCF electrónico (serie E).
  final PrintEcfData? ecf;
}

class SalePrintItemSource {
  const SalePrintItemSource({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.sku,
    this.unitLabel,
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
  final String? unitLabel;
  final String? notes;

  /// Descuento aplicado a la línea (monto). 0 = sin descuento.
  final double lineDiscount;
}

class SalePrintPaymentSource {
  const SalePrintPaymentSource({
    required this.method,
    required this.amount,
    this.reference,
  });

  final String method;
  final double amount;
  final String? reference;
}

class SalePrintDocumentAdapter {
  const SalePrintDocumentAdapter();

  PrintDocumentData toDocumentData(SalePrintSource source) {
    // Una cuenta guardada se imprime sin NCF y sin pagos, con balance 0: hay
    // que rotularla como tal para que no se confunda con una factura cobrada.
    final isPending = source.status.trim().toLowerCase() == 'pending';

    // Descuento del documento. Se prefiere la SUMA de los descuentos de línea
    // (`sale_items.discount_amount`), que es el dato que siempre existe;
    // `sales.discount_amount` solo lo trae desde las migraciones 76 y 77 y se
    // usa como respaldo para documentos cuyas líneas no lo detallan.
    final lineDiscounts = _round2(
      source.items.fold<double>(0, (sum, item) => sum + item.lineDiscount),
    );
    final discount =
        lineDiscounts > 0.0049 ? lineDiscounts : source.discountAmount;
    // `subtotal` viene NETO de descuento (subtotal + ITBIS = total), así que
    // imprimirlo junto a la fila "Descuento" descontaría dos veces en el
    // papel. Se imprime el subtotal BRUTO para que el recibo cuadre:
    // bruto − descuento + ITBIS = total.
    final grossSubtotal = _round2(source.subtotal + discount);

    return PrintDocumentData(
      documentType: _documentTypeForSale(source),
      documentNumber: source.saleNumber,
      issuedAt: source.saleDate,
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
      customer: _customerForSale(source),
      isPendingAccount: isPending,
      cashierName: _nullIfBlank(source.cashierName),
      cashRegisterName: _nullIfBlank(source.cashRegisterName),
      priceTierLabel: _nullIfBlank(source.priceTierLabel),
      changeAmount: source.changeAmount,
      showBarcode: source.showBarcode,
      receiptTypeLabel: _receiptTypeLabel(source.receiptType),
      paymentTermsLabel: isPending
          ? 'CUENTA GUARDADA'
          : (source.balanceDue > 0.0049 ? 'CRÉDITO' : 'CONTADO'),
      // ITBIS solo si: el toggle de config está activo, NO es venta sin
      // comprobante, y al menos un ítem realmente lleva impuesto.
      logoOnLeft: source.logoOnLeft,
      showTax: source.showItbis &&
          source.receiptType != 'none' &&
          source.items.any((i) => i.lineTax > 0.0049),
      qrBytes: source.qrBytes,
      ecf: source.ecf,
      observation: _nullIfBlank(source.observation),
      ncf: _nullIfBlank(source.ncf),
      ncfValidUntil: source.ncfValidUntil,
      notes: _nullIfBlank(source.notes),
      legalFooterText: _nullIfBlank(source.invoiceFooterNote),
      footerMessage: isPending
          ? 'Documento no fiscal — cuenta pendiente de cobro'
          : 'Gracias por su compra',
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
              unitLabel: _nullIfBlank(item.unitLabel),
              notes: _nullIfBlank(item.notes),
            ),
          )
          .toList(growable: false),
      payments: source.payments
          .map(
            (payment) => PrintPaymentLine(
              method: _paymentMethodLabel(payment.method),
              amount: payment.amount,
              reference: _nullIfBlank(payment.reference),
            ),
          )
          .toList(growable: false),
      totals: PrintTotals(
        subtotal: grossSubtotal,
        discount: discount,
        serviceCharge: source.serviceChargeAmount,
        tax: source.taxAmount,
        total: source.totalAmount,
        paid: source.paidAmount,
        balance: source.balanceDue,
      ),
      extra: <String, dynamic>{
        'source_table': 'sales',
        'source_id': source.saleId,
        'branch_id': source.branchId,
        'sale_status': source.status,
        'receipt_type': source.receiptType,
      },
    );
  }
}

PrintDocumentType _documentTypeForSale(SalePrintSource source) {
  if (_hasText(source.ncf)) {
    return PrintDocumentType.fiscalInvoice;
  }

  return PrintDocumentType.saleReceipt;
}

PrintParty? _customerForSale(SalePrintSource source) {
  final name = _nullIfBlank(source.clientName);
  if (name == null) return null;

  return PrintParty(
    name: name,
    document: _nullIfBlank(source.clientDocument),
    address: _nullIfBlank(source.clientAddress),
    phone: _nullIfBlank(source.clientPhone),
    email: _nullIfBlank(source.clientEmail),
  );
}

String _receiptTypeLabel(String value) {
  switch (value) {
    case 'none':
      return 'Sin comprobante';
    case 'consumer_final':
      return 'Consumidor final';
    case 'fiscal_credit':
      return 'Crédito fiscal';
    case 'governmental':
      return 'Gubernamental';
    case 'special':
      return 'Régimen especial';
    case 'export':
      return 'Exportación';
    default:
      return value.trim().isEmpty ? 'Venta' : value;
  }
}

String _paymentMethodLabel(String value) {
  switch (value) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    case 'mobile':
      return 'Pago móvil';
    case 'mixed':
      return 'Mixto';
    case 'credit':
      return 'Crédito';
    default:
      return value.trim().isEmpty ? 'Pago' : value;
  }
}

String? _nullIfBlank(String? value) {
  if (!_hasText(value)) return null;
  return value!.trim();
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

double _round2(double value) => (value * 100).roundToDouble() / 100;
