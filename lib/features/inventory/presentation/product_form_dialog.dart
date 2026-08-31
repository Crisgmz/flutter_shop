import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/pricing/margin.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/file_io_helper.dart';
import '../data/inventory_repository.dart';
import 'inventory_providers.dart';

/// Formulario completo de producto (alta y edición). Vive aparte de
/// `inventory_page.dart` porque el Punto de Venta lo abre para crear un
/// producto sin salir de la venta, igual que hace con el formulario de clientes.
class ProductFormDialog extends ConsumerStatefulWidget {
  const ProductFormDialog({super.key, required this.categories, this.initial});

  final List<InventoryCategory> categories;
  final InventoryProduct? initial;

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _internalCodeController;
  late final TextEditingController _unitController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;

  /// Margen % sobre el costo. No se guarda en la DB: es una ayuda de captura
  /// que escribe el precio (costo + costo × %). Ver `shared/pricing/margin.dart`.
  late final TextEditingController _marginController;
  late final TextEditingController _stockController;
  late final TextEditingController _minStockController;
  late final TextEditingController _taxController;
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _notesController;
  late final TextEditingController _imageUrlController;
  final TextEditingController _imeiController = TextEditingController();
  final List<String> _imeis = [];
  /// Controllers de los 10 tiers de precio. Cada índice 0..9 corresponde al
  /// tier 1..10. Si el tier no está nombrado en app_settings.sale_price_types,
  /// el `_PriceTierFields` no renderiza ese input.
  late final List<TextEditingController> _priceTierControllers;

  String? _categoryId;
  bool _isActive = true;
  bool _isService = false;
  bool _isTaxExempt = false;
  bool _priceIncludesTax = false;
  bool _trackInventory = true;
  bool _uploadingImage = false;

  /// products.imei_on_purchase — si está prendido, la compra de este producto
  /// abre el cuadro para escribir los IMEIs que entran.
  bool _imeiOnPurchase = false;

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
    // Al editar, se muestra el margen que ya tiene el producto (precio vs
    // costo) para poder subirlo/bajarlo sin sacar la cuenta a mano.
    final initialMargin = product == null
        ? null
        : marginFromPrice(product.cost, product.price);
    _marginController = TextEditingController(
      text: initialMargin == null ? '' : formatMargin(initialMargin),
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
    _priceTierControllers = List.generate(
      10,
      (i) => TextEditingController(
        text: product?.priceTier(i + 1)?.toString() ?? '0',
      ),
    );

    _categoryId = product?.categoryId;
    _isActive = product?.isActive ?? true;
    // Producto nuevo: arranca con el default global de "es servicio"
    // (app_settings.inv_default_is_service). Al editar manda el producto.
    _isService = product?.isService ??
        (ref.read(appSettingsProvider).valueOrNull?.invDefaultIsService ??
            false);
    _isTaxExempt = product?.isTaxExempt ?? false;
    _priceIncludesTax = product?.priceIncludesTax ?? false;
    // Un servicio no lleva control de inventario.
    _trackInventory = product?.trackInventory ?? !_isService;
    _imeis.addAll(product?.imeis ?? const <String>[]);
    _imeiOnPurchase = product?.imeiOnPurchase ?? false;
  }

  void _addImei() {
    final value = _imeiController.text.trim();
    if (value.isEmpty || _imeis.contains(value)) {
      _imeiController.clear();
      return;
    }
    setState(() {
      _imeis.add(value);
      _imeiController.clear();
    });
  }

  /// Costo o margen cambiaron → se reescribe el precio (costo + costo × %).
  /// Si el margen está vacío no se toca el precio: el usuario lo fija a mano.
  void _recalcPriceFromMargin() {
    final marginText = _marginController.text.trim();
    if (marginText.isEmpty) return;
    final margin = double.tryParse(marginText);
    final cost = double.tryParse(_costController.text.trim());
    if (margin == null || cost == null) return;
    _priceController.text = priceFromMargin(cost, margin).toStringAsFixed(2);
  }

  /// El precio se escribió a mano → el margen mostrado se ajusta a ese precio
  /// (sin costo no hay margen que mostrar, así que se limpia).
  void _recalcMarginFromPrice() {
    final cost = double.tryParse(_costController.text.trim()) ?? 0;
    final price = double.tryParse(_priceController.text.trim());
    if (price == null) return;
    final margin = marginFromPrice(cost, price);
    _marginController.text = margin == null ? '' : formatMargin(margin);
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
    _marginController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _taxController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _notesController.dispose();
    _imageUrlController.dispose();
    _imeiController.dispose();
    for (final ctrl in _priceTierControllers) {
      ctrl.dispose();
    }
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
                // IMEI: agregar uno o varios (para celulares/dispositivos).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _imeiController,
                        decoration: InputDecoration(
                          labelText: _imeis.isEmpty
                              ? 'IMEI'
                              : 'IMEI (${_imeis.length} agregado'
                                  '${_imeis.length == 1 ? '' : 's'})',
                          hintText: 'Escribe un IMEI y presiona +',
                        ),
                        onSubmitted: (_) => _addImei(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Agregar IMEI',
                      icon: const Icon(Icons.add_circle, color: AppTokens.primary),
                      onPressed: _addImei,
                    ),
                  ],
                ),
                if (_imeis.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final imei in _imeis)
                        Chip(
                          label: Text(imei,
                              style: const TextStyle(fontSize: 12)),
                          onDeleted: () => setState(() => _imeis.remove(imei)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                SwitchListTile(
                  value: _imeiOnPurchase,
                  onChanged: (value) =>
                      setState(() => _imeiOnPurchase = value),
                  title: const Text('Agregar IMEI en la compra'),
                  subtitle: const Text(
                    'Al comprar este producto se piden los IMEIs de los '
                    'equipos que entran.',
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
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
                              CategoryColorDot(colorHex: category.colorHex!),
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
                TextFormField(
                  controller: _modelController,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                ),
                const SizedBox(height: 10),
                _formRow(isMobile, [
                  TextFormField(
                    controller: _costController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Costo'),
                    onChanged: (_) => _recalcPriceFromMargin(),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Costo inválido';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _marginController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Margen %',
                      hintText: 'Ej: 20',
                    ),
                    onChanged: (_) => _recalcPriceFromMargin(),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return null;
                      final parsed = double.tryParse(text);
                      if (parsed == null) return 'Margen inválido';
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Precio'),
                    onChanged: (_) => _recalcMarginFromPrice(),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Precio inválido';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                _PriceTierFields(
                  isMobile: isMobile,
                  controllers: _priceTierControllers,
                ),
                const SizedBox(height: 10),
                // Un servicio no maneja inventario: se ocultan Stock y Stock
                // mínimo para no reintroducir valores (el submit fuerza 0).
                if (_isService)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Servicio: no maneja stock ni stock mínimo.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTokens.textMuted,
                      ),
                    ),
                  )
                else
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
                DropdownButtonFormField<bool>(
                  initialValue: _priceIncludesTax,
                  decoration: const InputDecoration(
                    labelText: 'ITBIS en el precio de venta',
                    helperText:
                        'Aparte: 100 → se cobra 118. Incluido: se cobra 100 '
                        'exacto y la factura desglosa base + ITBIS.',
                    helperMaxLines: 2,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text('ITBIS aparte (se suma encima del precio)'),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text('ITBIS incluido en el precio'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _priceIncludesTax = value ?? false,
                  ),
                ),
                const SizedBox(height: 10),
                _ProductImagePicker(
                  controller: _imageUrlController,
                  uploading: _uploadingImage,
                  onPick: _pickAndUploadImage,
                  onClear: () =>
                      setState(() => _imageUrlController.text = ''),
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
                    // Al marcar servicio se apaga el control de inventario; al
                    // desmarcarlo se restaura, porque un producto físico sí lo
                    // lleva (antes quedaba apagado para siempre).
                    _trackInventory = !value;
                    // Los controladores de stock NO se tocan: el switch solo
                    // oculta los campos. Si se pusieran en '0' al marcar
                    // servicio, apagarlo de nuevo dejaría 0 escrito y el
                    // guardado borraría el stock real del producto. Convertir
                    // a servicio ya se resuelve en `_submit`, que fuerza 0.
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
      // Un servicio nunca guarda stock: los campos están ocultos y se fuerza 0
      // para no reintroducir valores viejos al convertir un producto físico.
      stock: _isService ? 0 : double.parse(_stockController.text),
      minStock: _isService ? 0 : double.parse(_minStockController.text),
      isActive: _isActive,
      brand: _brandController.text,
      model: _modelController.text,
      notes: _notesController.text,
      imageUrl: _imageUrlController.text,
      isService: _isService,
      isTaxExempt: _isTaxExempt,
      priceIncludesTax: _priceIncludesTax,
      trackInventory: _trackInventory,
      imeis: List<String>.from(_imeis),
      imeiOnPurchase: _imeiOnPurchase,
      priceTier1: _parseTier(_priceTierControllers[0].text),
      priceTier2: _parseTier(_priceTierControllers[1].text),
      priceTier3: _parseTier(_priceTierControllers[2].text),
      priceTier4: _parseTier(_priceTierControllers[3].text),
      priceTier5: _parseTier(_priceTierControllers[4].text),
      priceTier6: _parseTier(_priceTierControllers[5].text),
      priceTier7: _parseTier(_priceTierControllers[6].text),
      priceTier8: _parseTier(_priceTierControllers[7].text),
      priceTier9: _parseTier(_priceTierControllers[8].text),
      priceTier10: _parseTier(_priceTierControllers[9].text),
    );

    Navigator.of(context).pop(input);
  }

  double? _parseTier(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage) return;
    final picked = await FileIoHelper.pickImage();
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      final url = await repo.uploadProductImage(
        bytes: picked.bytes,
        extension: picked.extension,
      );
      if (!mounted) return;
      setState(() => _imageUrlController.text = url);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo subir la imagen: $error')),
      );
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }
}

class _ProductImagePicker extends StatelessWidget {
  const _ProductImagePicker({
    required this.controller,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final url = controller.text.trim();
        final hasImage = url.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Imagen del producto',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTokens.muted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTokens.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          cacheWidth: 144,
                          cacheHeight: 144,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: AppTokens.mutedForeground,
                          ),
                        )
                      : const Icon(
                          Icons.image_outlined,
                          color: AppTokens.mutedForeground,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: uploading ? null : onPick,
                        icon: uploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_outlined, size: 18),
                        label: Text(
                          uploading
                              ? 'Subiendo…'
                              : (hasImage
                                  ? 'Cambiar imagen'
                                  : 'Seleccionar imagen'),
                        ),
                      ),
                      if (hasImage)
                        TextButton.icon(
                          onPressed: uploading ? null : onClear,
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Quitar'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Campos de precio por nivel: etiquetas vienen de app_settings.sale_price_types.
// Un slot se oculta si no tiene nombre configurado y el producto tampoco
// tiene valor guardado en ese tier.
// ─────────────────────────────────────────────────────────────────────────

class _PriceTierFields extends ConsumerWidget {
  const _PriceTierFields({
    required this.isMobile,
    required this.controllers,
  });

  final bool isMobile;

  /// Lista de 10 controllers (uno por cada tier 1..10). Se renderiza solo
  /// el subconjunto que tiene nombre configurado en app_settings.sale_price_types.
  final List<TextEditingController> controllers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceTypes =
        ref.watch(appSettingsProvider).valueOrNull?.salePriceTypes ?? const [];

    final maxTiers = controllers.length; // 10
    final rows = <Widget>[];
    for (var i = 0; i < maxTiers; i++) {
      final hasName = i < priceTypes.length &&
          priceTypes[i].toString().trim().isNotEmpty;
      if (!hasName) continue;
      final label = priceTypes[i].toString();
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: controllers[i],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final parsed = double.tryParse(value);
              if (parsed == null || parsed < 0) return 'Precio inválido';
              return null;
            },
          ),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// Small colored circle shown next to category names when a color_hex is set.
class CategoryColorDot extends StatelessWidget {
  const CategoryColorDot({super.key, required this.colorHex});

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
