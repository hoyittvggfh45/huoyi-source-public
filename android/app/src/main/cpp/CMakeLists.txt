cmake_minimum_required(VERSION 3.18)
project(huoyi_quickjs)
add_library(huoyi_quickjs SHARED
    quickjs/quickjs.c
    quickjs/libregexp.c
    quickjs/libunicode.c
    quickjs/cutils.c
    quickjs/libbf.c
    quickjs/huoyi_quickjs.c
    quickjs/quickjs_jni.c)
target_compile_definitions(huoyi_quickjs PRIVATE CONFIG_VERSION="2024-01-13" CONFIG_BIGNUM)
target_include_directories(huoyi_quickjs PRIVATE quickjs)
find_library(log-lib log)
target_link_libraries(huoyi_quickjs ${log-lib} m)
