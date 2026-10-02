import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Lector de código de barras a nivel de pantalla para el POS.
///
/// La pistola "teclea" donde esté el foco. Si el cajero había hecho clic fuera
/// del buscador (en el carrito, en una tarjeta, en el fondo), el escaneo se
/// perdía. Con este widget, mientras su pantalla esté a la vista y el foco no
/// esté en una caja de texto, las teclas se juntan aquí:
///
/// * con Enter (o Tab, como cierran algunas pistolas) → [onScan] con el código;
/// * si se escribe a mano y se hace una pausa sin Enter → [onTyped], para que
///   lo escrito pase al buscador. La pistola manda el código y el Enter en
///   unos pocos milisegundos, así que con ella nunca se dispara.
///
/// No toca nada cuando el foco está en una caja de texto (el buscador ya
/// maneja su propio Enter), cuando hay un diálogo o menú abierto encima, o
/// cuando otra página tapa la pantalla de ventas.
class PosScanListener extends StatefulWidget {
  const PosScanListener({
    super.key,
    required this.onScan,
    required this.onTyped,
    required this.child,
  });

  final ValueChanged<String> onScan;
  final ValueChanged<String> onTyped;
  final Widget child;

  /// Pausa que separa a una persona escribiendo de la pistola.
  static const typingPause = Duration(milliseconds: 150);

  @override
  State<PosScanListener> createState() => _PosScanListenerState();
}

class _PosScanListenerState extends State<PosScanListener> {
  final _buffer = StringBuffer();
  Timer? _idle;

  /// La pantalla está a la vista: ninguna página encima (TickerMode se apaga
  /// cuando una página opaca la tapa) y su ruta es la actual.
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idle?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !_canListen()) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      if (_buffer.isEmpty) return false;
      final code = _buffer.toString().trim();
      _buffer.clear();
      _idle?.cancel();
      if (code.isNotEmpty) widget.onScan(code);
      return true;
    }

    final char = event.character;
    if (char == null || char.length != 1) return false;
    final unit = char.codeUnitAt(0);
    if (unit < 0x20 || unit == 0x7f) return false;
    // Un espacio suelto puede ser para activar un botón enfocado.
    if (char == ' ' && _buffer.isEmpty) return false;

    _buffer.write(char);
    _idle?.cancel();
    _idle = Timer(PosScanListener.typingPause, () {
      final typed = _buffer.toString().trim();
      _buffer.clear();
      if (typed.isNotEmpty && mounted) widget.onTyped(typed);
    });
    return true;
  }

  /// Las teclas sueltas le tocan al lector si la pantalla está a la vista, el
  /// foco no está en una caja de texto y está dentro de esta pantalla o en un
  /// ancestro suyo (la página, el shell). Si está en otro lado es un diálogo,
  /// un menú o el cuadro de cobro, y ahí las teclas no son para el carrito.
  bool _canListen() {
    if (!mounted || !_visible) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return true;
    if (focusContext.findAncestorStateOfType<EditableTextState>() != null) {
      return false;
    }
    final self = context as Element;
    if (identical(focusContext, self)) return true;
    var related = false;
    focusContext.visitAncestorElements((e) {
      related = identical(e, self);
      return !related;
    });
    if (related) return true;
    self.visitAncestorElements((e) {
      related = identical(e, focusContext);
      return !related;
    });
    return related;
  }

  @override
  Widget build(BuildContext context) {
    _visible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    return widget.child;
  }
}
