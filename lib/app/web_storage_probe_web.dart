import 'dart:js_interop';

@JS('littleRestCheckStorage')
external JSPromise<JSBoolean> _littleRestCheckStorage();

Future<bool> canPersistWebData() async {
  try {
    return (await _littleRestCheckStorage().toDart).toDart;
  } catch (_) {
    return false;
  }
}
