import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _OpenExNative = Uint64 Function(
  Pointer<Utf8>,
  Int32,
  Pointer<Pointer<Utf8>>,
);
typedef _OpenExDart = int Function(
  Pointer<Utf8>,
  int,
  Pointer<Pointer<Utf8>>,
);
typedef _CloseNative = Void Function(Uint64);
typedef _CloseDart = void Function(int);
typedef _InvokeNative = Pointer<Utf8> Function(
  Uint64,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);
typedef _InvokeDart = Pointer<Utf8> Function(
  int,
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);
typedef _VersionNative = Pointer<Utf8> Function();

class MeowoException implements Exception {
  MeowoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MeowoCore {
  MeowoCore._(this._library, this._handle);

  final DynamicLibrary _library;
  final int _handle;

  late final _CloseDart _close = _library
      .lookupFunction<_CloseNative, _CloseDart>('meowo_workspace_close');
  late final _InvokeDart _invoke = _library
      .lookupFunction<_InvokeNative, _InvokeDart>('meowo_invoke');
  late final _FreeDart _free = _library.lookupFunction<_FreeNative, _FreeDart>(
    'meowo_free',
  );

  static String? _cachedPath;

  static String libraryVersion() {
    final library = DynamicLibrary.open(_resolveLibrary());
    final version = library
        .lookupFunction<_VersionNative, Pointer<Utf8> Function()>(
          'meowo_core_version',
        );
    return version().toDartString();
  }

  static Future<MeowoCore> open(
    String root, {
    bool acquireLock = true,
  }) async {
    final library = DynamicLibrary.open(_resolveLibrary());
    final open = library.lookupFunction<_OpenExNative, _OpenExDart>(
      'meowo_workspace_open_ex',
    );
    final error = calloc<Pointer<Utf8>>();
    try {
      final path = root.toNativeUtf8();
      try {
        final handle = open(path, acquireLock ? 1 : 0, error);
        if (handle == 0) {
          throw MeowoException(_readError(error) ?? '无法打开资料库');
        }
        final core = MeowoCore._(library, handle);
        final info = core.call('workspace_info');
        if (info['version'] == null) {
          core.close();
          throw MeowoException('核心版本信息缺失');
        }
        return core;
      } finally {
        malloc.free(path);
      }
    } finally {
      calloc.free(error);
    }
  }

  Map<String, dynamic> call(String op, [Map<String, dynamic>? args]) {
    final request = <String, dynamic>{'op': op, ...?args};
    final payload = jsonEncode(request).toNativeUtf8();
    final error = calloc<Pointer<Utf8>>();
    try {
      final result = _invoke(_handle, payload, error);
      if (result == nullptr) {
        throw MeowoException(_readError(error) ?? '核心调用失败: $op');
      }
      try {
        final decoded = jsonDecode(result.toDartString());
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.cast<String, dynamic>();
        }
        throw MeowoException('核心返回了非对象 JSON: $op');
      } finally {
        _free(result);
      }
    } finally {
      malloc.free(payload);
      calloc.free(error);
    }
  }

  void close() {
    _close(_handle);
  }

  static String? _readError(Pointer<Pointer<Utf8>> pointer) {
    final value = pointer.value;
    if (value == nullptr) return null;
    try {
      return value.toDartString();
    } finally {
      final library = DynamicLibrary.open(_resolveLibrary());
      final free = library.lookupFunction<_FreeNative, _FreeDart>('meowo_free');
      free(value);
    }
  }

  static String _resolveLibrary() {
    if (_cachedPath != null) return _cachedPath!;
    if (Platform.isAndroid) {
      return _cachedPath = 'libmeowo_core.so';
    }
    final env = Platform.environment['MEOWO_CORE_LIB'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return _cachedPath = env;
    }
    final name = Platform.isWindows ? 'meowo_core.dll' : 'libmeowo_core.so';
    final candidates = <String>[];
    final executable = File(Platform.resolvedExecutable);
    candidates.add(
      '${executable.parent.path}${Platform.pathSeparator}lib${Platform.pathSeparator}$name',
    );
    candidates.add('${executable.parent.path}${Platform.pathSeparator}$name');
    var dir = Directory.current.absolute;
    for (var i = 0; i < 6; i++) {
      candidates.add('${dir.path}/packages/meowo_core/native/build/$name');
      candidates.add('${dir.path}/build/$name');
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return _cachedPath = candidate;
      }
    }
    throw MeowoException(
      '找不到 Meowo 核心库 $name。请先构建 packages/meowo_core/native，'
      '或设置 MEOWO_CORE_LIB。已尝试:\n${candidates.join('\n')}',
    );
  }
}
