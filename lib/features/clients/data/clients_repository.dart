import 'package:supabase_flutter/supabase_flutter.dart';

class ClientEntity {
  ClientEntity({
    required this.id,
    required this.fullName,
    required this.entityType,
    required this.legalName,
    required this.email,
    required this.phone,
    required this.address,
    required this.documentType,
    required this.documentNumber,
    required this.creditLimit,
    required this.balanceDue,
    required this.isActive,
    // ── fields from 20260421 migration ──────────────────────────────────
    this.firstName,
    this.lastName,
    this.companyName,
    this.secondaryPhone,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.province,
    this.countryCode = 'DO',
    this.postalCode,
    this.googleMapsUrl,
    this.avatarUrl,
    this.birthday,
    this.comments,
    this.defaultReceiptType,
    this.priceTier = 'retail',
    this.taxExempt = false,
    this.chargeItbis = true,
    this.creditInvoiceLimit = 0,
  });

  final String id;
  final String fullName;
  final String entityType;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? address;
  final String? documentType;
  final String? documentNumber;
  final double creditLimit;
  final double balanceDue;
  final bool isActive;

  final String? firstName;
  final String? lastName;
  final String? companyName;
  final String? secondaryPhone;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? province;
  final String countryCode;
  final String? postalCode;
  final String? googleMapsUrl;
  final String? avatarUrl;
  final DateTime? birthday;
  final String? comments;
  final String? defaultReceiptType;
  final String priceTier;
  final bool taxExempt;
  final bool chargeItbis;
  final int creditInvoiceLimit;

  factory ClientEntity.fromMap(Map<String, dynamic> map) {
    return ClientEntity(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      entityType: (map['entity_type'] ?? 'person').toString(),
      legalName: map['legal_name']?.toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      address: map['address']?.toString(),
      documentType: map['document_type']?.toString(),
      documentNumber: map['document_number']?.toString(),
      creditLimit: _toDouble(map['credit_limit']),
      balanceDue: _toDouble(map['balance_due']),
      isActive: map['is_active'] == true,
      firstName: map['first_name']?.toString(),
      lastName: map['last_name']?.toString(),
      companyName: map['company_name']?.toString(),
      secondaryPhone: map['secondary_phone']?.toString(),
      addressLine1: map['address_line_1']?.toString(),
      addressLine2: map['address_line_2']?.toString(),
      city: map['city']?.toString(),
      province: map['province']?.toString(),
      countryCode: (map['country_code'] ?? 'DO').toString(),
      postalCode: map['postal_code']?.toString(),
      googleMapsUrl: map['google_maps_url']?.toString(),
      avatarUrl: map['avatar_url']?.toString(),
      birthday: map['birthday'] == null
          ? null
          : DateTime.tryParse(map['birthday'].toString()),
      comments: map['comments']?.toString(),
      defaultReceiptType: map['default_receipt_type']?.toString(),
      priceTier: (map['price_tier'] ?? 'retail').toString(),
      taxExempt: map['tax_exempt'] == true,
      chargeItbis: map['charge_itbis'] != false,
      creditInvoiceLimit: _toInt(map['credit_invoice_limit']),
    );
  }
}

class ClientInput {
  ClientInput({
    required this.fullName,
    required this.entityType,
    required this.creditLimit,
    required this.isActive,
    this.id,
    this.firstName,
    this.lastName,
    this.companyName,
    this.legalName,
    this.email,
    this.phone,
    this.secondaryPhone,
    this.address,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.province,
    this.countryCode = 'DO',
    this.postalCode,
    this.googleMapsUrl,
    this.documentType,
    this.documentNumber,
    this.birthday,
    this.comments,
    this.defaultReceiptType,
    this.priceTier = 'retail',
    this.taxExempt = false,
    this.chargeItbis = true,
    this.creditInvoiceLimit = 0,
  });

  final String? id;
  final String fullName;
  final String entityType;
  final String? firstName;
  final String? lastName;
  final String? companyName;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? secondaryPhone;
  final String? address;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? province;
  final String countryCode;
  final String? postalCode;
  final String? googleMapsUrl;
  final String? documentType;
  final String? documentNumber;
  final double creditLimit;
  final bool isActive;
  final DateTime? birthday;
  final String? comments;
  final String? defaultReceiptType;
  final String priceTier;
  final bool taxExempt;
  final bool chargeItbis;
  final int creditInvoiceLimit;
}

class CustomerBalanceItem {
  CustomerBalanceItem({
    required this.id,
    required this.fullName,
    required this.balanceDue,
    required this.creditLimit,
    required this.salesCount,
    required this.totalSalesAmount,
    this.companyName,
    this.phone,
    this.email,
    this.lastSaleAt,
    this.priceTier = 'retail',
  });

  final String id;
  final String fullName;
  final String? companyName;
  final String? phone;
  final String? email;
  final double balanceDue;
  final double creditLimit;
  final int salesCount;
  final double totalSalesAmount;
  final DateTime? lastSaleAt;
  final String priceTier;

  String get displayName => companyName?.isNotEmpty == true ? companyName! : fullName;
  bool get overLimit => creditLimit > 0 && balanceDue > creditLimit;

  factory CustomerBalanceItem.fromMap(Map<String, dynamic> map) {
    return CustomerBalanceItem(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      companyName: map['company_name']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      balanceDue: _toDouble(map['balance_due']),
      creditLimit: _toDouble(map['credit_limit']),
      salesCount: _toInt(map['sales_count']),
      totalSalesAmount: _toDouble(map['total_sales_amount']),
      lastSaleAt: map['last_sale_at'] == null
          ? null
          : DateTime.tryParse(map['last_sale_at'].toString()),
      priceTier: (map['price_tier'] ?? 'retail').toString(),
    );
  }
}

class ClientsRepository {
  ClientsRepository(this._client);

  final SupabaseClient _client;

  Future<List<ClientEntity>> fetchClients() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('clients')
        .select(
          'id, full_name, entity_type, legal_name, email, phone, address, '
          'document_type, document_number, credit_limit, balance_due, is_active, '
          'first_name, last_name, company_name, secondary_phone, '
          'address_line_1, address_line_2, city, province, country_code, '
          'postal_code, google_maps_url, avatar_url, birthday, comments, '
          'default_receipt_type, price_tier, tax_exempt, charge_itbis, '
          'credit_invoice_limit',
        )
        .eq('branch_id', branchId)
        .order('full_name');

    return rows
        .map(
          (item) =>
              ClientEntity.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<void> saveClient(ClientInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final payload = <String, dynamic>{
      'full_name': input.fullName.trim(),
      'entity_type': input.entityType,
      'first_name': _nullIfEmpty(input.firstName),
      'last_name': _nullIfEmpty(input.lastName),
      'company_name': _nullIfEmpty(input.companyName),
      'legal_name': _nullIfEmpty(input.legalName),
      'email': _nullIfEmpty(input.email),
      'phone': _nullIfEmpty(input.phone),
      'secondary_phone': _nullIfEmpty(input.secondaryPhone),
      'address': _nullIfEmpty(input.address),
      'address_line_1': _nullIfEmpty(input.addressLine1),
      'address_line_2': _nullIfEmpty(input.addressLine2),
      'city': _nullIfEmpty(input.city),
      'province': _nullIfEmpty(input.province),
      'country_code':
          input.countryCode.isNotEmpty ? input.countryCode : 'DO',
      'postal_code': _nullIfEmpty(input.postalCode),
      'google_maps_url': _nullIfEmpty(input.googleMapsUrl),
      'document_type': _nullIfEmpty(input.documentType),
      'document_number': _nullIfEmpty(input.documentNumber),
      'credit_limit': input.creditLimit,
      'is_active': input.isActive,
      'birthday': input.birthday?.toIso8601String().split('T').first,
      'comments': _nullIfEmpty(input.comments),
      'default_receipt_type': input.defaultReceiptType,
      'price_tier': input.priceTier,
      'tax_exempt': input.taxExempt,
      'charge_itbis': input.chargeItbis,
      'credit_invoice_limit': input.creditInvoiceLimit,
    };

    if (input.id == null) {
      payload['branch_id'] = branchId;
      await _client.from('clients').insert(payload);
      return;
    }

    await _client
        .from('clients')
        .update(payload)
        .eq('id', input.id!)
        .eq('branch_id', branchId);
  }

  Future<List<CustomerBalanceItem>> fetchCustomerBalances({
    bool withBalanceOnly = true,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    var query = _client
        .from('customer_balances_view')
        .select(
          'id, full_name, company_name, phone, email, '
          'credit_limit, balance_due, price_tier, '
          'sales_count, total_sales_amount, last_sale_at',
        )
        .eq('branch_id', branchId);

    if (withBalanceOnly) {
      query = query.gt('balance_due', 0);
    }

    final rows = await query
        .order('balance_due', ascending: false)
        .limit(100);

    return rows
        .map(
          (item) => CustomerBalanceItem.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> setClientActive({
    required String clientId,
    required bool isActive,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('clients')
        .update({'is_active': isActive})
        .eq('id', clientId)
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
