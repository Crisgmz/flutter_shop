import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/suppliers_repository.dart';
import 'suppliers_providers.dart';

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersListProvider);
    final query = ref.watch(suppliersSearchProvider).trim().toLowerCase();
    final showInactive = ref.watch(suppliersShowInactiveProvider);

    return ModulePage(
      title: 'Proveedores',
      description: 'Catálogo de proveedores y datos de contacto.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(suppliersListProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onCreateSupplier,
          icon: const Icon(Icons.add_business_outlined, size: 18),
          label: const Text('Nuevo proveedor'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(showInactive),
          const SizedBox(height: AppTokens.s24),
          suppliersAsync.when(
            data: (suppliers) {
              final filtered = suppliers
                  .where((supplier) {
                    if (!showInactive && !supplier.isActive) return false;
                    if (query.isEmpty) return true;
                    final searchable = [
                      supplier.legalName,
                      supplier.tradeName ?? '',
                      supplier.rnc ?? '',
                      supplier.documentNumber ?? '',
                      supplier.email ?? '',
                      supplier.contactName ?? '',
                      supplier.city ?? '',
                      supplier.province ?? '',
                    ].join(' ').toLowerCase();
                    return searchable.contains(query);
                  })
                  .toList(growable: false);

              return DataTableShell(
                title: 'Proveedores (${filtered.length})',
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppTokens.s20),
                        child: Text(
                          'No hay proveedores para mostrar.',
                          style: TextStyle(color: AppTokens.mutedForeground),
                        ),
                      )
                    : DataTable(
                        columns: const [
                          DataColumn(label: Text('Nombre legal')),
                          DataColumn(label: Text('Nombre comercial')),
                          DataColumn(label: Text('RNC')),
                          DataColumn(label: Text('Contacto')),
                          DataColumn(label: Text('Teléfono')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Estado')),
                          DataColumn(label: Text('Acciones')),
                        ],
                        rows: filtered
                            .map(
                              (supplier) => DataRow(
                                cells: [
                                  DataCell(Text(
                                    supplier.legalName,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  )),
                                  DataCell(Text(supplier.tradeName ?? '-')),
                                  DataCell(Text(
                                    supplier.rnc ?? '-',
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                  )),
                                  DataCell(Text(supplier.contactName ?? '-')),
                                  DataCell(Text(supplier.phone ?? '-')),
                                  DataCell(Text(supplier.email ?? '-')),
                                  DataCell(StatusBadge(
                                    label: supplier.isActive ? 'Activo' : 'Inactivo',
                                    status: supplier.isActive ? 'active' : 'inactive',
                                  )),
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar',
                                        onPressed: () => _onEditSupplier(supplier),
                                        icon: const Icon(Icons.edit_outlined, size: AppTokens.iconSizeS),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      IconButton(
                                        tooltip: supplier.isActive ? 'Desactivar' : 'Activar',
                                        onPressed: () => _onToggleActive(supplier),
                                        icon: Icon(
                                          supplier.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                                          size: AppTokens.iconSizeS,
                                          color: supplier.isActive ? AppTokens.destructive : AppTokens.success,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  )),
                                ],
                              ),
                            )
                            .toList(growable: false),
                      ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar proveedores: $error',
              onRetry: () => ref.invalidate(suppliersListProvider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool showInactive) {
    final isMobile = ResponsiveLayout.isMobile(context);

    final searchField = TextField(
      controller: _searchController,
      onChanged: (value) =>
          ref.read(suppliersSearchProvider.notifier).state = value,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search, size: 18),
        hintText: 'Buscar por nombre, RNC, email o contacto',
      ),
    );

    final filterChip = FilterChip(
      selected: showInactive,
      label: const Text('Mostrar inactivos'),
      onSelected: (value) =>
          ref.read(suppliersShowInactiveProvider.notifier).state = value,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [searchField, const SizedBox(height: AppTokens.s12), filterChip],
      );
    }

    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: AppTokens.s12),
        filterChip,
      ],
    );
  }

  Future<void> _onCreateSupplier() async {
    final input = await showDialog<SupplierInput>(
      context: context,
      builder: (_) => const _SupplierDialog(),
    );

    if (input == null || !mounted) return;
    await _saveSupplier(input, message: 'Proveedor creado');
  }

  Future<void> _onEditSupplier(SupplierEntity supplier) async {
    final input = await showDialog<SupplierInput>(
      context: context,
      builder: (_) => _SupplierDialog(initial: supplier),
    );

    if (input == null || !mounted) return;
    await _saveSupplier(input, message: 'Proveedor actualizado');
  }

  Future<void> _saveSupplier(
    SupplierInput input, {
    required String message,
  }) async {
    final repository = ref.read(suppliersRepositoryProvider);

    try {
      await repository.saveSupplier(input);
      if (!mounted) return;

      ref.invalidate(suppliersListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar proveedor: $error')),
      );
    }
  }

  Future<void> _onToggleActive(SupplierEntity supplier) async {
    final repository = ref.read(suppliersRepositoryProvider);

    try {
      await repository.setSupplierActive(
        supplierId: supplier.id,
        isActive: !supplier.isActive,
      );

      if (!mounted) return;
      ref.invalidate(suppliersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            supplier.isActive ? 'Proveedor desactivado' : 'Proveedor activado',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar proveedor: $error')),
      );
    }
  }
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({this.initial});

  final SupplierEntity? initial;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _legalNameController;
  late final TextEditingController _tradeNameController;
  late final TextEditingController _rncController;
  late final TextEditingController _contactController;
  late final TextEditingController _phoneController;
  late final TextEditingController _secondaryPhoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _documentNumberController;
  late final TextEditingController _paymentTermsController;
  late final TextEditingController _commentsController;

  String _documentType = 'rnc';
  bool _isActive = true;

  static const _docTypes = ['rnc', 'cedula', 'pasaporte', 'otro'];

  @override
  void initState() {
    super.initState();
    final s = widget.initial;

    _legalNameController = TextEditingController(text: s?.legalName ?? '');
    _tradeNameController = TextEditingController(text: s?.tradeName ?? '');
    _rncController = TextEditingController(text: s?.rnc ?? '');
    _contactController = TextEditingController(text: s?.contactName ?? '');
    _phoneController = TextEditingController(text: s?.phone ?? '');
    _secondaryPhoneController = TextEditingController(text: s?.secondaryPhone ?? '');
    _emailController = TextEditingController(text: s?.email ?? '');
    _addressController = TextEditingController(text: s?.address ?? '');
    _cityController = TextEditingController(text: s?.city ?? '');
    _provinceController = TextEditingController(text: s?.province ?? '');
    _postalCodeController = TextEditingController(text: s?.postalCode ?? '');
    _documentNumberController = TextEditingController(text: s?.documentNumber ?? '');
    _paymentTermsController = TextEditingController(
      text: (s?.paymentTermsDays ?? 0).toString(),
    );
    _commentsController = TextEditingController(text: s?.comments ?? '');

    _documentType = s?.documentType ?? 'rnc';
    _isActive = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _legalNameController.dispose();
    _tradeNameController.dispose();
    _rncController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _secondaryPhoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _postalCodeController.dispose();
    _documentNumberController.dispose();
    _paymentTermsController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo proveedor' : 'Editar proveedor'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // — Identificación —
                _sectionHeader('Identificación'),
                TextFormField(
                  controller: _legalNameController,
                  decoration: const InputDecoration(labelText: 'Nombre legal *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _tradeNameController,
                  decoration: const InputDecoration(labelText: 'Nombre comercial'),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _rncController,
                    decoration: const InputDecoration(labelText: 'RNC'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _docTypes.contains(_documentType) ? _documentType : 'rnc',
                    decoration: const InputDecoration(labelText: 'Tipo documento adicional'),
                    items: _docTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.toUpperCase())))
                        .toList(growable: false),
                    onChanged: (v) => setState(() => _documentType = v ?? 'rnc'),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _documentNumberController,
                  decoration: const InputDecoration(labelText: 'Número de documento adicional'),
                ),

                // — Contacto —
                _sectionHeader('Contacto'),
                TextFormField(
                  controller: _contactController,
                  decoration: const InputDecoration(labelText: 'Persona de contacto'),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Teléfono principal'),
                  ),
                  TextFormField(
                    controller: _secondaryPhoneController,
                    decoration: const InputDecoration(labelText: 'Teléfono secundario'),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (!v.contains('@')) return 'Correo inválido';
                    return null;
                  },
                ),

                // — Ubicación —
                _sectionHeader('Ubicación'),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Dirección'),
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
                TextFormField(
                  controller: _postalCodeController,
                  decoration: const InputDecoration(labelText: 'Código postal'),
                ),

                // — Condiciones comerciales —
                _sectionHeader('Condiciones comerciales'),
                TextFormField(
                  controller: _paymentTermsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Días de crédito',
                    hintText: '0 = pago inmediato',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (int.tryParse(v.trim()) == null) return 'Debe ser un número';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _commentsController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Comentarios'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
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
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.5,
          color: AppTokens.mutedForeground,
        ),
      ),
    );
  }

  Widget _formRow(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children: children
            .expand((w) => [w, const SizedBox(height: 10)])
            .toList()
          ..removeLast(),
      );
    }
    return Row(
      children: children
          .expand((w) => [Expanded(child: w), const SizedBox(width: 10)])
          .toList()
        ..removeLast(),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      SupplierInput(
        id: widget.initial?.id,
        legalName: _legalNameController.text,
        tradeName: _tradeNameController.text,
        rnc: _rncController.text,
        contactName: _contactController.text,
        phone: _phoneController.text,
        secondaryPhone: _secondaryPhoneController.text,
        email: _emailController.text,
        address: _addressController.text,
        city: _cityController.text,
        province: _provinceController.text,
        postalCode: _postalCodeController.text,
        documentType: _documentType,
        documentNumber: _documentNumberController.text,
        paymentTermsDays: int.tryParse(_paymentTermsController.text.trim()) ?? 0,
        comments: _commentsController.text,
        isActive: _isActive,
      ),
    );
  }
}
