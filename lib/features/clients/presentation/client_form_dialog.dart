import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/services/dgii_lookup_service.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/clients_repository.dart';

const _receiptTypeLabels = <String, String>{
  'consumer_final': 'Consumidor final',
  'fiscal_credit': 'Crédito fiscal',
  'governmental': 'Gubernamental',
  'special': 'Especial',
  'export': 'Exportación',
};

// ─── Client dialog ───────────────────────────────────────────────────────────

/// Formulario completo de cliente. Se usa tanto desde la pantalla Clientes
/// como desde el Punto de Venta. Devuelve un [ClientInput] por `Navigator.pop`
/// (o `null` si se cancela); guardar en la base es responsabilidad del caller.
class ClientFormDialog extends ConsumerStatefulWidget {
  const ClientFormDialog({super.key, this.initial});

  final ClientEntity? initial;

  @override
  ConsumerState<ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends ConsumerState<ClientFormDialog> {
  final _formKey = GlobalKey<FormState>();

  // Datos generales
  late final TextEditingController _fullNameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _companyNameController;
  late final TextEditingController _legalNameController;
  late final TextEditingController _documentTypeController;
  late final TextEditingController _documentNumberController;

  // Contacto
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _secondaryPhoneController;

  // Dirección
  late final TextEditingController _addressLine1Controller;
  late final TextEditingController _addressLine2Controller;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _countryCodeController;
  late final TextEditingController _googleMapsUrlController;

  // Fiscal / Comercial
  late final TextEditingController _creditLimitController;
  late final TextEditingController _creditInvoiceLimitController;
  late final TextEditingController _birthdayController;
  late final TextEditingController _commentsController;

  late String _entityType;
  late String _priceTier;
  late String? _defaultReceiptType;
  late bool _isActive;
  late bool _taxExempt;
  late bool _chargeItbis;

  /// Consulta de RNC a DGII en curso.
  bool _rncLookupLoading = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;

    _fullNameController = TextEditingController(text: c?.fullName ?? '');
    _firstNameController = TextEditingController(text: c?.firstName ?? '');
    _lastNameController = TextEditingController(text: c?.lastName ?? '');
    _companyNameController = TextEditingController(text: c?.companyName ?? '');
    _legalNameController = TextEditingController(text: c?.legalName ?? '');
    _documentTypeController = TextEditingController(
      text: c?.documentType ?? '',
    );
    _documentNumberController = TextEditingController(
      text: c?.documentNumber ?? '',
    );

    _emailController = TextEditingController(text: c?.email ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _secondaryPhoneController = TextEditingController(
      text: c?.secondaryPhone ?? '',
    );

    _addressLine1Controller = TextEditingController(
      text: c?.addressLine1 ?? c?.address ?? '',
    );
    _addressLine2Controller = TextEditingController(
      text: c?.addressLine2 ?? '',
    );
    _cityController = TextEditingController(text: c?.city ?? '');
    _provinceController = TextEditingController(text: c?.province ?? '');
    _postalCodeController = TextEditingController(text: c?.postalCode ?? '');
    _countryCodeController = TextEditingController(
      text: c?.countryCode ?? 'DO',
    );
    _googleMapsUrlController = TextEditingController(
      text: c?.googleMapsUrl ?? '',
    );

    _creditLimitController = TextEditingController(
      text: c == null ? '0' : c.creditLimit.toStringAsFixed(2),
    );
    _creditInvoiceLimitController = TextEditingController(
      text: (c?.creditInvoiceLimit ?? 0).toString(),
    );
    _birthdayController = TextEditingController(
      text: c?.birthday == null ? '' : _date(c!.birthday!),
    );
    _commentsController = TextEditingController(text: c?.comments ?? '');

    _entityType = c?.entityType ?? 'person';
    _priceTier = c?.priceTier ?? 'retail';
    _defaultReceiptType = c?.defaultReceiptType;
    _isActive = c?.isActive ?? true;
    _taxExempt = c?.taxExempt ?? false;
    _chargeItbis = c?.chargeItbis ?? true;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyNameController.dispose();
    _legalNameController.dispose();
    _documentTypeController.dispose();
    _documentNumberController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _secondaryPhoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _postalCodeController.dispose();
    _countryCodeController.dispose();
    _googleMapsUrlController.dispose();
    _creditLimitController.dispose();
    _creditInvoiceLimitController.dispose();
    _birthdayController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  /// Consulta el RNC/cédula del campo "Número documento" contra DGII y
  /// auto-completa razón social, nombre comercial y tipo de documento.
  Future<void> _lookupRnc() async {
    final raw = _documentNumberController.text.trim();
    if (raw.isEmpty) {
      AppSnackBar.info(context, 'Escribe el RNC o cédula primero.');
      return;
    }
    setState(() => _rncLookupLoading = true);
    try {
      final info = await ref.read(dgiiLookupServiceProvider).lookupByRnc(raw);
      if (!mounted) return;
      if (info == null) {
        AppSnackBar.error(context, 'RNC/cédula no encontrado en DGII.');
        return;
      }
      setState(() {
        final name = info.nombreRazonSocial ?? info.displayName;
        if (name != null && name.isNotEmpty) {
          if (_legalNameController.text.trim().isEmpty) {
            _legalNameController.text = name;
          }
          if (_fullNameController.text.trim().isEmpty) {
            _fullNameController.text = name;
          }
        }
        final comercial = info.nombreComercial;
        if (comercial != null &&
            comercial.isNotEmpty &&
            _companyNameController.text.trim().isEmpty) {
          _companyNameController.text = comercial;
        }
        // Tipo de documento por longitud: 11 = cédula, 9 = RNC (empresa).
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        if (_documentTypeController.text.trim().isEmpty) {
          _documentTypeController.text = digits.length == 11 ? 'cedula' : 'rnc';
        }
      });
      if (info.isActivo) {
        AppSnackBar.success(context, 'Encontrado: ${info.displayName ?? raw}');
      } else {
        AppSnackBar.info(
          context,
          'Encontrado (${info.estado ?? "estado desconocido"}): '
          '${info.displayName ?? raw}',
        );
      }
    } on InvalidRncException catch (e) {
      if (mounted) AppSnackBar.error(context, e.reason);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'No se pudo consultar el RNC', e);
    } finally {
      if (mounted) setState(() => _rncLookupLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo cliente' : 'Editar cliente'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 580,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Datos generales ──────────────────────────────────────
                _sectionHeader('Datos generales'),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo / Razón comercial',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nombre requerido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  TextFormField(
                    controller: _lastNameController,
                    decoration: const InputDecoration(labelText: 'Apellido'),
                  ),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _entityType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de entidad',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'person', child: Text('Persona')),
                    DropdownMenuItem(value: 'company', child: Text('Empresa')),
                    DropdownMenuItem(
                      value: 'government',
                      child: Text('Gubernamental'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _entityType = value);
                  },
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _companyNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre empresa',
                    ),
                  ),
                  TextFormField(
                    controller: _legalNameController,
                    decoration: const InputDecoration(
                      labelText: 'Razón social',
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _documentTypeController,
                    decoration: const InputDecoration(
                      labelText: 'Tipo doc. (cédula/rnc)',
                    ),
                  ),
                  TextFormField(
                    controller: _documentNumberController,
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (_) => _lookupRnc(),
                    decoration: InputDecoration(
                      labelText: 'Número documento',
                      helperText: 'RNC (9) o cédula (11). Busca en DGII.',
                      suffixIcon: _rncLookupLoading
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Buscar razón social en DGII',
                              icon: const Icon(Icons.search),
                              onPressed: _lookupRnc,
                            ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                const Divider(),

                // ── Contacto ─────────────────────────────────────────────
                _sectionHeader('Contacto'),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      if (!value.contains('@')) return 'Correo inválido';
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _secondaryPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono secundario',
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // ── Dirección ────────────────────────────────────────────
                _sectionHeader('Dirección'),
                TextFormField(
                  controller: _addressLine1Controller,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressLine2Controller,
                  decoration: const InputDecoration(
                    labelText: 'Dirección (línea 2)',
                  ),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                  ),
                  TextFormField(
                    controller: _provinceController,
                    decoration: const InputDecoration(labelText: 'Provincia'),
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _postalCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Código postal',
                    ),
                  ),
                  TextFormField(
                    controller: _countryCodeController,
                    decoration: const InputDecoration(labelText: 'País'),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _googleMapsUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL Google Maps (opcional)',
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // ── Fiscal / Comercial ───────────────────────────────────
                _sectionHeader('Fiscal / Comercial'),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _creditLimitController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Límite de crédito',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Límite inválido';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _creditInvoiceLimitController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Límite facturas crédito',
                    ),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                _PriceTierDropdown(
                  value: _priceTier,
                  onChanged: (v) => setState(() => _priceTier = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _defaultReceiptType,
                  decoration: const InputDecoration(
                    labelText: 'Comprobante por defecto (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— Sin especificar —'),
                    ),
                    ..._receiptTypeLabels.entries.map(
                      (e) => DropdownMenuItem<String?>(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _defaultReceiptType = value),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _chargeItbis,
                  onChanged: (value) => setState(() => _chargeItbis = value),
                  title: const Text('Cobrar ITBIS'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _taxExempt,
                  onChanged: (value) => setState(() => _taxExempt = value),
                  title: const Text('Exento de impuestos'),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // ── Otros ────────────────────────────────────────────────
                _sectionHeader('Otros'),
                TextFormField(
                  controller: _birthdayController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Fecha de nacimiento',
                    suffixIcon: IconButton(
                      onPressed: _pickBirthday,
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _commentsController,
                  decoration: const InputDecoration(labelText: 'Comentarios'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Activo'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppTokens.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _formRow(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children:
            children.expand((w) => [w, const SizedBox(height: 10)]).toList()
              ..removeLast(),
      );
    }
    return Row(
      children:
          children
              .expand((w) => [Expanded(child: w), const SizedBox(width: 10)])
              .toList()
            ..removeLast(),
    );
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final parsed = _parseDate(_birthdayController.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked == null) return;
    _birthdayController.text = _date(picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      ClientInput(
        id: widget.initial?.id,
        fullName: _fullNameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        companyName: _companyNameController.text.trim(),
        entityType: _entityType,
        legalName: _legalNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        secondaryPhone: _secondaryPhoneController.text.trim(),
        address: _addressLine1Controller.text.trim(),
        addressLine1: _addressLine1Controller.text.trim(),
        addressLine2: _addressLine2Controller.text.trim(),
        city: _cityController.text.trim(),
        province: _provinceController.text.trim(),
        postalCode: _postalCodeController.text.trim(),
        countryCode: _countryCodeController.text.trim().isEmpty
            ? 'DO'
            : _countryCodeController.text.trim(),
        googleMapsUrl: _googleMapsUrlController.text.trim(),
        documentType: _documentTypeController.text.trim(),
        documentNumber: _documentNumberController.text.trim(),
        creditLimit: double.parse(_creditLimitController.text.trim()),
        creditInvoiceLimit: int.parse(
          _creditInvoiceLimitController.text.trim(),
        ),
        birthday: _parseDate(_birthdayController.text),
        comments: _commentsController.text.trim(),
        defaultReceiptType: _defaultReceiptType,
        priceTier: _priceTier,
        taxExempt: _taxExempt,
        chargeItbis: _chargeItbis,
        isActive: _isActive,
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _date(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime? _parseDate(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

// ─────────────────────────────────────────────────────────────────────────
// Dropdown de nivel de precio, alimentado por app_settings.sale_price_types.
// Mapeo posicional: índice 0 → tier_1, 1 → tier_2, 2 → tier_3. Más
// 'Detalle' (retail) como base siempre disponible. Valores legados
// ('wholesale', 'vip', etc.) se preservan como opción "(antiguo)".
// ─────────────────────────────────────────────────────────────────────────

const _kPriceTierBase = 'retail';
const _kPriceTierSlots = ['tier_1', 'tier_2', 'tier_3'];

class _PriceTierDropdown extends ConsumerWidget {
  const _PriceTierDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final priceTypes = settingsAsync.valueOrNull?.salePriceTypes ?? const [];

    final labels = <String, String>{_kPriceTierBase: 'Detalle'};
    for (var i = 0; i < _kPriceTierSlots.length && i < priceTypes.length; i++) {
      final name = priceTypes[i].toString().trim();
      if (name.isEmpty) continue;
      labels[_kPriceTierSlots[i]] = name;
    }

    if (!labels.containsKey(value)) {
      labels[value] = '$value (antiguo)';
    }

    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Nivel de precio'),
      items: [
        for (final entry in labels.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
