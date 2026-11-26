# W317 watch 模块发布模板。
#
# 这是按常见 ms_code 模块写法准备的接入模板，不代表所有 W317 基线的变量名都一致。
# 客户需要参考自身基线的 minidemo / trtc 模块，确认：
#   1. mk 文件的加载位置和 include 方式；
#   2. MINCPATH、MSRCPATH、SOURCES、MCFLAG_OPT 的实际语义；
#   3. COMPLIBS_DBG 对模块源码和 WATCH_LIBS 的链接方式。
#
# 所有路径都相对于客户基线中的 external/watch，不包含绝对路径。

WATCH_MODULE_ROOT ?= external/watch
WATCH_SDK_ROOT ?= $(WATCH_MODULE_ROOT)/sdk

MINCPATH += \
    $(WATCH_MODULE_ROOT)/include \
    $(WATCH_MODULE_ROOT)/platform/common \
    $(WATCH_MODULE_ROOT)/platform/w317 \
    $(WATCH_MODULE_ROOT)/message \
    $(WATCH_MODULE_ROOT)/third_party/cJSON \
    $(WATCH_MODULE_ROOT)/third_party/cJSON_compat \
    $(WATCH_SDK_ROOT)/include

MSRCPATH += \
    $(WATCH_MODULE_ROOT)/app \
    $(WATCH_MODULE_ROOT)/auth \
    $(WATCH_MODULE_ROOT)/media \
    $(WATCH_MODULE_ROOT)/message \
    $(WATCH_MODULE_ROOT)/signaling \
    $(WATCH_MODULE_ROOT)/platform/common \
    $(WATCH_MODULE_ROOT)/platform/w317 \
    $(WATCH_MODULE_ROOT)/third_party/cJSON

SOURCES += \
    watch_app.c \
    watch_config.c \
    watch_usersig.c \
    watch_media.c \
    watch_message.c \
    watch_message_im.c \
    watch_signal_codec.c \
    watch_signaling.c \
    watch_media_iot.c \
    watch_entry_w317.c \
    watch_platform_w317.c \
    watch_media_source_w317.c \
    watch_video_receiver_w317.c \
    cJSON.c

# 客户按自身基线的编译变量调整；watch 核心使用 GNU C99 语法。
MCFLAG_OPT += -std=gnu99

# 当前临时发布包中的两个库来自 ESP32，仅用于目录和链接配置占位，不能用于 W317。
WATCH_LIBS += \
    $(WATCH_SDK_ROOT)/lib/libtc_iot_sdk.a \
    $(WATCH_SDK_ROOT)/lib/libim.a
