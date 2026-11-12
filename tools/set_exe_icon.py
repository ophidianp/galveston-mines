#!/usr/bin/env python3
"""
Replaces the icon embedded in a Windows .exe with an .ico file (Windows only,
no extra packages needed - it uses the Win32 resource-update API).

    python tools/set_exe_icon.py build/GalvestonMines.exe assets/art/icon.ico
"""
import ctypes
import struct
import sys
from ctypes import wintypes

RT_ICON = 3
RT_GROUP_ICON = 14
LOAD_LIBRARY_AS_DATAFILE = 0x2

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
k32.LoadLibraryExW.restype = wintypes.HMODULE
k32.FreeLibrary.argtypes = [wintypes.HMODULE]
k32.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
k32.BeginUpdateResourceW.restype = wintypes.HANDLE
k32.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p, wintypes.DWORD]
k32.UpdateResourceW.restype = wintypes.BOOL
k32.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
k32.EndUpdateResourceW.restype = wintypes.BOOL

ENUM_NAME = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
ENUM_LANG = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p)
k32.EnumResourceNamesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ENUM_NAME, ctypes.c_void_p]
k32.EnumResourceLanguagesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ENUM_LANG, ctypes.c_void_p]


def res_id(name):
    """int -> MAKEINTRESOURCE pointer, str -> wide string buffer."""
    if isinstance(name, int):
        return ctypes.c_void_p(name), None
    buf = ctypes.create_unicode_buffer(name)
    return ctypes.cast(buf, ctypes.c_void_p), buf


def existing_groups(exe):
    """[(name, language)] of the RT_GROUP_ICON resources in the exe."""
    h = k32.LoadLibraryExW(exe, None, LOAD_LIBRARY_AS_DATAFILE)
    if not h:
        raise OSError(ctypes.get_last_error(), "LoadLibraryEx failed")
    names = []

    def on_name(_h, _t, name, _p):
        names.append(name if name < 0x10000 else ctypes.wstring_at(name))
        return True

    cb_name = ENUM_NAME(on_name)
    k32.EnumResourceNamesW(h, ctypes.c_void_p(RT_GROUP_ICON), cb_name, None)
    result = []
    for n in names:
        langs = []

        def on_lang(_h, _t, _n, lang, _p):
            langs.append(lang)
            return True

        cb_lang = ENUM_LANG(on_lang)
        ptr, keep = res_id(n)
        k32.EnumResourceLanguagesW(h, ctypes.c_void_p(RT_GROUP_ICON), ptr, cb_lang, None)
        result += [(n, lg) for lg in langs]
    k32.FreeLibrary(h)
    return result


def main(exe, ico_path):
    ico = open(ico_path, "rb").read()
    _, _, count = struct.unpack_from("<HHH", ico, 0)
    images = []
    for i in range(count):
        w, h, colors, res, planes, bpp, size, offset = struct.unpack_from("<BBBBHHII", ico, 6 + i * 16)
        images.append(((w, h, colors, res, planes, bpp, size), ico[offset:offset + size]))

    groups = existing_groups(exe)
    if not groups:
        groups = [(1, 1033)]
    first_name, lang = groups[0]

    hu = k32.BeginUpdateResourceW(exe, False)
    if not hu:
        raise OSError(ctypes.get_last_error(), "BeginUpdateResource failed")
    keep = []
    # Remove the old icon groups so Explorer can only pick ours.
    for name, lg in groups:
        ptr, buf = res_id(name)
        keep.append(buf)
        k32.UpdateResourceW(hu, ctypes.c_void_p(RT_GROUP_ICON), ptr, lg, None, 0)
    # Add each image as an RT_ICON, then a group directory pointing at them.
    base_id = 900
    group = struct.pack("<HHH", 0, 1, len(images))
    for i, (hdr, data) in enumerate(images):
        w, h, colors, res, planes, bpp, size = hdr
        buf = ctypes.create_string_buffer(data, len(data))
        keep.append(buf)
        if not k32.UpdateResourceW(hu, ctypes.c_void_p(RT_ICON), ctypes.c_void_p(base_id + i), lang, buf, len(data)):
            raise OSError(ctypes.get_last_error(), "UpdateResource (icon) failed")
        group += struct.pack("<BBBBHHIH", w, h, colors, res, planes, bpp, size, base_id + i)
    gbuf = ctypes.create_string_buffer(group, len(group))
    ptr, nbuf = res_id(first_name)
    keep += [gbuf, nbuf]
    if not k32.UpdateResourceW(hu, ctypes.c_void_p(RT_GROUP_ICON), ptr, lang, gbuf, len(group)):
        raise OSError(ctypes.get_last_error(), "UpdateResource (group) failed")
    if not k32.EndUpdateResourceW(hu, False):
        raise OSError(ctypes.get_last_error(), "EndUpdateResource failed")
    print(f"icon set on {exe} ({len(images)} sizes, replaced {len(groups)} group(s), name={first_name!r})")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
