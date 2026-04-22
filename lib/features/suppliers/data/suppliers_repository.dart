import 'package:supabase_flutter/supabase_flutter.dart';

class SupplierEntity {
  SupplierEntity({
    required this.id,
    required this.legalName,
    required this.isActive,
    this.tradeName,
    this.email,
    this.phone,
    this.address,
    this.rnc,
    this.contactName,
    this.documentType,
    this.documentNumber,
    this.secondaryPhone,
    this.city,
    this.province,
    this.countryCode = 'DO',
    this.postalCode,
    this.paymentTermsDays = 0,
    this.comments,
  });

  final String id;
  final String legalName;
  final String? tradeName;
  final String? email;
  final String? phone;
  final String? address;
  final String? rnc;
  final String? contactName;
  final bool isActive;
  final String? documentType;
  final String? documentNumber;
  final String? secondaryPhone;
  final String? city;
  final String? province;
  final String countryCode;
  final String? postalCode;
  final int paymentTermsDays;
  final String? comments;

  factory SupplierEntity.fromMap(Map<String, dynamic> map) {
    return SupplierEntity(
      id: (map['id'] ?? '').toString(),
      legalName: (map['legal_name'] ?? '').toString(),
      tradeName: map['trade_name']?.toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      address: map['address']?.toString(),
      rnc: map['rnc']?.toString(),
      contactName: map['contact_name']?.toString(),
      isActive: map['is_active'] == true,
      documentType: map['document_type']?.toString(),
      documentNumber: map['document_number']?.toString(),
      secondaryPhone: map['secondary_phone']?.toString(),
      city: map['city']?.toString(),
      province: map['province']?.toString(),
      countryCode: (map['country_code'] ?? 'DO').toString(),
      postalCode: map['postal_code']?.toString(),
      paymentTermsDays: (map['payment_terms_days'] as int?) ?? 0,
      comments: map['comments']?.toString(),
    );
  }
}

class SupplierInput {
  SupplierInput({
    required this.legalName,
    required this.isActive,
    this.id,
    this.tradeName,
    this.email,
    this.phone,
    this.address,
    this.rnc,
    this.contactName,
    this.documentType,
    this.documentNumber,
    this.secondaryPhone,
    this.city,
    this.province,
    this.countryCode = 'DO',
    this.postalCode,
    this.paymentTermsDays = 0,
    this.comments,
  });

  final String? id;
  final String legalName;
  final String? tradeName;
  final String? email;
  final String? phone;
  final String? address;
  final String? rnc;
  final String? contactName;
  final bool isActive;
  final String? documentType;
  final String? documentNumber;
  final String? secondaryPhone;
  final String? city;
  final String? province;
  final String countryCode;
  final String? postalCode;
  final int paymentTermsDays;
  final String? comments;
}

class SuppliersRepository {
  SuppliersRepository(this._client);

  final SupabaseClient _client;

  Future<List<SupplierEntity>> fetchSuppliers() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('suppliers')
        .select(
          'id, legal_name, trade_name, email, phone, address, rnc, contact_name, is_active, '
          'document_type, document_number, secondary_phone, '
          'city, province, country_code, postal_code, '
          'payment_terms_days, comments',
        )
        .eq('branch_id', branchId)
        .order('legal_name');

    return rows
        .map(
          (item) =>
              SupplierEntity.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<void> saveSupplier(SupplierInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final payload = <String, dynamic>{
      'legal_name': input.legalName.trim(),
      'trade_name': _nullIfEmpty(input.tradeName),
      'email': _nullIfEmpty(input.email),
      'phone': _nullIfEmpty(input.phone),
      'address': _nullIfEmpty(input.address),
      'rnc': _nullIfEmpty(input.rnc),
      'contact_name': _nullIfEmpty(input.contactName),
      'is_active': input.isActive,
      'document_type': _nullIfEmpty(input.documentType),
      'document_number': _nullIfEmpty(input.documentNumber),
      'secondary_phone': _nullIfEmpty(input.secondaryPhone),
      'city': _nullIfEmpty(input.city),
      'province': _nullIfEmpty(input.province),
      'country_code': input.countryCode,
      'postal_code': _nullIfEmpty(input.postalCode),
      'payment_terms_days': input.paymentTermsDays,
      'comments': _nullIfEmpty(input.comments),
    };

    if (input.id == null) {
      payload['branch_id'] = branchId;
      await _client.from('suppliers').insert(payload);
      return;
    }

    await _client
        .from('suppliers')
        .update(payload)
        .eq('id', input.id!)
        .eq('branch_id', branchId);
  }

  Future<void> setSupplierActive({
    required String supplierId,
    required bool isActive,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('suppliers')
        .update({'is_active': isActive})
        .eq('id', supplierId)
        .eq('branch_id', branchId);
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
