import 'package:flutter_opencc_ffi/flutter_opencc_ffi.dart';

Converter? _converter;
bool _failed = false;

String toSimplifiedImpl(String text) {
  if (text.isEmpty) return text;
  final c = _converter ??= _create();
  if (_failed || c == null) return text;
  try {
    return c.convert(text);
  } catch (_) {
    _failed = true;
    return text;
  }
}

Converter? _create() {
  try {
    return createConverter('t2s.json');
  } catch (_) {
    _failed = true;
    return null;
  }
}
