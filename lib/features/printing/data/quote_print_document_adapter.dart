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
    this.clientDocument,
    this.notes,
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
  final String? clientDocument;
  final String? notes;
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
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;
  final String? sku;
}

class QuotePrintDocumentAdapter {
  const QuotePrintDocumentAdapter();

  PrintDocumentData toDocumentData(QuotePrintSource source) {
    return PrintDocumentData(
      documentType: PrintDocumentType.quote,
      documentNumber: source.quoteCode,
      issuedAt: source.issuedAt,
      branch: PrintBranchIdentity(
        name: source.branchName,
        address: source.branchAddress,
        phone: source.branchPhone,
      ),
      customer: PrintParty(
        name: source.clientName,
        document: _nullIfBlank(source.clientDocument),
      ),
      receiptTypeLabel: 'Cotización',
      referenceNumber: 'Vigencia: ${_dateLabel(source.validUntil)}',
      notes: _nullIfBlank(source.notes),
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
              sku: _nullIfBlank(item.sku),
            ),
          )
          .toList(growable: false),
      payments: const [],
      totals: PrintTotals(
        subtotal: source.subtotal,
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
