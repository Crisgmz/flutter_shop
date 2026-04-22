import 'package:supabase_flutter/supabase_flutter.dart';

class FiscalDocument {
  FiscalDocument({
    required this.id,
    required this.branchId,
    required this.receiptType,
    required this.ncf,
    required this.fiscalStatus,
    required this.issuedAt,
    required this.subtotal,
    required this.taxableAmount,
    required this.exemptAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.totalAmount,
    required this.discountAmount,
    this.saleId,
    this.clientId,
    this.ncfSequenceId,
    this.sequenceNumber,
    this.expiresOn,
    this.voidedAt,
    this.voidReason,
    this.customerName,
    this.customerDocumentType,
    this.customerDocumentNumber,
    this.customerAddress,
    this.issuerName,
    this.issuerTaxId,
    this.issuerAddress,
  });

  final String id;
  final String branchId;
  final String? saleId;
  final String? clientId;
  final String? ncfSequenceId;
  final String receiptType;
  final String ncf;
  final int? sequenceNumber;
  final String fiscalStatus;
  final DateTime issuedAt;
  final DateTime? expiresOn;
  final DateTime? voidedAt;
  final String? voidReason;
  final String? customerName;
  final String? customerDocumentType;
  final String? customerDocumentNumber;
  final String? customerAddress;
  final String? issuerName;
  final String? issuerTaxId;
  final String? issuerAddress;
  final double subtotal;
  final double discountAmount;
  final double taxableAmount;
  final double exemptAmount;
  final double taxAmount;
  final double serviceChargeAmount;
  final double totalAmount;

  bool get isVoided => voidedAt != null;
  bool get isApproved => fiscalStatus == 'approved';
  bool get isPending => fiscalStatus == 'pending';

  factory FiscalDocument.fromMap(Map<String, dynamic> map) {
    return FiscalDocument(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      saleId: map['sale_id']?.toString(),
      clientId: map['client_id']?.toString(),
      ncfSequenceId: map['ncf_sequence_id']?.toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      ncf: (map['ncf'] ?? '').toString(),
      sequenceNumber: map['sequence_number'] == null
          ? null
          : _toInt(map['sequence_number']),
      fiscalStatus: (map['fiscal_status'] ?? 'pending').toString(),
      issuedAt: DateTime.tryParse((map['issued_at'] ?? '').toString()) ??
          DateTime.now(),
      expiresOn: map['expires_on'] == null
          ? null
          : DateTime.tryParse(map['expires_on'].toString()),
      voidedAt: map['voided_at'] == null
          ? null
          : DateTime.tryParse(map['voided_at'].toString()),
      voidReason: map['void_reason']?.toString(),
      customerName: map['customer_name']?.toString(),
      customerDocumentType: map['customer_document_type']?.toString(),
      customerDocumentNumber: map['customer_document_number']?.toString(),
      customerAddress: map['customer_address']?.toString(),
      issuerName: map['issuer_name']?.toString(),
      issuerTaxId: map['issuer_tax_id']?.toString(),
      issuerAddress: map['issuer_address']?.toString(),
      subtotal: _toDouble(map['subtotal']),
      discountAmount: _toDouble(map['discount_amount']),
      taxableAmount: _toDouble(map['taxable_amount']),
      exemptAmount: _toDouble(map['exempt_amount']),
      taxAmount: _toDouble(map['tax_amount']),
      serviceChargeAmount: _toDouble(map['service_charge_amount']),
      totalAmount: _toDouble(map['total_amount']),
    );
  }
}

class FiscalDocumentsRepository {
  FiscalDocumentsRepository(this._client);

  final SupabaseClient _client;

  Future<List<FiscalDocument>> fetchDocuments({
    String? statusFilter,
    String? receiptTypeFilter,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    var query = _client
        .from('fiscal_documents')
        .select(
          'id, branch_id, sale_id, client_id, ncf_sequence_id, receipt_type, ncf, '
          'sequence_number, fiscal_status, issued_at, expires_on, voided_at, void_reason, '
          'customer_name, customer_document_type, customer_document_number, customer_address, '
          'issuer_name, issuer_tax_id, issuer_address, '
          'subtotal, discount_amount, taxable_amount, exempt_amount, tax_amount, '
          'service_charge_amount, total_amount',
        )
        .eq('branch_id', branchId);

    if (statusFilter != null && statusFilter.isNotEmpty) {
      query = query.eq('fiscal_status', statusFilter);
    }
    if (receiptTypeFilter != null && receiptTypeFilter.isNotEmpty) {
      query = query.eq('receipt_type', receiptTypeFilter);
    }
    if (from != null) {
      query = query.gte('issued_at', from.toIso8601String());
    }
    if (to != null) {
      query = query.lte('issued_at', to.toIso8601String());
    }

    final rows = await query.order('issued_at', ascending: false).limit(limit);

    return rows
        .map((item) =>
            FiscalDocument.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<FiscalDocument?> fetchDocument(String id) async {
    final rows = await _client
        .from('fiscal_documents')
        .select()
        .eq('id', id)
        .limit(1);

    if (rows.isEmpty) return null;
    return FiscalDocument.fromMap(
        Map<String, dynamic>.from(rows.first as Map));
  }

  Future<void> voidDocument({
    required String id,
    required String reason,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('fiscal_documents')
        .update({
          'fiscal_status': 'voided',
          'voided_at': DateTime.now().toUtc().toIso8601String(),
          'void_reason': reason.trim(),
        })
        .eq('id', id)
        .eq('branch_id', branchId);
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
