import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/file_io_helper.dart';
import '../data/inventory_excel_service.dart';
import '../data/inventory_repository.dart';
import 'inventory_providers.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(inventoryProductsProvider);
    final categoriesAsync = ref.watch(inventoryCategoriesProvider);
    final lowStockOnly = ref.watch(inventoryLowStockOnlyProvider);
    final selectedCategoryId = ref.watch(inventorySelectedCategoryProvider);
    final query = ref.watch(inventorySearchProvider).trim().toLowerCase();
    final isMobile = ResponsiveLayout.isMobile(context);

    return ModulePage(
      title: 'Inventario',
      description: 'Gestión centralizada de productos y existencias.',
      actions: [
        OutlinedButton.icon(
          onPressed: _refreshInventoryData,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        _buildExcelMenu(),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onCreateProduct,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nuevo Producto'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Bar
          Container(
            decoration: BoxDecoration(
              color: AppTokens.card,
              borderRadius: BorderRadius.circular(AppTokens.radius),
              border: Border.all(color: AppTokens.border),
            ),
            padding: const EdgeInsets.all(AppTokens.s16),
            child: isMobile
                ? Column(
                    children: [
                      _buildSearchField(),
                      const SizedBox(height: AppTokens.s12),
                      _buildCategoryDropdown(categoriesAsync, selectedCategoryId),
                      const SizedBox(height: AppTokens.s12),
                      _buildLowStockToggle(lowStockOnly),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(flex: 3, child: _buildSearchField()),
                      const SizedBox(width: AppTokens.s16),
                      Expanded(
                        flex: 2,
                        child: _buildCategoryDropdown(categoriesAsync, selectedCategoryId),
                      ),
                      const SizedBox(width: AppTokens.s16),
                      _buildLowStockToggle(lowStockOnly),
                    ],
                  ),
          ),
          const SizedBox(height: AppTokens.s24),
          
          // Products List/Table
          productsAsync.when(
            data: (products) {
              final filtered = products.where((product) {
                if (lowStockOnly && !product.isLowStock) return false;
                if (selectedCategoryId != null && product.categoryId != selectedCategoryId) {
                  return false;
                }
                if (query.isEmpty) return true;
                final searchable = [
                  product.name,
                  product.sku ?? '',
                  product.barcode ?? '',
                  product.categoryName ?? '',
                ].join(' ').toLowerCase();
                return searchable.contains(query);
              }).toList();

              if (filtered.isEmpty) {
                return const EmptyStateCard(
                  icon: Icons.inventory_2_outlined,
                  message: 'No se encontraron productos con los filtros aplicados.',
                );
              }

              if (isMobile) {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppTokens.s12),
                  itemBuilder: (context, index) => _InventoryProductCard(
                    product: filtered[index],
                    onEdit: () => _onEditProduct(filtered[index]),
                    onToggle: () => _onToggleActive(filtered[index]),
                  ),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: AppTokens.card,
                  borderRadius: BorderRadius.circular(AppTokens.radius),
                  border: Border.all(color: AppTokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppTokens.s20),
                      child: Text(
                        'Productos (${filtered.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataTableShell(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(AppTokens.background),
                        columns: const [
                          DataColumn(label: Text('Producto')),
                          DataColumn(label: Text('SKU')),
                          DataColumn(label: Text('Categoría')),
                          DataColumn(label: Text('Precio')),
                          DataColumn(label: Text('Stock')),
                          DataColumn(label: Text('Estado')),
                          DataColumn(label: Text('Acciones')),
                        ],
                        rows: filtered.map((product) => DataRow(
                          cells: [
                            DataCell(Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(product.sku ?? '-')),
                            DataCell(Text(product.categoryName ?? '-')),
                            DataCell(Text(money(product.price))),
                            DataCell(Text(
                              qty(product.stock),
                              style: TextStyle(
                                color: product.isLowStock ? AppTokens.error : null,
                                fontWeight: product.isLowStock ? FontWeight.bold : null,
                              ),
                            )),
                            DataCell(StatusBadge(
                              label: product.isActive ? 'Activo' : 'Inactivo',
                              status: product.isActive ? 'active' : 'inactive',
                            )),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _onEditProduct(product),
                                ),
                                IconButton(
                                  icon: Icon(
                                    product.isActive ? Icons.block : Icons.check_circle_outline,
                                    size: 20,
                                    color: product.isActive ? AppTokens.error : AppTokens.success,
                                  ),
                                  onPressed: () => _onToggleActive(product),
                                ),
                              ],
                            )),
                          ],
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'Error al cargar inventario: $error',
              onRetry: _refreshInventoryData,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => ref.read(inventorySearchProvider.notifier).state = v,
      decoration: const InputDecoration(
        hintText: 'Buscar por nombre, SKU...',
        prefixIcon: Icon(Icons.search, size: 18),
      ),
    );
  }

  Widget _buildCategoryDropdown(AsyncValue<List<InventoryCategory>> categoriesAsync, String? selectedId) {
    return categoriesAsync.when(
      data: (categories) => DropdownButtonFormField<String>(
        value: selectedId ?? '',
        decoration: const InputDecoration(labelText: 'Categoría'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todas las categorías')),
          ...categories.map(
            (c) => DropdownMenuItem(
              value: c.id,
              child: Row(
                children: [
                  if (c.colorHex != null) ...[
                    _CategoryColorDot(colorHex: c.colorHex!),
                    const SizedBox(width: 8),
                  ],
                  Text(c.name),
                ],
              ),
            ),
          ),
        ],
        onChanged: (v) => ref.read(inventorySelectedCategoryProvider.notifier).state = (v == null || v.isEmpty) ? null : v,
      ),
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLowStockToggle(bool value) {
    return FilterChip(
      selected: value,
      label: const Text('Bajo Stock'),
      onSelected: (v) => ref.read(inventoryLowStockOnlyProvider.notifier).state = v,
    );
  }


  Future<void> _refreshInventoryData() async {
    ref.invalidate(inventoryProductsProvider);
    ref.invalidate(inventoryCategoriesProvider);
    await Future.wait([
      ref.read(inventoryProductsProvider.future),
      ref.read(inventoryCategoriesProvider.future),
    ]);
  }

  Future<void> _onCreateProduct() async {
    final categories = await _readCategoriesOrShowError();
    if (categories == null || !mounted) return;

    final input = await showDialog<InventoryProductInput>(
      context: context,
      builder: (_) => _ProductDialog(categories: categories),
    );

    if (input == null || !mounted) return;

    await _saveProduct(input, successMessage: 'Producto creado');
  }

  Future<void> _onEditProduct(InventoryProduct product) async {
    final categories = await _readCategoriesOrShowError();
    if (categories == null || !mounted) return;

    final input = await showDialog<InventoryProductInput>(
      context: context,
      builder: (_) => _ProductDialog(categories: categories, initial: product),
    );

    if (input == null || !mounted) return;

    await _saveProduct(input, successMessage: 'Producto actualizado');
  }

  Future<void> _onToggleActive(InventoryProduct product) async {
    final repository = ref.read(inventoryRepositoryProvider);

    try {
      await repository.setProductActive(
        productId: product.id,
        isActive: !product.isActive,
      );

      if (!mounted) return;

      ref.invalidate(inventoryProductsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product.isActive ? 'Producto desactivado' : 'Producto activado',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar estado: $error')),
      );
    }
  }

  Future<void> _saveProduct(
    InventoryProductInput input, {
    required String successMessage,
  }) async {
    final repository = ref.read(inventoryRepositoryProvider);

    try {
      await repository.saveProduct(input);
      if (!mounted) return;

      ref.invalidate(inventoryProductsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar producto: $error')),
      );
    }
  }

  Future<List<InventoryCategory>?> _readCategoriesOrShowError() async {
    try {
      return await ref.read(inventoryCategoriesProvider.future);
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar categorías: $error')),
      );
      return null;
    }
  }

  Widget _buildExcelMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Excel',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'template':
            _onDownloadTemplate();
            break;
          case 'export':
            _onExportInventory();
            break;
          case 'import':
            _onImportInventory();
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'template',
          child: ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('Descargar plantilla'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.file_download_outlined),
            title: Text('Exportar inventario'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'import',
          child: ListTile(
            leading: Icon(Icons.file_upload_outlined),
            title: Text('Importar inventario'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.table_chart_outlined, size: 18),
        label: const Text('Excel'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.foreground,
          disabledForegroundColor: AppTokens.foreground,
        ),
      ),
    );
  }

  Future<void> _onDownloadTemplate() async {
    final categories = await _readCategoriesOrShowError();
    if (categories == null || !mounted) return;

    try {
      final bytes = InventoryExcelService().buildTemplate(
        categories: categories,
      );
      final fileName =
          'plantilla_inventario_${_timestamp()}.xlsx';
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: fileName,
        dialogTitle: 'Guardar plantilla de inventario',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plantilla generada')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la plantilla: $error')),
      );
    }
  }

  Future<void> _onExportInventory() async {
    final categories = await _readCategoriesOrShowError();
    if (categories == null || !mounted) return;

    final List<InventoryProduct> products;
    try {
      products = await ref.read(inventoryProductsProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar productos: $error')),
      );
      return;
    }

    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay productos para exportar.'),
        ),
      );
      return;
    }

    try {
      final bytes = InventoryExcelService().buildExport(
        products: products,
        categories: categories,
      );
      final fileName = 'inventario_${_timestamp()}.xlsx';
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: fileName,
        dialogTitle: 'Guardar inventario',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inventario exportado (${products.length} productos)'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar: $error')),
      );
    }
  }

  Future<void> _onImportInventory() async {
    final categories = await _readCategoriesOrShowError();
    if (categories == null || !mounted) return;

    final Uint8List? bytes;
    try {
      bytes = await FileIoHelper.pickXlsxBytes();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el archivo: $error')),
      );
      return;
    }
    if (bytes == null || !mounted) return;

    final InventoryImportParseResult parsed;
    try {
      parsed = InventoryExcelService().parseImport(
        bytes: bytes,
        categories: categories,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archivo inválido: $error')),
      );
      return;
    }

    if (parsed.totalRows == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El archivo no contiene filas con datos.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ImportPreviewDialog(parseResult: parsed),
    );
    if (confirmed != true || !mounted) return;
    if (parsed.inputs.isEmpty) return;

    final repository = ref.read(inventoryRepositoryProvider);
    final InventoryBulkUpsertResult result;
    try {
      result = await repository.bulkUpsertProducts(parsed.inputs);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error durante la importación: $error')),
      );
      return;
    }

    if (!mounted) return;
    ref.invalidate(inventoryProductsProvider);
    await showDialog<void>(
      context: context,
      builder: (_) => _ImportResultDialog(
        result: result,
        parseErrors: parsed.errors,
      ),
    );
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }
}

/// Mobile card for a single product.
class _InventoryProductCard extends StatelessWidget {
  const _InventoryProductCard({
    required this.product,
    required this.onEdit,
    required this.onToggle,
  });

  final InventoryProduct product;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                StatusBadge(
                  label: product.isActive ? 'Activo' : 'Inactivo',
                  status: product.isActive ? 'active' : 'inactive',
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s8),
            Text(
              'SKU: ${product.sku ?? '-'} · ${product.categoryName ?? 'Sin categoría'}',
              style: const TextStyle(color: AppTokens.mutedForeground, fontSize: 13),
            ),
            const Divider(height: AppTokens.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfo('Precio', money(product.price)),
                _buildInfo('Stock', qty(product.stock), isBad: product.isLowStock),
              ],
            ),
            const SizedBox(height: AppTokens.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: Icon(
                    product.isActive ? Icons.block : Icons.check_circle_outline,
                    size: 20,
                    color: product.isActive ? AppTokens.error : AppTokens.success,
                  ),
                  onPressed: onToggle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(String label, String value, {bool isBad = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTokens.mutedForeground)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isBad ? AppTokens.error : null,
          ),
        ),
      ],
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.categories, this.initial});

  final List<InventoryCategory> categories;
  final InventoryProduct? initial;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _internalCodeController;
  late final TextEditingController _unitController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;
  late final TextEditingController _stockController;
  late final TextEditingController _minStockController;
  late final TextEditingController _taxController;
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _notesController;
  late final TextEditingController _imageUrlController;

  String? _categoryId;
  bool _isActive = true;
  bool _isService = false;
  bool _isTaxExempt = false;
  bool _trackInventory = true;

  @override
  void initState() {
    super.initState();
    final product = widget.initial;

    _nameController = TextEditingController(text: product?.name ?? '');
    _skuController = TextEditingController(text: product?.sku ?? '');
    _barcodeController = TextEditingController(text: product?.barcode ?? '');
    _internalCodeController = TextEditingController(text: product?.internalCode ?? '');
    _unitController = TextEditingController(text: product?.unit ?? 'unidad');
    _priceController = TextEditingController(
      text: product == null ? '' : product.price.toString(),
    );
    _costController = TextEditingController(
      text: product == null ? '0' : product.cost.toString(),
    );
    _stockController = TextEditingController(
      text: product == null ? '0' : product.stock.toString(),
    );
    _minStockController = TextEditingController(
      text: product == null ? '0' : product.minStock.toString(),
    );
    _taxController = TextEditingController(
      text: product == null ? '18' : product.taxRate.toString(),
    );
    _brandController = TextEditingController(text: product?.brand ?? '');
    _modelController = TextEditingController(text: product?.model ?? '');
    _notesController = TextEditingController(text: product?.notes ?? '');
    _imageUrlController = TextEditingController(text: product?.imageUrl ?? '');

    _categoryId = product?.categoryId;
    _isActive = product?.isActive ?? true;
    _isService = product?.isService ?? false;
    _isTaxExempt = product?.isTaxExempt ?? false;
    _trackInventory = product?.trackInventory ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _internalCodeController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _taxController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _notesController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Nuevo producto' : 'Editar producto',
      ),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa el nombre';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                if (isMobile) ...[
                  TextFormField(
                    controller: _skuController,
                    decoration: const InputDecoration(labelText: 'SKU'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _barcodeController,
                    decoration: const InputDecoration(
                      labelText: 'Código de barra',
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _skuController,
                          decoration: const InputDecoration(labelText: 'SKU'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'Código de barra',
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _internalCodeController,
                  decoration: const InputDecoration(labelText: 'Código interno'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId ?? '',
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Sin categoría'),
                    ),
                    ...widget.categories.map(
                      (category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Row(
                          children: [
                            if (category.colorHex != null) ...[
                              _CategoryColorDot(colorHex: category.colorHex!),
                              const SizedBox(width: 8),
                            ],
                            Text(category.name),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _categoryId = (value == null || value.isEmpty)
                        ? null
                        : value,
                  ),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _brandController,
                    decoration: const InputDecoration(labelText: 'Marca'),
                  ),
                  TextFormField(
                    controller: _modelController,
                    decoration: const InputDecoration(labelText: 'Modelo'),
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Precio'),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Precio inválido';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _costController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Costo'),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Costo inválido';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _stockController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Stock'),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null) return 'Stock inválido';
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _minStockController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Stock mínimo',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Mínimo inválido';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _taxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'ITBIS %'),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0 || parsed > 100) {
                        return 'Impuesto inválido';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _unitController,
                    decoration: const InputDecoration(labelText: 'Unidad'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Unidad requerida';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL de imagen',
                    hintText: 'https://...',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notas'),
                  maxLines: 2,
                  minLines: 1,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Activo'),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  value: _isService,
                  onChanged: (value) => setState(() {
                    _isService = value;
                    if (value) _trackInventory = false;
                  }),
                  title: const Text('Es servicio'),
                  subtitle: const Text('No lleva control de inventario físico'),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  value: _isTaxExempt,
                  onChanged: (value) => setState(() => _isTaxExempt = value),
                  title: const Text('Exento de ITBIS'),
                  contentPadding: EdgeInsets.zero,
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

  /// On mobile, stack fields vertically; on desktop, side-by-side.
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final input = InventoryProductInput(
      id: widget.initial?.id,
      name: _nameController.text,
      sku: _skuController.text,
      barcode: _barcodeController.text,
      internalCode: _internalCodeController.text,
      categoryId: _categoryId,
      unit: _unitController.text,
      cost: double.parse(_costController.text),
      price: double.parse(_priceController.text),
      taxRate: double.parse(_taxController.text),
      stock: double.parse(_stockController.text),
      minStock: double.parse(_minStockController.text),
      isActive: _isActive,
      brand: _brandController.text,
      model: _modelController.text,
      notes: _notesController.text,
      imageUrl: _imageUrlController.text,
      isService: _isService,
      isTaxExempt: _isTaxExempt,
      trackInventory: _trackInventory,
    );

    Navigator.of(context).pop(input);
  }
}

/// Small colored circle shown next to category names when a color_hex is set.
class _CategoryColorDot extends StatelessWidget {
  const _CategoryColorDot({required this.colorHex});

  final String colorHex;

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(colorHex);
    if (color == null) return const SizedBox.shrink();
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  static Color? _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return null;
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return value == null ? null : Color(value);
  }
}

class _ImportPreviewDialog extends StatelessWidget {
  const _ImportPreviewDialog({required this.parseResult});

  final InventoryImportParseResult parseResult;

  @override
  Widget build(BuildContext context) {
    final hasValid = parseResult.inputs.isNotEmpty;
    final hasErrors = parseResult.errors.isNotEmpty;

    return AlertDialog(
      title: const Text('Vista previa de importación'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filas leídas: ${parseResult.totalRows}\n'
              'Filas válidas: ${parseResult.inputs.length}\n'
              'Filas con error: ${parseResult.errors.length}',
            ),
            const SizedBox(height: AppTokens.s12),
            if (hasErrors) ...[
              const Text(
                'Errores detectados:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppTokens.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: parseResult.errors
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTokens.s4,
                            ),
                            child: Text(
                              'Fila ${e.rowNumber}: ${e.message}',
                              style: const TextStyle(
                                color: AppTokens.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s12),
            ],
            if (hasValid)
              const Text(
                'Las filas válidas se importarán. Las filas con error se ignorarán.',
                style: TextStyle(color: AppTokens.mutedForeground),
              )
            else
              const Text(
                'No hay filas válidas para importar.',
                style: TextStyle(color: AppTokens.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: hasValid
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(
            hasValid ? 'Importar ${parseResult.inputs.length}' : 'Importar',
          ),
        ),
      ],
    );
  }
}

class _ImportResultDialog extends StatelessWidget {
  const _ImportResultDialog({
    required this.result,
    required this.parseErrors,
  });

  final InventoryBulkUpsertResult result;
  final List<InventoryImportRowError> parseErrors;

  @override
  Widget build(BuildContext context) {
    final hasDbErrors = result.errors.isNotEmpty;
    final hasParseErrors = parseErrors.isNotEmpty;

    return AlertDialog(
      title: const Text('Importación completada'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productos creados: ${result.inserted}\n'
              'Productos actualizados: ${result.updated}',
            ),
            if (hasDbErrors || hasParseErrors) ...[
              const SizedBox(height: AppTokens.s12),
              const Text(
                'Errores:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppTokens.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...parseErrors.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppTokens.s4,
                          ),
                          child: Text(
                            'Fila ${e.rowNumber}: ${e.message}',
                            style: const TextStyle(
                              color: AppTokens.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      ...result.errors.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppTokens.s4,
                          ),
                          child: Text(
                            '${e.productName}: ${e.message}',
                            style: const TextStyle(
                              color: AppTokens.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
