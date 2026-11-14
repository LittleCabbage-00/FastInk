/// Windows 右键上下文菜单集成。
///
/// 通过修改 Windows 注册表，让用户在文件资源管理器中右键点击文件时
/// 可以选择"用 FastInk 打开"。
///
/// 注册表路径（当前用户，不需要管理员权限）：
///   HKCU\Software\Classes\*\shell\fastink
///   HKCU\Software\Classes\*\shell\fastink\command
///
/// 使用纯 dart:ffi 实现，不依赖 win32 包。
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as pkg_ffi;

// ============================================================
//  Win32 API 函数签名（advapi32.dll / kernel32.dll）
// ============================================================

// 注：ffi 参数名来自 Win32 文档，保持原样方便对照。
// ignore_for_file: non_constant_identifier_names

/// HKEY 类型。
typedef HKEY = ffi.Pointer<ffi.Void>;

/// LONG 类型。
typedef LONG = ffi.Int32;

/// DWORD 类型。
typedef DWORD = ffi.Uint32;

// --- advapi32.dll: 注册表操作 ---

// RegOpenKeyExW
typedef _RegOpenKeyExWNative =
    DWORD Function(
      HKEY hKey,
      ffi.Pointer<pkg_ffi.Utf16> lpSubKey,
      DWORD ulOptions,
      DWORD samDesired,
      ffi.Pointer<HKEY> phkResult,
    );
typedef _RegOpenKeyExW =
    int Function(
      HKEY hKey,
      ffi.Pointer<pkg_ffi.Utf16> lpSubKey,
      int ulOptions,
      int samDesired,
      ffi.Pointer<HKEY> phkResult,
    );

// RegCreateKeyExW
typedef _RegCreateKeyExWNative =
    DWORD Function(
      HKEY hKey,
      ffi.Pointer<pkg_ffi.Utf16> lpSubKey,
      DWORD Reserved,
      ffi.Pointer<pkg_ffi.Utf16> lpClass,
      DWORD dwOptions,
      DWORD samDesired,
      ffi.Pointer<ffi.Void> lpSecurityAttributes,
      ffi.Pointer<HKEY> phkResult,
      ffi.Pointer<DWORD> lpdwDisposition,
    );
typedef _RegCreateKeyExW =
    int Function(
      HKEY hKey,
      ffi.Pointer<pkg_ffi.Utf16> lpSubKey,
      int Reserved,
      ffi.Pointer<pkg_ffi.Utf16> lpClass,
      int dwOptions,
      int samDesired,
      ffi.Pointer<ffi.Void> lpSecurityAttributes,
      ffi.Pointer<HKEY> phkResult,
      ffi.Pointer<DWORD> lpdwDisposition,
    );

// RegSetValueExW
typedef _RegSetValueExWNative =
    DWORD Function(
      HKEY hKey,
      ffi.Pointer<pkg_ffi.Utf16> lpValueName,
      DWORD Reserved,
      DWORD dwType,
      ffi.Pointer<ffi.Uint8> lpData,
      DWORD cbData,
    );
typedef _RegSetValueExW =
    int Function(
      HKEY hKey,
      ffi.Pointer<pkg_ffi.Utf16> lpValueName,
      int Reserved,
      int dwType,
      ffi.Pointer<ffi.Uint8> lpData,
      int cbData,
    );

// RegDeleteTreeW
typedef _RegDeleteTreeWNative =
    LONG Function(HKEY hKey, ffi.Pointer<pkg_ffi.Utf16> lpSubKey);
typedef _RegDeleteTreeW =
    int Function(HKEY hKey, ffi.Pointer<pkg_ffi.Utf16> lpSubKey);

// RegCloseKey
typedef _RegCloseKeyNative = LONG Function(HKEY hKey);
typedef _RegCloseKey = int Function(HKEY hKey);

// --- kernel32.dll: 可执行文件路径 ---

// GetModuleFileNameW
typedef _GetModuleFileNameWNative =
    DWORD Function(
      ffi.Uint32 hModule,
      ffi.Pointer<pkg_ffi.Utf16> lpFilename,
      DWORD nSize,
    );
typedef _GetModuleFileNameW =
    int Function(int hModule, ffi.Pointer<pkg_ffi.Utf16> lpFilename, int nSize);

// ============================================================
//  Win32 API 缓存（延迟加载，只加载一次）
// ============================================================

/// _regOpenKeyExW：注册表键打开函数的 FFI 绑定，返回句柄由对应关闭函数释放。
late final _RegOpenKeyExW _regOpenKeyExW;

/// _regCreateKeyExW：注册表键创建/打开函数的 FFI 绑定，不代表可任意修改系统键。
late final _RegCreateKeyExW _regCreateKeyExW;

/// _regSetValueExW：注册表值写入函数的 FFI 绑定，按类型和字节长度传参。
late final _RegSetValueExW _regSetValueExW;

/// _regDeleteTreeW：删除指定注册表子树的 FFI 绑定，调用方必须限定本应用注册范围。
late final _RegDeleteTreeW _regDeleteTreeW;

/// _regCloseKey：注册表句柄关闭函数，与成功打开或创建的键句柄配对。
late final _RegCloseKey _regCloseKey;

/// _getModuleFileNameW：读取当前模块路径的 UTF-16 Win32 函数绑定，避免把工作目录当程序目录。
late final _GetModuleFileNameW _getModuleFileNameW;

/// _ffiReady：原生注册表 API 是否完成绑定，初始化失败时禁用对应入口。
late final bool _ffiReady;

/// 是否成功加载了 Win32 API。
/// 非 Windows 平台永远返回 false。
bool get ffiReady {
  try {
    return _ffiReady;
  } catch (_) {
    return false;
  }
}

/// 延迟初始化：加载 advapi32.dll 和 kernel32.dll 中的函数。
bool _initFfiOnce() {
  try {
    final ffi.DynamicLibrary advapi32 = ffi.DynamicLibrary.open('advapi32.dll');
    final ffi.DynamicLibrary kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
    _regOpenKeyExW = advapi32
        .lookupFunction<_RegOpenKeyExWNative, _RegOpenKeyExW>('RegOpenKeyExW');
    _regCreateKeyExW = advapi32
        .lookupFunction<_RegCreateKeyExWNative, _RegCreateKeyExW>(
          'RegCreateKeyExW',
        );
    _regSetValueExW = advapi32
        .lookupFunction<_RegSetValueExWNative, _RegSetValueExW>(
          'RegSetValueExW',
        );
    _regDeleteTreeW = advapi32
        .lookupFunction<_RegDeleteTreeWNative, _RegDeleteTreeW>(
          'RegDeleteTreeW',
        );
    _regCloseKey = advapi32.lookupFunction<_RegCloseKeyNative, _RegCloseKey>(
      'RegCloseKey',
    );
    _getModuleFileNameW = kernel32
        .lookupFunction<_GetModuleFileNameWNative, _GetModuleFileNameW>(
          'GetModuleFileNameW',
        );
    return true;
  } catch (_) {
    return false;
  }
}

// ============================================================
//  常量
// ============================================================

/// 注册表根键 HKEY_CURRENT_USER。
final HKEY _hkcu = ffi.Pointer.fromAddress(0x80000001);

/// REG_SZ 值类型。
const int _regSz = 1;

/// KEY_READ 权限。
const int _keyRead = 0x20019;

/// KEY_SET_VALUE | KEY_CREATE_SUB_KEY 权限。
const int _keyWrite = 0x20006;

/// FastInk 右键菜单在注册表中的路径。
const String _shellKeyPath = r'Software\Classes\*\shell\fastink';

/// FastInk 命令子键路径。
const String _commandKeyPath = r'Software\Classes\*\shell\fastink\command';

// ============================================================
//  公开接口
// ============================================================

/// 检查 FastInk 右键菜单是否已注册。
///
/// 非 Windows 平台返回 false。
bool isContextMenuRegistered() {
  if (!ffiReady) return false;
  final ffi.Pointer<HKEY> keyHandle = pkg_ffi.calloc<HKEY>();
  try {
    final int result = _regOpenKeyExW(
      _hkcu,
      _shellKeyPath.toNativeUtf16(),
      0,
      _keyRead,
      keyHandle,
    );
    if (result == 0) {
      _regCloseKey(keyHandle.value);
      return true;
    }
    return false;
  } finally {
    pkg_ffi.calloc.free(keyHandle);
  }
}

/// 将 FastInk 添加到右键上下文菜单。
///
/// [executablePath] 是 FastInk.exe 的完整路径。
/// 注册的命令格式: "exe_path" --open-external "%1"
///
/// 返回 true 表示注册成功。
bool registerContextMenu(String executablePath) {
  if (!ffiReady) return false;
  const String displayName = '用 FastInk 打开（笔记 / Markdown）';
  final String commandValue = '"$executablePath" --open-external "%1"';
  final ffi.Pointer<HKEY> keyHandle = pkg_ffi.calloc<HKEY>();
  final ffi.Pointer<DWORD> disposition = pkg_ffi.calloc<DWORD>();
  final ffi.Pointer<pkg_ffi.Utf16> shellPathPtr = _shellKeyPath.toNativeUtf16();
  final ffi.Pointer<pkg_ffi.Utf16> cmdPathPtr = _commandKeyPath.toNativeUtf16();
  try {
    // 创建或打开 HKCU\Software\Classes\*\shell\fastink
    final int result = _regCreateKeyExW(
      _hkcu,
      shellPathPtr,
      0,
      ffi.nullptr,
      0,
      _keyWrite,
      ffi.nullptr,
      keyHandle,
      disposition,
    );
    if (result != 0) return false;
    // 写入菜单显示名称（默认值）。
    final ffi.Pointer<pkg_ffi.Utf16> namePtr = displayName.toNativeUtf16();
    final ffi.Pointer<ffi.Uint8> nameData = namePtr.cast<ffi.Uint8>();
    _regSetValueExW(
      keyHandle.value,
      ffi.nullptr,
      0,
      _regSz,
      nameData,
      displayName.length * 2 + 2,
    );
    pkg_ffi.calloc.free(namePtr);
    _regCloseKey(keyHandle.value);
    // 创建 command 子键。
    final ffi.Pointer<HKEY> cmdKey = pkg_ffi.calloc<HKEY>();
    final int cmdResult = _regCreateKeyExW(
      _hkcu,
      cmdPathPtr,
      0,
      ffi.nullptr,
      0,
      _keyWrite,
      ffi.nullptr,
      cmdKey,
      disposition,
    );
    if (cmdResult != 0) {
      pkg_ffi.calloc.free(cmdKey);
      return false;
    }
    // 写入命令字符串。
    final ffi.Pointer<pkg_ffi.Utf16> cmdPtr = commandValue.toNativeUtf16();
    final ffi.Pointer<ffi.Uint8> cmdData = cmdPtr.cast<ffi.Uint8>();
    _regSetValueExW(
      cmdKey.value,
      ffi.nullptr,
      0,
      _regSz,
      cmdData,
      commandValue.length * 2 + 2,
    );
    pkg_ffi.calloc.free(cmdPtr);
    _regCloseKey(cmdKey.value);
    pkg_ffi.calloc.free(cmdKey);
    return true;
  } finally {
    pkg_ffi.calloc.free(shellPathPtr);
    pkg_ffi.calloc.free(cmdPathPtr);
    pkg_ffi.calloc.free(keyHandle);
    pkg_ffi.calloc.free(disposition);
  }
}

/// 从右键上下文菜单中移除 FastInk。
///
/// 返回 true 表示移除成功（或本来就不存在）。
bool unregisterContextMenu() {
  if (!ffiReady) return false;
  // RegDeleteTreeW 递归删除 shell\fastink 及其所有子键。
  final ffi.Pointer<pkg_ffi.Utf16> pathPtr = _shellKeyPath.toNativeUtf16();
  try {
    final int result = _regDeleteTreeW(_hkcu, pathPtr);
    // ERROR_FILE_NOT_FOUND (2) = 键本来就不存在，也算成功。
    return result == 0 || result == 2;
  } finally {
    pkg_ffi.calloc.free(pathPtr);
  }
}

/// 获取当前可执行文件的完整路径（Windows）。
///
/// 使用 Win32 GetModuleFileNameW API。
String getExecutablePath() {
  if (!ffiReady) return '';
  // MAX_PATH 常量 32768 足够覆盖长路径。
  // Utf16 不能直接作为 calloc 的类型参数，先分配 Uint16 数组再 cast。
  final ffi.Pointer<ffi.Uint16> rawBuffer = pkg_ffi.calloc<ffi.Uint16>(32768);
  final ffi.Pointer<pkg_ffi.Utf16> buffer = rawBuffer.cast<pkg_ffi.Utf16>();
  try {
    final int length = _getModuleFileNameW(0, buffer, 32768);
    if (length == 0) return '';
    return buffer.toDartString();
  } finally {
    pkg_ffi.calloc.free(rawBuffer);
  }
}

/// 初始化 FFI，返回是否成功。
/// 非 Windows 平台返回 false。
///
/// 在使用其他函数前会自动调用，也可提前调用确认能力。
bool initWindowsRegistryFfi() {
  try {
    _ffiReady = _initFfiOnce();
    return _ffiReady;
  } catch (_) {
    return false;
  }
}
