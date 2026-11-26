# ESP32-S31-Korvo-1 板级音视频驱动（av_device_esp32s31.c）：
#   音频：ES8389 麦克风 / 扬声器 + esp-sr 回声消除；
#   摄像头：sc101iot（DVP）采集 1280x720，PPA 缩放到 640x360，硬件 JPEG 编码后推流；
#   屏幕：800x480 RGB 屏（ESP32-S3-LCD-EV-Board-SUB3 子板），硬件 JPEG 解码显示手机画面。
#   HAL_Audio_esp.c：tc_iot_sdk 回调的音频编解码 HAL（AAC / G.722，基于 esp_audio_codec）。
#
# 摄像头 / 屏开关与 cmd_watch 共用：idf.py -DWATCH_ENABLE_CAMERA=0 -DWATCH_ENABLE_DISPLAY=0 build
if(NOT DEFINED WATCH_ENABLE_CAMERA)
    set(WATCH_ENABLE_CAMERA 1)
endif()
if(NOT DEFINED WATCH_ENABLE_DISPLAY)
    set(WATCH_ENABLE_DISPLAY 1)
endif()
set(_AV_CAMERA 0)
set(_AV_LCD 0)
if("${WATCH_ENABLE_CAMERA}" STREQUAL "1")
    set(_AV_CAMERA 1)
endif()
if("${WATCH_ENABLE_DISPLAY}" STREQUAL "1")
    set(_AV_LCD 1)
endif()

idf_component_register(
    SRCS av_device_esp32s31.c
    INCLUDE_DIRS "."
    REQUIRES tc_iot_sdk
    PRIV_REQUIRES
        driver esp_timer esp_driver_gpio esp_driver_i2c esp_driver_i2s
        espressif__esp_audio_codec espressif__esp_codec_dev espressif__esp-sr
        espressif__esp_video espressif__esp_cam_sensor
        esp_driver_cam esp_driver_jpeg esp_driver_ppa esp_lcd)

target_compile_definitions(${COMPONENT_LIB} PRIVATE
    PLATFORM_FREERTOS BUILD_IOT_AV=1 BUILD_IOT_CLOUD_STORAGE=0 BUILD_IOT_AITALK=0 BUILD_OPUS=0
    AV_DEVICE_ENABLE_CAMERA=${_AV_CAMERA}
    AV_DEVICE_ENABLE_LCD=${_AV_LCD})
target_compile_options(${COMPONENT_LIB} PRIVATE
    "SHELL:-include ${CMAKE_CURRENT_LIST_DIR}/platform_compat.h")
if(_AV_CAMERA)
    # 上行：sensor 1280x720 经 PPA 缩到 640x360，最高 15fps，JPEG 质量 50，约 1Mbps。
    # 宽高须与 cmd_watch 的 WATCH_CAM_FRAME_WIDTH/HEIGHT 一致。
    target_compile_definitions(${COMPONENT_LIB} PRIVATE
        AV_ESP_UPLINK_WIDTH=640
        AV_ESP_UPLINK_HEIGHT=360
        AV_ESP_UPLINK_MAX_FPS=15
        AV_ESP_JPEG_QUALITY=50)
endif()

# HAL_Audio 以 OBJECT 库直接参与最终链接，避免静态库链接顺序导致 tc_iot_sdk 找不到 HAL 符号。
add_library(watch_hal_audio_obj OBJECT "${CMAKE_CURRENT_LIST_DIR}/HAL_Audio_esp.c")
target_include_directories(watch_hal_audio_obj PRIVATE
    $<TARGET_PROPERTY:${COMPONENT_LIB},INCLUDE_DIRECTORIES>)
target_compile_definitions(watch_hal_audio_obj PRIVATE
    $<TARGET_PROPERTY:${COMPONENT_LIB},COMPILE_DEFINITIONS>)
target_link_libraries(${COMPONENT_LIB} PUBLIC $<TARGET_OBJECTS:watch_hal_audio_obj>)
