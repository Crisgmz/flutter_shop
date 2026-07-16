import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../data/settings_repository.dart';
import 'settings_providers.dart';

const _modeLabels = <String, String>{
  'physical': 'Física (NCF serie B)',
  'hybrid': 'Híbrida (e-CF con respaldo físico)',
  'electronic': 'Electrónica (solo e-CF serie E)',
};

const _certificationLabels = <String, String>{
  'pending': 'Pendiente',
  'in_progress': 'En proceso',
  'certified': 'Certificada',
  'rejected': 'Rechazada',
};

/// Tarjeta de configuración de facturación electrónica (e-CF).
///
/// Concepto portado de mangospos: la empresa se registra una vez en el
/// proveedor (Alanube) vía la Edge Function `register-company`; la modalidad
/// controla qué serie de NCF consume `assign_next_ncf` (B física / E
/// electrónica); la emisión ocurre desacoplada de la venta.
class EcfSettingsCard extends ConsumerStatefulWidget {
  const EcfSettingsCard({super.key});

  @override
  ConsumerState<EcfSettingsCard> createState() => _EcfSettingsCardState();
}

class _EcfSettingsCardState extends ConsumerState<EcfSettingsCard> {
  bool _saving = false;
  bool _registering = false;

  @override
  Widget build(BuildContext context) {
    final ecfAsync = ref.watch(companyEcfSettingsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ecfAsync.when(
          data: (settings) => _content(settings),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Text(
            'No se pudo cargar la configuración e-CF: $error',
            style: const TextStyle(color: AppTokens.mutedForeground),
          ),
        ),
      ),
    );
  }

  Widget _content(CompanyEcfSettings? settings) {
    final mode = settings?.mode ?? 'physical';
    final environment = settings?.environment ?? 'sandbox';
    final registered = settings?.isRegistered ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Facturación electrónica (e-CF)',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _statusChip(settings),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Emisión de comprobantes fiscales electrónicos DGII a través de '
          'Alanube. La venta nunca se bloquea por el e-CF: si el proveedor '
          'no responde, el documento queda en cola y se emite en segundo '
          'plano.',
          style: TextStyle(color: AppTokens.mutedForeground),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(
                  labelText: 'Modalidad de facturación',
                  helperText:
                      'Controla qué serie consumen las ventas (B física / E '
                      'electrónica).',
                  helperMaxLines: 2,
                ),
                items: _modeLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null || value == mode) return;
                        _save(mode: value, environment: environment);
                      },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: environment,
                decoration: const InputDecoration(
                  labelText: 'Ambiente',
                  helperText: 'Sandbox para pruebas/certificación DGII.',
                  helperMaxLines: 2,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'sandbox',
                    child: Text('Sandbox (pruebas)'),
                  ),
                  DropdownMenuItem(
                    value: 'production',
                    child: Text('Producción'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null || value == environment) return;
                        _save(mode: mode, environment: value);
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _detail(
              'Registro en Alanube',
              registered
                  ? 'Registrada (${settings!.alanubeCompanyId})'
                  : 'Sin registrar',
            ),
            _detail(
              'Certificación DGII',
              _certificationLabels[settings?.certificationStatus] ??
                  'Pendiente',
            ),
            if (!registered)
              FilledButton.tonalIcon(
                onPressed: _registering ? null : _register,
                icon: _registering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: const Text('Registrar empresa en Alanube'),
              ),
          ],
        ),
        if ((settings?.electronicEnabled ?? false) && !registered) ...[
          const SizedBox(height: 10),
          const Text(
            'La modalidad electrónica está activa pero la empresa no está '
            'registrada en Alanube: los e-CF quedarán en cola sin emitirse '
            'hasta completar el registro.',
            style: TextStyle(color: AppTokens.destructive),
          ),
        ],
      ],
    );
  }

  Widget _statusChip(CompanyEcfSettings? settings) {
    final enabled = settings?.electronicEnabled ?? false;
    return Chip(
      avatar: Icon(
        enabled ? Icons.bolt : Icons.receipt_long_outlined,
        size: 16,
      ),
      label: Text(enabled ? 'e-CF activo' : 'NCF físico'),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _detail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTokens.mutedForeground,
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Future<void> _save({
    required String mode,
    required String environment,
  }) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveCompanyEcfSettings(mode: mode, environment: environment);
      ref.invalidate(companyEcfSettingsProvider);
      if (mounted) {
        AppSnackBar.success(context, 'Configuración e-CF guardada.');
      }
    } catch (error) {
      if (mounted) {
        AppSnackBar.error(context, 'No se pudo guardar', error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _register() async {
    setState(() => _registering = true);
    try {
      await ref.read(settingsRepositoryProvider).registerEcfCompany();
      ref.invalidate(companyEcfSettingsProvider);
      if (mounted) {
        AppSnackBar.success(
          context,
          'Empresa registrada en Alanube. Ya puede emitir e-CF.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppSnackBar.error(context, 'Registro fallido', error);
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }
}
