import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/clients_repository.dart';
import 'clients_providers.dart';

const _receiptTypeLabels = <String, String>{
  'consumer_final': 'Consumidor final',
  'fiscal_credit': 'Crédito fiscal',
  'governmental': 'Gubernamental',
  'special': 'Especial',
  'export': 'Exportación',
};

class ClientsPage extends ConsumerStatefulWidget {
  const ClientsPage({super.key});

  @override
  ConsumerState<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends ConsumerState<ClientsPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsListProvider);
    final query = ref.watch(clientsSearchProvider).trim().toLowerCase();
    final showInactive = ref.watch(clientsShowInactiveProvider);

    return ModulePage(
      title: 'Clientes',
      description: 'Catálogo de clientes y cuentas por cobrar.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(clientsListProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onCreateClient,
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text('Nuevo cliente'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(showInactive),
          const SizedBox(height: AppTokens.s24),
          clientsAsync.when(
            data: (clients) {
              final filtered = clients
                  .where((client) {
                    if (!showInactive && !client.isActive) return false;
                    if (query.isEmpty) return true;
                    final searchable = [
                      client.fullName,
                      client.firstName ?? '',
                      client.lastName ?? '',
                      client.companyName ?? '',
                      client.documentNumber ?? '',
                      client.email ?? '',
                      client.phone ?? '',
                    ].join(' ').toLowerCase();
                    return searchable.contains(query);
                  })
                  .toList(growable: false);

              final totalBalance = filtered.fold<double>(
                0,
                (sum, item) => sum + item.balanceDue,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KpisGrid(
                    totalClients: filtered.length,
                    totalBalance: totalBalance,
                  ),
                  const SizedBox(height: AppTokens.s24),
                  DataTableShell(
                    title: 'Clientes (${filtered.length})',
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(AppTokens.s20),
                            child: Text(
                              'No hay clientes que coincidan con el filtro.',
                              style: TextStyle(
                                color: AppTokens.mutedForeground,
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Nombre')),
                                DataColumn(label: Text('Tipo')),
                                DataColumn(label: Text('Documento')),
                                DataColumn(label: Text('Teléfono')),
                                DataColumn(label: Text('Email')),
                                DataColumn(
                                  label: Text('Límite crédito'),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text('Balance'),
                                  numeric: true,
                                ),
                                DataColumn(label: Text('Estado')),
                                DataColumn(label: Text('Acciones')),
                              ],
                              rows: filtered
                                  .map(
                                    (client) => DataRow(
                                      cells: [
                                        DataCell(Text(
                                          client.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )),
                                        DataCell(
                                          Text(_entityTypeLabel(client.entityType)),
                                        ),
                                        DataCell(Text(
                                          _documentDisplay(client),
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        )),
                                        DataCell(
                                          Text(client.phone ?? '-'),
                                        ),
                                        DataCell(
                                          Text(client.email ?? '-'),
                                        ),
                                        DataCell(
                                          Text(money(client.creditLimit)),
                                        ),
                                        DataCell(Text(
                                          money(client.balanceDue),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: client.balanceDue > 0
                                                ? AppTokens.warning
                                                : null,
                                          ),
                                        )),
                                        DataCell(StatusBadge(
                                          label: client.isActive
                                              ? 'Activo'
                                              : 'Inactivo',
                                          status: client.isActive
                                              ? 'active'
                                              : 'inactive',
                                        )),
                                        DataCell(Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Editar',
                                              onPressed: () =>
                                                  _onEditClient(client),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: AppTokens.iconSizeS,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            IconButton(
                                              tooltip: client.isActive
                                                  ? 'Desactivar'
                                                  : 'Activar',
                                              onPressed: () =>
                                                  _onToggleActive(client),
                                              icon: Icon(
                                                client.isActive
                                                    ? Icons.block_outlined
                                                    : Icons
                                                        .check_circle_outline,
                                                size: AppTokens.iconSizeS,
                                                color: client.isActive
                                                    ? AppTokens.destructive
                                                    : AppTokens.success,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ],
                                        )),
                                      ],
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar clientes: $error',
              onRetry: () => ref.invalidate(clientsListProvider),
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
          ref.read(clientsSearchProvider.notifier).state = value,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search, size: 18),
        hintText: 'Buscar por nombre, documento, email o teléfono',
      ),
    );

    final filterChip = FilterChip(
      selected: showInactive,
      label: const Text('Mostrar inactivos'),
      onSelected: (value) =>
          ref.read(clientsShowInactiveProvider.notifier).state = value,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          searchField,
          const SizedBox(height: AppTokens.s12),
          filterChip,
        ],
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

  String _documentDisplay(ClientEntity client) {
    final parts = [
      client.documentType ?? '',
      client.documentNumber ?? '',
    ].where((part) => part.isNotEmpty);
    return parts.isEmpty ? '-' : parts.join(': ');
  }

  Future<void> _onCreateClient() async {
    final input = await showDialog<ClientInput>(
      context: context,
      builder: (_) => const _ClientDialog(),
    );
    if (input == null || !mounted) return;
    await _saveClient(input, successMessage: 'Cliente creado');
  }

  Future<void> _onEditClient(ClientEntity client) async {
    final input = await showDialog<ClientInput>(
      context: context,
      builder: (_) => _ClientDialog(initial: client),
    );
    if (input == null || !mounted) return;
    await _saveClient(input, successMessage: 'Cliente actualizado');
  }

  Future<void> _saveClient(
    ClientInput input, {
    required String successMessage,
  }) async {
    final repository = ref.read(clientsRepositoryProvider);
    try {
      await repository.saveClient(input);
      if (!mounted) return;
      ref.invalidate(clientsListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar cliente: $error')),
      );
    }
  }

  Future<void> _onToggleActive(ClientEntity client) async {
    final repository = ref.read(clientsRepositoryProvider);
    try {
      await repository.setClientActive(
        clientId: client.id,
        isActive: !client.isActive,
      );
      if (!mounted) return;
      ref.invalidate(clientsListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            client.isActive ? 'Cliente desactivado' : 'Cliente activado',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar cliente: $error')),
      );
    }
  }
}

// ─── KPIs ────────────────────────────────────────────────────────────────────

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.totalClients, required this.totalBalance});

  final int totalClients;
  final double totalBalance;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Clientes',
        value: totalClients.toString(),
        icon: Icons.people_outline_rounded,
        trend: 'Registrados',
      ),
      KPICard(
        label: 'Balance por cobrar',
        value: money(totalBalance),
        icon: Icons.attach_money_rounded,
        trend: 'Total pendiente',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppTokens.breakpointCompact) {
          return Column(
            children: [
              cards[0],
              const SizedBox(height: AppTokens.s12),
              cards[1],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

// ─── Client dialog ───────────────────────────────────────────────────────────

class _ClientDialog extends StatefulWidget {
  const _ClientDialog({this.initial});

  final ClientEntity? initial;

  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<_ClientDialog> {
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

  @override
  void initState() {
    super.initState();
    final c = widget.initial;

    _fullNameController = TextEditingController(text: c?.fullName ?? '');
    _firstNameController = TextEditingController(text: c?.firstName ?? '');
    _lastNameController = TextEditingController(text: c?.lastName ?? '');
    _companyNameController = TextEditingController(text: c?.companyName ?? '');
    _legalNameController = TextEditingController(text: c?.legalName ?? '');
    _documentTypeController =
        TextEditingController(text: c?.documentType ?? '');
    _documentNumberController =
        TextEditingController(text: c?.documentNumber ?? '');

    _emailController = TextEditingController(text: c?.email ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _secondaryPhoneController =
        TextEditingController(text: c?.secondaryPhone ?? '');

    _addressLine1Controller =
        TextEditingController(text: c?.addressLine1 ?? c?.address ?? '');
    _addressLine2Controller =
        TextEditingController(text: c?.addressLine2 ?? '');
    _cityController = TextEditingController(text: c?.city ?? '');
    _provinceController = TextEditingController(text: c?.province ?? '');
    _postalCodeController = TextEditingController(text: c?.postalCode ?? '');
    _countryCodeController =
        TextEditingController(text: c?.countryCode ?? 'DO');
    _googleMapsUrlController =
        TextEditingController(text: c?.googleMapsUrl ?? '');

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

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Nuevo cliente' : 'Editar cliente',
      ),
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
                    DropdownMenuItem(
                      value: 'person',
                      child: Text('Persona'),
                    ),
                    DropdownMenuItem(
                      value: 'company',
                      child: Text('Empresa'),
                    ),
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
                    decoration: const InputDecoration(
                      labelText: 'Número documento',
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
                DropdownButtonFormField<String>(
                  initialValue: _priceTier,
                  decoration: const InputDecoration(
                    labelText: 'Nivel de precio',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'retail',
                      child: Text('Detalle'),
                    ),
                    DropdownMenuItem(
                      value: 'wholesale',
                      child: Text('Mayoreo'),
                    ),
                    DropdownMenuItem(value: 'vip', child: Text('VIP')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _priceTier = value);
                  },
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
        creditInvoiceLimit:
            int.parse(_creditInvoiceLimitController.text.trim()),
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

String _entityTypeLabel(String type) {
  switch (type) {
    case 'person':
      return 'Persona';
    case 'company':
      return 'Empresa';
    case 'government':
      return 'Gubernamental';
    default:
      return type;
  }
}

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
