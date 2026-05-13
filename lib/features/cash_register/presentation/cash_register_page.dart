import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/cash_register_repository.dart';
import 'cash_register_providers.dart';

class CashRegisterPage extends ConsumerStatefulWidget {
  const CashRegisterPage({super.key});

  @override
  ConsumerState<CashRegisterPage> createState() => _CashRegisterPageState();
}

class _CashRegisterPageState extends ConsumerState<CashRegisterPage> {
  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(cashRegisterDataProvider);

    return ModulePage(
      title: 'Caja',
      description: 'Apertura, arqueo, diferencias y cierre diario.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(cashRegisterDataProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: dataAsync.when(
        data: (data) {
          final openSession = data.openSession;
          final metrics = data.openMetrics;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (openSession == null)
                _noSessionCard()
              else
                _openSessionCard(openSession, metrics),
              const SizedBox(height: AppTokens.s24),
              DataTableShell(
                title: 'Sesiones recientes',
                child: data.recentSessions.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppTokens.s20),
                        child: Text(
                          'Aún no hay sesiones registradas.',
                          style: TextStyle(color: AppTokens.mutedForeground),
                        ),
                      )
                    : DataTable(
                        columns: const [
                          DataColumn(label: Text('Apertura')),
                          DataColumn(label: Text('Cierre')),
                          DataColumn(label: Text('Estado')),
                          DataColumn(label: Text('Monto apertura'), numeric: true),
                          DataColumn(label: Text('Esperado'), numeric: true),
                          DataColumn(label: Text('Conteo cierre'), numeric: true),
                          DataColumn(label: Text('Diferencia'), numeric: true),
                          DataColumn(label: Text('Acciones')),
                        ],
                        rows: data.recentSessions
                            .map(
                              (session) => DataRow(
                                cells: [
                                  DataCell(Text(formatDateTime(session.openedAt))),
                                  DataCell(Text(
                                    session.closedAt == null
                                        ? '-'
                                        : formatDateTime(session.closedAt!),
                                  )),
                                  DataCell(StatusBadge(
                                    label: session.isOpen ? 'Abierta' : 'Cerrada',
                                    status: session.isOpen ? 'open' : 'closed',
                                  )),
                                  DataCell(Text(money(session.openingAmount))),
                                  DataCell(Text(money(session.expectedAmount))),
                                  DataCell(Text(
                                    session.closingAmount == null
                                        ? '-'
                                        : money(session.closingAmount!),
                                  )),
                                  DataCell(Text(
                                    session.differenceAmount == null
                                        ? '-'
                                        : money(session.differenceAmount!),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: session.differenceAmount != null &&
                                              session.differenceAmount! < 0
                                          ? AppTokens.destructive
                                          : null,
                                    ),
                                  )),
                                  DataCell(
                                    session.isOpen
                                        ? const SizedBox.shrink()
                                        : RoleGate(
                                            allowed: const {
                                              'admin',
                                              'supervisor'
                                            },
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _onSealZ(session.id),
                                              icon: const Icon(
                                                  Icons.lock_outline,
                                                  size: 14),
                                              label: const Text(
                                                'Sellar Z',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                minimumSize: const Size(0, 28),
                                                padding: const EdgeInsets
                                                    .symmetric(horizontal: 8),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                foregroundColor:
                                                    AppTokens.primary,
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorCard(
          message: 'No se pudo cargar caja: $error',
          onRetry: () => ref.invalidate(cashRegisterDataProvider),
        ),
      ),
    );
  }

  Widget _noSessionCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border),
      ),
      padding: const EdgeInsets.all(AppTokens.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No hay caja abierta',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTokens.foreground,
            ),
          ),
          const SizedBox(height: AppTokens.s8),
          const Text(
            'Abre una caja para empezar a registrar movimientos del turno.',
            style: TextStyle(color: AppTokens.mutedForeground),
          ),
          const SizedBox(height: AppTokens.s16),
          FilledButton.icon(
            onPressed: _onOpenSession,
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: const Text('Abrir caja'),
          ),
        ],
      ),
    );
  }

  Widget _openSessionCard(
    CashSessionEntity openSession,
    CashSessionMetrics? metrics,
  ) {
    final expectedCash = metrics == null
        ? openSession.expectedAmount
        : metrics.expectedCashFromOpening(openSession.openingAmount);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border),
      ),
      padding: const EdgeInsets.all(AppTokens.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Caja abierta',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.foreground,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _onCashMovement(openSession.id, 'deposit'),
                icon: const Icon(Icons.add_circle_outline,
                    size: 18, color: Color(0xFF22C55E)),
                label: const Text('Agregar efectivo'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    _onCashMovement(openSession.id, 'withdrawal'),
                icon: const Icon(Icons.remove_circle_outline,
                    size: 18, color: Color(0xFFEF4444)),
                label: const Text('Sangría'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _onCloseSession,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Cerrar caja'),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          Text(
            'Abierta: ${formatDateTime(openSession.openedAt)}',
            style: const TextStyle(color: AppTokens.mutedForeground),
          ),
          const SizedBox(height: AppTokens.s16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                KPICard(
                  label: 'Apertura',
                  value: money(openSession.openingAmount),
                  icon: Icons.lock_open_outlined,
                ),
                KPICard(
                  label: 'Cobros (todos)',
                  value: money(metrics?.totalPayments ?? 0),
                  icon: Icons.payments_outlined,
                ),
                KPICard(
                  label: 'Gastos (todos)',
                  value: money(metrics?.totalExpenses ?? 0),
                  icon: Icons.money_off_outlined,
                ),
                KPICard(
                  label: 'Ingreso efectivo',
                  value: money(metrics?.cashPayments ?? 0),
                  icon: Icons.arrow_downward_rounded,
                ),
                KPICard(
                  label: 'Egreso efectivo',
                  value: money(metrics?.cashExpenses ?? 0),
                  icon: Icons.arrow_upward_rounded,
                ),
                KPICard(
                  label: 'Esperado en caja',
                  value: money(expectedCash),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ];
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 900 ? 3 : width >= 500 ? 2 : 1;
              final cardWidth = (width - (crossAxisCount - 1) * 12) / crossAxisCount;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _onOpenSession() async {
    final input = await showDialog<OpenCashInput>(
      context: context,
      builder: (_) => const _OpenSessionDialog(),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);

    try {
      await repository.openSession(input);
      if (!mounted) return;

      ref.invalidate(cashRegisterDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja abierta correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir caja: $error')));
    }
  }

  Future<void> _onCloseSession() async {
    final input = await showDialog<CloseCashInput>(
      context: context,
      builder: (_) => const _CloseSessionDialog(),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);

    try {
      await repository.closeSession(input);
      if (!mounted) return;

      ref.invalidate(cashRegisterDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja cerrada correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cerrar caja: $error')));
    }
  }

  /// Sella un cierre Z fiscal (inmutable) para una sesión ya cerrada.
  /// Pide confirmación explícita porque la operación no se puede revertir
  /// (sólo se puede emitir un cierre Z "complementario").
  Future<void> _onSealZ(String cashSessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sellar cierre Z fiscal'),
        content: const Text(
          'El cierre Z queda inmutable una vez sellado. Cualquier corrección '
          'requiere emitir un cierre Z complementario. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Sellar Z'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);
    try {
      final closureId = await repository.sealFiscalZClosure(cashSessionId);
      if (!mounted) return;
      ref.invalidate(cashRegisterDataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.primary,
          content: Text(
            'Cierre Z sellado · ${closureId.substring(0, 8)}…',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // Si ya existe un cierre Z para esta sesión, el RPC lo bloquea.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo sellar el cierre Z: $error')),
      );
    }
  }

  /// Diálogo para agregar (deposit) o retirar (withdrawal) efectivo de la
  /// sesión activa. El trigger SQL ajusta `expected_amount` automáticamente.
  Future<void> _onCashMovement(String sessionId, String movementType) async {
    final input = await showDialog<CashMovementInput>(
      context: context,
      builder: (_) => _CashMovementDialog(movementType: movementType),
    );
    if (input == null || !mounted) return;

    final repository = ref.read(cashRegisterRepositoryProvider);
    try {
      await repository.addMovement(input);
      if (!mounted) return;
      ref.invalidate(cashRegisterDataProvider);
      final label = movementType == 'deposit'
          ? 'Efectivo agregado a la caja'
          : 'Sangría registrada';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: movementType == 'deposit'
              ? const Color(0xFF22C55E)
              : const Color(0xFFEF4444),
          content: Text(
            '$label · ${money(input.amount)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar el movimiento: $error')),
      );
    }
  }
}

class _CashMovementDialog extends StatefulWidget {
  const _CashMovementDialog({required this.movementType});

  final String movementType;

  @override
  State<_CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<_CashMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDeposit = widget.movementType == 'deposit';
    final accent =
        isDeposit ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isDeposit
                ? Icons.add_circle_outline
                : Icons.remove_circle_outline,
            color: accent,
          ),
          const SizedBox(width: 8),
          Text(isDeposit ? 'Agregar efectivo' : 'Sangría / Retiro'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reasonController,
                decoration: InputDecoration(
                  labelText: 'Motivo',
                  hintText: isDeposit
                      ? 'p.ej. Apertura adicional del dueño'
                      : 'p.ej. Depósito al banco',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              CashMovementInput(
                movementType: widget.movementType,
                amount: double.parse(_amountController.text.trim()),
                reason: _reasonController.text.trim(),
                notes: _notesController.text.trim(),
              ),
            );
          },
          icon: Icon(
            isDeposit ? Icons.check : Icons.arrow_outward,
            size: 18,
          ),
          label: Text(isDeposit ? 'Agregar' : 'Retirar'),
        ),
      ],
    );
  }
}

class _OpenSessionDialog extends StatefulWidget {
  const _OpenSessionDialog();

  @override
  State<_OpenSessionDialog> createState() => _OpenSessionDialogState();
}

class _OpenSessionDialogState extends State<_OpenSessionDialog> {
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
      title: const Text('Abrir caja'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _openingController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto de apertura'),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed < 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
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
        FilledButton(onPressed: _submit, child: const Text('Abrir')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      OpenCashInput(
        openingAmount: double.parse(_openingController.text),
        notes: _notesController.text,
      ),
    );
  }
}

class _CloseSessionDialog extends StatefulWidget {
  const _CloseSessionDialog();

  @override
  State<_CloseSessionDialog> createState() => _CloseSessionDialogState();
}

class _CloseSessionDialogState extends State<_CloseSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _closingController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _closingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cerrar caja'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _closingController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Conteo de cierre'),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed < 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
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
        FilledButton(onPressed: _submit, child: const Text('Cerrar')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      CloseCashInput(
        closingAmount: double.parse(_closingController.text),
        notes: _notesController.text,
      ),
    );
  }
}
