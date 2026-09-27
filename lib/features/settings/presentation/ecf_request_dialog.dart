import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../inventory/data/file_io_helper.dart';
import '../data/ecf_request_repository.dart';
import 'settings_providers.dart';

/// Formulario con el que el dueño solicita la facturación electrónica.
///
/// Portado de mangospos (`ecf_request_dialog.dart`). Pide exactamente lo que
/// el proveedor necesita para dar de alta la empresa ante la DGII: los datos
/// del contribuyente tal como están en el RNC, con quién coordinar, y el
/// certificado de firma digital con su contraseña.
///
/// El certificado no se guarda: viaja al proveedor en la misma petición y se
/// descarta. Eso se le dice al usuario en la pantalla, no solo en el código.
class EcfRequestDialog extends ConsumerStatefulWidget {
  const EcfRequestDialog({super.key, required this.status});

  final EcfRequestStatus status;

  static Future<bool?> show(BuildContext context, EcfRequestStatus status) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EcfRequestDialog(status: status),
    );
  }

  @override
  ConsumerState<EcfRequestDialog> createState() => _EcfRequestDialogState();
}

class _EcfRequestDialogState extends ConsumerState<EcfRequestDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _rnc;
  late final TextEditingController _legalName;
  late final TextEditingController _tradeName;
  late final TextEditingController _address;
  late final TextEditingController _province;
  late final TextEditingController _municipality;
  late final TextEditingController _email;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  final _certPassword = TextEditingController();

  bool _alreadyAuthorized = false;
  bool _acceptTerms = false;
  bool _sending = false;
  bool _showPassword = false;

  ({Uint8List bytes, String name})? _certificate;

  @override
  void initState() {
    super.initState();
    final d = widget.status.data;
    _rnc = TextEditingController(text: d.rnc ?? '');
    _legalName = TextEditingController(text: d.legalName ?? '');
    _tradeName = TextEditingController(text: d.tradeName ?? '');
    _address = TextEditingController(text: d.fiscalAddress ?? '');
    _province = TextEditingController(text: d.province ?? '');
    _municipality = TextEditingController(text: d.municipality ?? '');
    _email = TextEditingController(text: d.email ?? '');
    _contactName = TextEditingController(text: widget.status.contactName ?? '');
    _contactPhone = TextEditingController(
      text: widget.status.contactPhone ?? '',
    );
    _alreadyAuthorized = widget.status.alreadyAuthorized ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _rnc,
      _legalName,
      _tradeName,
      _address,
      _province,
      _municipality,
      _email,
      _contactName,
      _contactPhone,
      _certPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Solicitar facturación electrónica'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Estos datos tienen que estar tal como los tiene la DGII en '
                  'tu RNC. Si algo no coincide, el proveedor rechaza el alta.',
                  style: TextStyle(color: AppTokens.mutedForeground),
                ),
                const SizedBox(height: AppTokens.s16),

                _section('Datos del contribuyente'),
                _field(
                  controller: _rnc,
                  label: 'RNC o cédula',
                  hint: '131974602',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.isEmpty) return 'Falta el RNC.';
                    if (digits.length != 9 && digits.length != 11) {
                      return 'El RNC lleva 9 dígitos y la cédula 11.';
                    }
                    return null;
                  },
                ),
                _field(
                  controller: _legalName,
                  label: 'Razón social',
                  hint: 'Como aparece en el RNC',
                  validator: _required('Falta la razón social.'),
                ),
                _field(
                  controller: _tradeName,
                  label: 'Nombre comercial',
                  hint: 'El nombre con el que te conocen',
                  validator: _required('Falta el nombre comercial.'),
                ),
                _field(
                  controller: _address,
                  label: 'Domicilio fiscal',
                  hint: 'El registrado en la DGII',
                  maxLength: 100,
                  validator: _required('Falta el domicilio fiscal.'),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        controller: _province,
                        label: 'Provincia',
                        hint: 'Santo Domingo',
                        validator: _required('Falta la provincia.'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.s12),
                    Expanded(
                      child: _field(
                        controller: _municipality,
                        label: 'Municipio',
                        hint: 'Santo Domingo Norte',
                        validator: _required('Falta el municipio.'),
                      ),
                    ),
                  ],
                ),
                _field(
                  controller: _email,
                  label: 'Correo para los comprobantes',
                  hint: 'facturacion@empresa.com',
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 80,
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'Falta el correo.';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
                      return 'Ese correo no parece válido.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppTokens.s8),
                _section('Con quién coordinamos'),
                _field(
                  controller: _contactName,
                  label: 'Nombre de contacto',
                  hint: 'Quien atiende el proceso ante la DGII',
                  maxLength: 80,
                  validator: _required('Falta el nombre de contacto.'),
                ),
                _field(
                  controller: _contactPhone,
                  label: 'Teléfono de contacto',
                  hint: '809-555-1234',
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.isEmpty) return 'Falta el teléfono.';
                    if (digits.length < 10) {
                      return 'El teléfono lleva 10 dígitos.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppTokens.s8),
                _section('Certificado de firma digital'),
                const Text(
                  'Es el archivo .p12 que te entregó la entidad certificadora '
                  '(Avansi, Camarasoft…). Se envía al proveedor para firmar '
                  'tus comprobantes y no se guarda en el sistema.',
                  style: TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppTokens.s8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _sending ? null : _pickCertificate,
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: Text(
                        _certificate == null
                            ? 'Elegir certificado'
                            : 'Cambiar archivo',
                      ),
                    ),
                    const SizedBox(width: AppTokens.s12),
                    Expanded(
                      child: Text(
                        _certificate?.name ?? 'Ningún archivo elegido',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _certificate == null
                              ? AppTokens.mutedForeground
                              : AppTokens.foreground,
                          fontWeight: _certificate == null
                              ? FontWeight.normal
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s12),
                TextFormField(
                  controller: _certPassword,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña del certificado',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Falta la contraseña.' : null,
                ),

                const SizedBox(height: AppTokens.s16),
                CheckboxListTile(
                  value: _alreadyAuthorized,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => _alreadyAuthorized = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Ya soy emisor electrónico autorizado por la DGII',
                  ),
                  subtitle: const Text(
                    'Si no lo eres, te acompañamos en el trámite.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                CheckboxListTile(
                  value: _acceptTerms,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => _acceptTerms = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Autorizo a registrar mi certificado con el proveedor de '
                    'facturación electrónica',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _submit,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined, size: 18),
          label: Text(_sending ? 'Enviando...' : 'Enviar solicitud'),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.s8),
    child: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppTokens.foreground,
      ),
    ),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
        ),
        validator: validator,
      ),
    );
  }

  String? Function(String?) _required(String message) =>
      (v) => (v ?? '').trim().isEmpty ? message : null;

  Future<void> _pickCertificate() async {
    final picked = await FileIoHelper.pickCertificateFile();
    if (picked == null || !mounted) return;
    // Un .p12 de firma no pasa de 100 KB; el servidor lo rechaza igual, pero
    // avisar acá evita subir un PDF y esperar el viaje de ida y vuelta.
    if (picked.bytes.length > 100 * 1024) {
      AppSnackBar.error(
        context,
        'Ese archivo pesa ${(picked.bytes.length / 1024).round()} KB. Un '
        'certificado .p12 no pasa de 100 KB: revisa que sea el archivo '
        'correcto.',
      );
      return;
    }
    setState(() => _certificate = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_certificate == null) {
      AppSnackBar.error(context, 'Falta elegir el certificado .p12.');
      return;
    }
    if (!_acceptTerms) {
      AppSnackBar.error(
        context,
        'Falta autorizar el registro de tu certificado con el proveedor.',
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await ref
          .read(ecfRequestRepositoryProvider)
          .submit(
            EcfRequestSubmission(
              data: EcfRequestData(
                rnc: _rnc.text.trim(),
                legalName: _legalName.text.trim(),
                tradeName: _tradeName.text.trim(),
                fiscalAddress: _address.text.trim(),
                province: _province.text.trim(),
                municipality: _municipality.text.trim(),
                email: _email.text.trim(),
              ),
              contactName: _contactName.text.trim(),
              contactPhone: _contactPhone.text.trim(),
              alreadyAuthorized: _alreadyAuthorized,
              certificateFilename: _certificate!.name,
              certificateBytes: _certificate!.bytes,
              certificatePassword: _certPassword.text,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppSnackBar.success(
        context,
        result.message ??
            (result.companyRegistered
                ? 'Solicitud enviada. Tu empresa quedó registrada con el proveedor.'
                : 'Solicitud enviada. Te vamos a contactar.'),
      );
    } on EcfRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'No se pudo enviar', e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
