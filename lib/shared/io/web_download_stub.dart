// Stub para plataformas NO-web. Nunca se invoca en runtime nativo porque
// `FileIoHelper.saveBytes` chequea `kIsWeb` antes de llamarlo, pero existe
// para que el conditional import compile en mobile/desktop.

import 'dart:typed_data';

bool downloadBytesInBrowser({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  throw UnsupportedError(
    'downloadBytesInBrowser solo se invoca en Flutter Web.',
  );
}
