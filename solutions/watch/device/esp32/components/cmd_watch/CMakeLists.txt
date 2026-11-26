# watch 应用组件：watch_* 串口命令（cmd_watch.c）+ 工程目录下 watch/ 中的 watch 源码。
# 摄像头与屏由 watch_board（av_device_esp32s31.c）驱动，本组件只做转接；
# 手机下行的 MJPEG 画面直接交给 watch_board 硬件解码显示。
#
# 摄像头 / 屏默认开启；不接摄像头或屏时可关闭：
#   idf.py -DWATCH_ENABLE_CAMERA=0 -DWATCH_ENABLE_DISPLAY=0 build
get_filename_component(WATCH_DIR "${CMAKE_CURRENT_LIST_DIR}/../../watch" ABSOLUTE)
if(NOT EXISTS "${WATCH_DIR}/config.h")
    message(FATAL_ERROR "找不到 ${WATCH_DIR}/config.h，请按 README 填写账号配置。")
endif()

if(NOT DEFINED WATCH_ENABLE_CAMERA)
    set(WATCH_ENABLE_CAMERA 1)
endif()
if(NOT DEFINED WATCH_ENABLE_DISPLAY)
    set(WATCH_ENABLE_DISPLAY 1)
endif()
set(_WATCH_CAMERA 0)
set(_WATCH_DISPLAY 0)
set(_WATCH_CAMERA_SRCS "")
if("${WATCH_ENABLE_CAMERA}" STREQUAL "1")
    set(_WATCH_CAMERA 1)
    set(_WATCH_CAMERA_SRCS ${WATCH_DIR}/platform/esp32/watch_camera_esp_av.c)
endif()
if("${WATCH_ENABLE_DISPLAY}" STREQUAL "1")
    set(_WATCH_DISPLAY 1)
endif()

idf_component_register(
    SRCS
        cmd_watch.c
        # watch 核心（与平台无关）
        ${WATCH_DIR}/app/watch_config.c
        ${WATCH_DIR}/app/watch_app.c
        ${WATCH_DIR}/auth/watch_usersig.c
        ${WATCH_DIR}/message/watch_message.c
        ${WATCH_DIR}/message/watch_message_im.c
        ${WATCH_DIR}/media/watch_media.c
        ${WATCH_DIR}/signaling/watch_signal_codec.c
        ${WATCH_DIR}/signaling/watch_signaling.c
        ${WATCH_DIR}/platform/common/watch_media_iot.c
        # ESP32 平台适配
        ${WATCH_DIR}/platform/esp32/watch_platform_esp.c
        ${WATCH_DIR}/platform/esp32/watch_media_source_esp.c
        ${WATCH_DIR}/platform/esp32/watch_video_receiver_esp.c
        ${_WATCH_CAMERA_SRCS}
        # IM 消息与呼叫信令的 JSON 编解码
        ${WATCH_DIR}/third_party/cJSON/cJSON.c
    INCLUDE_DIRS
        include
    PRIV_INCLUDE_DIRS
        ${WATCH_DIR}/include
        ${WATCH_DIR}/message
        ${WATCH_DIR}/platform/common
        ${WATCH_DIR}/platform/esp32
        ${WATCH_DIR}/third_party/cJSON
        ${WATCH_DIR}/third_party/cJSON_compat
    PRIV_REQUIRES
        console tc_iot_sdk im watch_board
        freertos esp_timer esp_netif lwip pthread esp_lcd driver log
        espressif__esp_new_jpeg espressif__esp_h264)

# 固定 gnu17：IDF v6 默认 gnu23，IM 头文件 TIMCloudComm.h 的 `typedef unsigned char bool`
# 在 C23 下报错。
target_compile_options(${COMPONENT_LIB} PRIVATE
    -std=gnu17
    -Wno-error
    -Wno-unused-variable
    -Wno-unused-function
    -Wno-format)

# WATCH_ESP_BOARD_AV=1：摄像头 / 屏走 watch_board（av_device）。
target_compile_definitions(${COMPONENT_LIB} PRIVATE
    WATCH_ENABLE_CAMERA=${_WATCH_CAMERA}
    WATCH_ENABLE_DISPLAY=${_WATCH_DISPLAY}
    WATCH_ESP_BOARD_AV=1)
if(_WATCH_CAMERA)
    # 推流宽高，须与 watch_board/CMakeLists.txt 的 AV_ESP_UPLINK_WIDTH/HEIGHT 一致。
    target_compile_definitions(${COMPONENT_LIB} PRIVATE
        WATCH_CAM_FRAME_WIDTH=640
        WATCH_CAM_FRAME_HEIGHT=360)
endif()
