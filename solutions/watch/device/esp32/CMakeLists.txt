# watch ESP-IDF 工程（ESP32-S31-Korvo-1，ESP-IDF v6.1）。
#
#   idf.py --preview set-target esp32s31
#   idf.py build
#   idf.py -p <串口> flash monitor
#
# 配置文件：watch/config.h（编译期固化进固件）。
cmake_minimum_required(VERSION 3.22)

# 公共默认配置 + sdkconfig.defaults.esp32s31（IDF 按芯片自动叠加）。
set(SDKCONFIG_DEFAULTS "${CMAKE_CURRENT_LIST_DIR}/sdkconfig.defaults")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
# 只编译 main 及其依赖的组件。
idf_build_set_property(MINIMAL_BUILD ON)
# 依赖版本已在 main/idf_component.yml 中固定，不再联网探测新版本。
set(ENV{IDF_COMPONENT_CHECK_NEW_VERSION} 0)
project(watch)

# storage 分区（SPIFFS，挂载到 /data）：存放 IM 本地数据与命令历史。
spiffs_create_partition_image(storage spiffs_data FLASH_IN_PROJECT)
