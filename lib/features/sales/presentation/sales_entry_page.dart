import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../cash_register/data/cash_register_repository.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
import 'sales_page.dart';

/// Punto de entrada del módulo de Ventas.
///
/// Antes: `/ventas` mostraba directo el POS. El cajero usaba cualquier caja
/// implícita (sesión sin nombre).
///
/// Ahora: muestra primero el selector de cajas (como WilmaxPOS). Admin y
/// supervisor ven todas las cajas activas de la sucursal; el cajero solo ve
/// las que le fueron asignadas. Al elegir una caja se abre la sesión (si
/// no había) y se entra al POS sobre esa caja.
class SalesEntryPage extends ConsumerWidget {
  const SalesEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(cashRegisterDataProvider);

    return dataAsync.when(
      data: (data) {
        // Si el usuario ya tiene una sesión abierta, vamos directo al POS.
        // El picker solo aparece cuando hace falta elegir caja para abrir.
        if (data.openSession != null) {
          return const SalesPage();
        }
        return const _SalesCashRegisterPicker();
      },
      loading: () => const _LoadingScaffold(),
      error: (error, _) => _ErrorScaffold(
        message: 'No se pudo cargar el estado de la caja: $error',
        onRetry: () => ref.invalidate(cashRegisterDataProvider),
      ),
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const ModulePage(
      title: 'Ventas',
      child: SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ModulePage(
      title: 'Ventas',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: AppTokens.s12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: AppTokens.s16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesCashRegisterPicker extends ConsumerWidget {
  const _SalesCashRegisterPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleAccessProvider);
    final canSeeAll = role.isAdmin || role.isSupervisor;
    // Admin/supervisor ven el catálogo completo de la sucursal. El cajero
    // solo ve las cajas a las que está explícitamente asignado.
    final cajasAsync = canSeeAll
        ? ref.watch(cashRegistersProvider)
        : ref.watch(myCashRegistersProvider);
    final openSessionsAsync = canSeeAll
        ? ref.watch(allOpenCashSessionsProvider)
        : const AsyncValue<List<CashSessionOverview>>.data([]);

    return ModulePage(
      title: 'Ventas',
      description: canSeeAll
          ? 'Selecciona la caja desde donde vas a vender.'
          : 'Selecciona tu caja para empezar a vender.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(cashRegistersProvider);
            ref.invalidate(myCashRegistersProvider);
            ref.invalidate(allOpenCashSessionsProvider);
            ref.invalidate(cashRegisterDataProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: cajasAsync.when(
        data: (cajas) {
          if (cajas.isEmpty) {
            return _EmptyState(canManage: canSeeAll);
          }
          final openByRegister = <String, CashSessionOverview>{
            for (final s in openSessionsAsync.valueOrNull ?? const [])
              // CashSessionEntity no trae cash_register_id directamente; el
              // overview tampoco. Indexamos por id del cajero como respaldo,
              // pero el resaltado de "ocupada" se calcula abajo cuando llega.
              s.session.id: s,
          };
          return _CashRegisterGrid(
            cajas: cajas,
            openSessions: openByRegister,
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              'No se pudieron cargar las cajas: $error',
              style: const TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          const Icon(Icons.point_of_sale_outlined,
              size: 56, color: Color(0xFF94A3B8)),
          const SizedBox(height: AppTokens.s12),
          Text(
            canManage
                ? 'Todavía no hay cajas configuradas en esta sucursal.'
                : 'No tenés cajas asignadas. Pedile al administrador que te asigne una.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF475569),
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: AppTokens.s16),
            const Text(
              'Configurá las cajas y sus cajeros en /configuración.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _CashRegisterGrid extends ConsumerWidget {
  const _CashRegisterGrid({
    required this.cajas,
    required this.openSessions,
  });

  final List<CashRegisterEntity> cajas;

  /// Mapeo por session.id (solo informativo — no lo usamos para el
  /// resaltado por caja todavía, eso requeriría exponer cash_register_id en
  /// el overview).
  final Map<String, CashSessionOverview> openSessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = ResponsiveLayout.isMobile(context)
            ? 1
            : (width / 280).floor().clamp(1, 4);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: 140,
          ),
          itemCount: cajas.length,
          itemBuilder: (context, i) {
            final caja = cajas[i];
            return _CashRegisterCard(
              caja: caja,
              onTap: () => _onPickCaja(context, ref, caja),
            );
          },
        );
      },
    );
  }

  Future<void> _onPickCaja(
    BuildContext context,
    WidgetRef ref,
    CashRegisterEntity caja,
  ) async {
    final input = await showDialog<OpenCashInput>(
      context: context,
      builder: (_) => _OpenSessionForCajaDialog(caja: caja),
    );
    if (input == null) return;
    if (!context.mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);
    try {
      await repository.openSessionForRegister(input);
      ref.invalidate(cashRegisterDataProvider);
      ref.invalidate(allOpenCashSessionsProvider);
      if (!context.mounted) return;
      AppSnackBar.success(context, 'Caja "${caja.name}" abierta');
    } catch (error) {
      if (!context.mounted) return;
      AppSnackBar.error(context, 'No se pudo abrir la caja', error);
    }
  }
}

class _CashRegisterCard extends StatelessWidget {
  const _CashRegisterCard({required this.caja, required this.onTap});

  final CashRegisterEntity caja;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTokens.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppTokens.s16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(AppTokens.radius),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTokens.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.point_of_sale,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppTokens.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      caja.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.group_outlined,
                            size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          caja.assignedUserIds.isEmpty
                              ? 'Sin cajeros asignados'
                              : '${caja.assignedUserIds.length} cajero(s)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog de apertura para una caja concreta. Reusa el endpoint
/// `open_cash_session_for_register` que valida que el usuario actual esté
/// asignado a la caja (RLS + RPC).
class _OpenSessionForCajaDialog extends StatefulWidget {
  const _OpenSessionForCajaDialog({required this.caja});

  final CashRegisterEntity caja;

  @override
  State<_OpenSessionForCajaDialog> createState() =>
      _OpenSessionForCajaDialogState();
}

class _OpenSessionForCajaDialogState extends State<_OpenSessionForCajaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _openingController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _openingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Abrir ${widget.caja.name}'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _openingController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto de apertura',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed < 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Abrir caja')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      OpenCashInput(
        openingAmount: double.parse(_openingController.text),
        notes: _notesController.text,
        cashRegisterId: widget.caja.id,
      ),
    );
  }
}
