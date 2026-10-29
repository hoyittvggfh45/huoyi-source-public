import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class _JsValue extends Struct {
  @Uint64()
  external int u;

  @Int64()
  external int tag;
}

typedef _NewRuntimeNative = Pointer<Void> Function();
typedef _NewContextNative = Pointer<Void> Function(Pointer<Void>);
typedef _EvalNative = _JsValue Function(
  Pointer<Void>,
  Pointer<Int8>,
  IntPtr,
  Pointer<Int8>,
  Int32,
);
typedef _ToCStringNative = Pointer<Int8> Function(
  Pointer<Void>,
  Pointer<IntPtr>,
  _JsValue,
  Int32,
);
typedef _GetExceptionNative = _JsValue Function(Pointer<Void>);
typedef _FreeValueRawNative = Void Function(Pointer<Void>, _JsValue);
typedef _FreeCStringNative = Void Function(Pointer<Void>, Pointer<Int8>);
typedef _FreeContextNative = Void Function(Pointer<Void>);
typedef _FreeRuntimeNative = Void Function(Pointer<Void>);
typedef _GetRuntimeNative = Pointer<Void> Function(Pointer<Void>);
typedef _ExecutePendingJobNative =
    Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);

class QuickJsEngine {
  QuickJsEngine._(
    this._runtime,
    this._context,
    this._eval,
    this._toCString,
    this._getException,
    this._freeValueRaw,
    this._freeCString,
    this._freeContext,
    this._freeRuntime,
    this._getRuntime,
    this._executePendingJob,
  );

  factory QuickJsEngine.open(String libPath) {
    final DynamicLibrary lib = DynamicLibrary.open(libPath);
    final Pointer<Void> Function() newRuntime =
        lib.lookupFunction<_NewRuntimeNative, Pointer<Void> Function()>(
          'JS_NewRuntime',
        );
    final Pointer<Void> Function(Pointer<Void>) newContext =
        lib.lookupFunction<_NewContextNative, Pointer<Void> Function(Pointer<Void>)>(
          'JS_NewContext',
        );
    final void Function(Pointer<Void>) freeContext =
        lib.lookupFunction<_FreeContextNative, void Function(Pointer<Void>)>(
          'JS_FreeContext',
        );
    final void Function(Pointer<Void>) freeRuntime =
        lib.lookupFunction<_FreeRuntimeNative, void Function(Pointer<Void>)>(
          'JS_FreeRuntime',
        );
    final Pointer<Void> Function(Pointer<Void>) getRuntime =
        lib.lookupFunction<_GetRuntimeNative, Pointer<Void> Function(Pointer<Void>)>(
          'JS_GetRuntime',
        );
    final int Function(Pointer<Void>, Pointer<Pointer<Void>>)
    executePendingJob =
        lib.lookupFunction<
          _ExecutePendingJobNative,
          int Function(Pointer<Void>, Pointer<Pointer<Void>>)
        >('JS_ExecutePendingJob');
    final Pointer<Void> runtime = newRuntime();
    if (runtime == nullptr) {
      throw Exception('QuickJS: JS_NewRuntime returned null');
    }
    final Pointer<Void> context = newContext(runtime);
    if (context == nullptr) {
      freeRuntime(runtime);
      throw Exception('QuickJS: JS_NewContext returned null');
    }
    return QuickJsEngine._(
      runtime,
      context,
      lib.lookupFunction<_EvalNative, _JsValue Function(Pointer<Void>, Pointer<Int8>, int, Pointer<Int8>, int)>(
        'JS_Eval',
      ),
      lib.lookupFunction<_ToCStringNative, Pointer<Int8> Function(Pointer<Void>, Pointer<IntPtr>, _JsValue, int)>(
        'JS_ToCStringLen2',
      ),
      lib.lookupFunction<_GetExceptionNative, _JsValue Function(Pointer<Void>)>(
        'JS_GetException',
      ),
      lib.lookupFunction<_FreeValueRawNative, void Function(Pointer<Void>, _JsValue)>(
        '__JS_FreeValue',
      ),
      lib.lookupFunction<_FreeCStringNative, void Function(Pointer<Void>, Pointer<Int8>)>(
        'JS_FreeCString',
      ),
      freeContext,
      freeRuntime,
      getRuntime,
      executePendingJob,
    );
  }

  final Pointer<Void> _runtime;
  final Pointer<Void> _context;
  final _JsValue Function(Pointer<Void>, Pointer<Int8>, int, Pointer<Int8>, int) _eval;
  final Pointer<Int8> Function(Pointer<Void>, Pointer<IntPtr>, _JsValue, int) _toCString;
  final _JsValue Function(Pointer<Void>) _getException;
  final void Function(Pointer<Void>, _JsValue) _freeValueRaw;
  final void Function(Pointer<Void>, Pointer<Int8>) _freeCString;
  final void Function(Pointer<Void>) _freeContext;
  final void Function(Pointer<Void>) _freeRuntime;
  final Pointer<Void> Function(Pointer<Void>) _getRuntime;
  final int Function(Pointer<Void>, Pointer<Pointer<Void>>)
  _executePendingJob;
  bool _disposed = false;

  String eval(String code) {
    if (_disposed) {
      throw StateError('QuickJS engine is disposed');
    }
    final List<int> inputBytes = utf8.encode(code);
    final Pointer<Uint8> input = calloc<Uint8>(inputBytes.length + 1);
    final Pointer<Uint8> filename = calloc<Uint8>(7);
    try {
      input.asTypedList(inputBytes.length).setAll(0, inputBytes);
      input[inputBytes.length] = 0;
      const List<int> nameBytes = <int>[60, 101, 118, 97, 108, 62];
      filename.asTypedList(nameBytes.length).setAll(0, nameBytes);
      filename[nameBytes.length] = 0;
      final _JsValue value = _eval(
        _context,
        input.cast<Int8>(),
        inputBytes.length,
        filename.cast<Int8>(),
        0,
      );
      if (value.tag == 6) {
        final _JsValue exception = _getException(_context);
        final String message = _valueToString(exception);
        _freeValue(exception);
        throw Exception(message);
      }
      final String result = _valueToString(value);
      _freeValue(value);
      return result;
    } finally {
      calloc.free(input);
      calloc.free(filename);
    }
  }

  String _valueToString(_JsValue value) {    final Pointer<Int8> text = _toCString(
      _context,
      Pointer<IntPtr>.fromAddress(0),
      value,
      0,
    );
    if (text == nullptr) {
      throw Exception('QuickJS: failed to convert value to string');
    }
    try {
      return text.cast<Utf8>().toDartString();
    } finally {
      _freeCString(_context, text);
    }
  }

  void _freeValue(_JsValue value) {
    if (value.tag >= -11 && value.tag < 0) {
      final Pointer<Int32> header = Pointer<Int32>.fromAddress(value.u);
      final int refCount = header.value - 1;
      header.value = refCount;
      if (refCount <= 0) {
        _freeValueRaw(_context, value);
      }
    }
  }

  int executePendingJob() {
    if (_disposed) {
      throw StateError('QuickJS engine is disposed');
    }
    final Pointer<Pointer<Void>> pctx = calloc<Pointer<Void>>();
    try {
      pctx.value = _context;
      final int result = _executePendingJob(_getRuntime(_context), pctx);
      if (result < 0) {
        final _JsValue exception = _getException(_context);
        final String message = _valueToString(exception);
        _freeValue(exception);
        throw Exception(message);
      }
      return result;
    } finally {
      calloc.free(pctx);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _freeContext(_context);
    _freeRuntime(_runtime);
  }
}
