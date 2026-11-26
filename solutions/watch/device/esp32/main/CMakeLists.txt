idf_component_register(
    SRCS "app_main.c" "console_settings.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES
        console esp_driver_uart esp_driver_usb_serial_jtag esp_usb_cdc_rom_console
        fatfs nvs_flash spiffs esp_psram
        cmd_system cmd_wifi cmd_nvs cmd_watch)

# TC_ENABLE_WATCH=1：注册 watch_* 命令；APP_SYS_MONITOR=0：不周期打印 CPU / 堆统计。
target_compile_definitions(${COMPONENT_LIB} PRIVATE
    TC_PRODUCT_TRTC=0
    TC_ENABLE_WATCH=1
    APP_SYS_MONITOR=0)
