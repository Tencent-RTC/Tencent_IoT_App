# 腾讯云 IoT / TRTC SDK（预编译静态库，ESP32-S31）。
#   include/                 对外头文件（tc_iot*.h）
#   hal/                     SDK 回调到板级的音频 HAL 接口（tc_hal_audio.h，由 watch_board 实现）
#   lib/esp32s31/            libtc_iot_sdk.a，须用 ESP-IDF v6.1 编译工程
if(NOT IDF_TARGET STREQUAL "esp32s31")
    message(FATAL_ERROR
        "本工程只支持 ESP32-S31（当前 ${IDF_TARGET}）。"
        "请删除 build 目录后执行 idf.py --preview set-target esp32s31。")
endif()
set(_TC_SDK_LIB "${CMAKE_CURRENT_LIST_DIR}/lib/esp32s31/libtc_iot_sdk.a")

# 预编译库与编译它的 ESP-IDF 版本绑定（IM 库含 LTO 对象，要求完全相同的 GCC），版本不符时
# 链接期会出现难以理解的错误，这里提前拦截。
if(NOT "${IDF_VERSION_MAJOR}.${IDF_VERSION_MINOR}" STREQUAL "6.1")
    message(FATAL_ERROR
        "esp32s31 需要 ESP-IDF v6.1.x，当前为 "
        "v${IDF_VERSION_MAJOR}.${IDF_VERSION_MINOR}。请安装 v6.1 并在新终端里激活。")
endif()

idf_component_register(
    INCLUDE_DIRS include hal hal/src/base
    REQUIRES esp_netif esp_http_client freertos mbedtls log nvs_flash
             heap esp_system esp_rom esp_timer pthread)

add_library(tc_iot_sdk_prebuilt STATIC IMPORTED GLOBAL)
set_target_properties(tc_iot_sdk_prebuilt PROPERTIES IMPORTED_LOCATION "${_TC_SDK_LIB}")
target_link_libraries(${COMPONENT_LIB} INTERFACE tc_iot_sdk_prebuilt)

# 链接顺序：libtc_iot_sdk.a 必须排在 libim.a 之前。两个库各带一份同源的基础层（xc_* 消息循环 /
# HTTP / 线程、HAL_*、zlib 等），先出现的那份会被 IM 与 IoT SDK 共用；固件按「SDK 在前」验证过。
# 声明 SDK 依赖 IM（im_sdk_prebuilt 由 im 组件定义，生成阶段才解析），CMake 就会把 libim.a
# 放在 libtc_iot_sdk.a 之后。
target_link_libraries(tc_iot_sdk_prebuilt INTERFACE im_sdk_prebuilt)
