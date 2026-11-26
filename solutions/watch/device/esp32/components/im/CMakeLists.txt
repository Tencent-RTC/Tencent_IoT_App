# 腾讯云 IM SDK（预编译静态库，C API，ESP32-S31）。
#   include/                 TIMCloud*.h 等对外头文件，以及 UserSig 压缩用的 zlib.h / zconf.h
#   lib/esp32s31/            libim.a
set(_IM_SDK_LIB "${CMAKE_CURRENT_LIST_DIR}/lib/esp32s31/libim.a")

idf_component_register(
    INCLUDE_DIRS include
    REQUIRES esp_netif esp_http_client freertos mbedtls log nvs_flash
             heap esp_system esp_rom esp_timer pthread)

add_library(im_sdk_prebuilt STATIC IMPORTED GLOBAL)
set_target_properties(im_sdk_prebuilt PROPERTIES IMPORTED_LOCATION "${_IM_SDK_LIB}")
target_link_libraries(${COMPONENT_LIB} INTERFACE im_sdk_prebuilt)
# 库内为 LTO 对象，链接阶段需要 -flto。
target_link_libraries(${COMPONENT_LIB} INTERFACE -flto)
# 注意：对外头文件 TIMCloudComm.h 含 `typedef unsigned char bool`，C23（IDF v6 默认 gnu23）
# 下 bool 是关键字，引用方须用 -std=gnu17 编译（见 cmd_watch）。
