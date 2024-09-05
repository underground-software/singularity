import ctypes
import sys

_libmemcached = ctypes.CDLL('libmemcached.so')


class _impl:

    EXPIRATION_TIME = 2

    MEMCACHED_NOTFOUND = 16
    MEMCACHED_SUCCESS = 0
    server_config = b'--SOCKET="/run/orbit/memcached.sock" --BINARY-PROTOCOL'

    open = _libmemcached.memcached
    set = _libmemcached.memcached_set
    exist = _libmemcached.memcached_exist


_impl.open.restype = ctypes.c_void_p
_impl.open.argtypes = (ctypes.c_char_p, ctypes.c_size_t)

_impl.set.restype = ctypes.c_int
_impl.set.argtypes = (ctypes.c_void_p,
                      ctypes.c_char_p,
                      ctypes.c_size_t,
                      ctypes.c_char_p,
                      ctypes.c_size_t,
                      ctypes.c_time_t,
                      ctypes.c_uint32)

_impl.exist.restype = ctypes.c_int
_impl.exist.argtypes = (ctypes.c_void_p,
                        ctypes.c_char_p,
                        ctypes.c_size_t)

_connection = _impl.open(_impl.server_config, len(_impl.server_config))


def add_entry(key):
    ret = _impl.set(_connection, key, len(key), None, 0,
                    _impl.EXPIRATION_TIME, 0)

    if ret != _impl.MEMCACHED_SUCCESS:
        print(f'Failed to set cache {ret}', file=sys.stderr)

    return ret == _impl.MEMCACHED_SUCCESS


def entry_exists(key):
    ret = _impl.exist(_connection, key, len(key))

    if ret not in (_impl.MEMCACHED_SUCCESS, _impl.MEMCACHED_NOTFOUND):
        print(f'Failed to retrieve cache item {ret}', file=sys.stderr)

    return ret == _impl.MEMCACHED_SUCCESS
