import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Concepto, Proyecto y Localización de la factura A4 clásica. Lo usan el POS
/// (plegado, para no ocupar el carrito) y Editar venta.
class SaleInvoiceDetailsFields extends StatelessWidget {
  const SaleInvoiceDetailsFields({
    super.key,
    required this.project,
    required this.location,
    required this.concept,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController project;
  final TextEditingController location;
  final TextEditingController concept;
  final VoidCallback? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    InputDecoration decoration(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: concept,
          enabled: enabled,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => onChanged?.call(),
          decoration: decoration(
            'Concepto',
            'Ej. Control de calidad del hormigón',
          ),
        ),
        const SizedBox(height: AppTokens.s8),
        TextField(
          controller: project,
          enabled: enabled,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => onChanged?.call(),
          decoration: decoration('Proyecto', 'Nombre de la obra o proyecto'),
        ),
        const SizedBox(height: AppTokens.s8),
        TextField(
          controller: location,
          enabled: enabled,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => onChanged?.call(),
          decoration: decoration('Localización', 'Sector, ciudad'),
        ),
      ],
    );
  }
}

/// Versión plegable para el carrito del POS.
class SaleInvoiceDetailsPanel extends StatelessWidget {
  const SaleInvoiceDetailsPanel({
    super.key,
    required this.project,
    required this.location,
    required this.concept,
    this.onChanged,
  });

  final TextEditingController project;
  final TextEditingController location;
  final TextEditingController concept;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final hasData = project.text.trim().isNotEmpty ||
        location.text.trim().isNotEmpty ||
        concept.text.trim().isNotEmpty;
    return ExpansionTile(
      initiallyExpanded: hasData,
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppTokens.s8),
      title: const Text(
        'Datos de la factura',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Concepto, Proyecto y Localización',
        style: TextStyle(fontSize: 11, color: AppTokens.textMuted),
      ),
      children: [
        SaleInvoiceDetailsFields(
          project: project,
          location: location,
          concept: concept,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
