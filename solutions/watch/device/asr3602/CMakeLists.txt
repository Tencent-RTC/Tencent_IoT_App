# ASR3602 watch 模块发布模板。
#
# 该文件使用通用 CMake 语法，客户需要根据自身 ASR SDK 的固件目标和链接规则
# 调整模块注册位置。当前 sdk/lib 中的静态库是 ESP32 占位库，不能用于 ASR3602。

cmake_minimum_required(VERSION 3.13)

add_library(watch STATIC
    app/watch_app.c
    app/watch_config.c
    auth/watch_usersig.c
    media/watch_media.c
    message/watch_message.c
    message/watch_message_im.c
    signaling/watch_signal_codec.c
    signaling/watch_signaling.c
    platform/common/watch_media_iot.c
    platform/asr3602/watch_entry_asr3602.c
    platform/asr3602/watch_platform_asr3602.c
    platform/asr3602/watch_media_source_asr3602.c
    platform/asr3602/watch_video_receiver_asr3602.c
    third_party/cJSON/cJSON.c
)

target_include_directories(watch PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}/include
    ${CMAKE_CURRENT_LIST_DIR}/platform/common
    ${CMAKE_CURRENT_LIST_DIR}/platform/asr3602
    ${CMAKE_CURRENT_LIST_DIR}/third_party/cJSON
    ${CMAKE_CURRENT_LIST_DIR}/third_party/cJSON_compat
    ${CMAKE_CURRENT_LIST_DIR}/sdk/include
)

if(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/config.h")
    message(FATAL_ERROR "ASR3602 watch config.h is required")
endif()

if(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/sdk/lib/libtc_iot_sdk.a")
    message(FATAL_ERROR "libtc_iot_sdk.a is required")
endif()

if(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/sdk/lib/libim.a")
    message(FATAL_ERROR "libim.a is required")
endif()

target_link_libraries(watch PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}/sdk/lib/libtc_iot_sdk.a
    ${CMAKE_CURRENT_LIST_DIR}/sdk/lib/libim.a
)
