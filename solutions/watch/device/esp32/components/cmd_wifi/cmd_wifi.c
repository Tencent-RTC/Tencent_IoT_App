#include <stdio.h>
#include <string.h>
#include "esp_log.h"
#include "esp_console.h"
#include "argtable3/argtable3.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_event.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "cmd_wifi.h"

#define JOIN_TIMEOUT_MS (10000)
#define WIFI_NVS_NAMESPACE "wifi_cfg"
#define WIFI_NVS_KEY_SSID "ssid"
#define WIFI_NVS_KEY_PASS "password"

static const char *TAG = "cmd_wifi";

static EventGroupHandle_t s_wifi_event_group;
static const int CONNECTED_BIT = BIT0;
static bool s_wifi_initialized = false;
// join 切换网络期间为 true：断线事件不再自动重连旧配置，否则 sta 一直处于 connecting，
// esp_wifi_set_config 始终返回 ESP_ERR_WIFI_STATE。
static volatile bool s_wifi_switching = false;

static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        if (!s_wifi_switching) {
            esp_wifi_connect();
        }
        xEventGroupClearBits(s_wifi_event_group, CONNECTED_BIT);
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
        ESP_LOGI(TAG, "Got IP: " IPSTR, IP2STR(&event->ip_info.ip));
        xEventGroupSetBits(s_wifi_event_group, CONNECTED_BIT);
    }
}

static void wifi_init(void)
{
    if (s_wifi_initialized) {
        return;
    }
    ESP_ERROR_CHECK(esp_netif_init());
    s_wifi_event_group = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, WIFI_EVENT_STA_DISCONNECTED,
                                               &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                               &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());
    // 关闭 Wi-Fi 省电。IDF 的 STA 默认 WIFI_PS_MIN_MODEM：射频只在 AP 的 DTIM 信标时
    // 醒来收包，期间下行包由 AP 缓存。音视频通话下行是持续的小包流，这会带来 100~300ms
    // 的突发时延；手机热点类 AP 缓存小，满了直接丢包，表现为视频组帧收不齐、音频等重传
    // 积压（packet_buffer full）、RTT 偶发 >1s。代价是待机功耗上升，实时通话设备可接受。
    esp_err_t ps_err = esp_wifi_set_ps(WIFI_PS_NONE);
    if (ps_err != ESP_OK) {
        ESP_LOGW(TAG, "esp_wifi_set_ps(WIFI_PS_NONE) failed: %s", esp_err_to_name(ps_err));
    } else {
        ESP_LOGI(TAG, "wifi power save disabled");
    }
    s_wifi_initialized = true;
}

static bool wifi_join(const char *ssid, const char *pass, int timeout_ms)
{
    wifi_init();
    wifi_config_t wifi_config = {0};
    strlcpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid));
    if (pass) {
        strlcpy((char *)wifi_config.sta.password, pass, sizeof(wifi_config.sta.password));
    }

    // 开机自动重连（以及断线事件里的 esp_wifi_connect）可能正处于连接中，此时
    // esp_wifi_set_config 返回 ESP_ERR_WIFI_STATE（"sta is connecting, cannot set config"）。
    // 原先用 ESP_ERROR_CHECK 会直接 abort 重启——保存的 AP 不在附近时 join 新网络必然触发。
    // 先断开当前尝试，再切换配置；失败时返回错误而不是重启。
    s_wifi_switching = true;
    esp_wifi_disconnect();
    xEventGroupClearBits(s_wifi_event_group, CONNECTED_BIT);
    esp_err_t err = ESP_FAIL;
    for (int i = 0; i < 30; i++) {
        err = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
        if (err != ESP_ERR_WIFI_STATE) {
            break;
        }
        // 自动重连正在扫描时 disconnect 可能不立即生效，重复下发直到 sta 回到空闲。
        esp_wifi_disconnect();
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    s_wifi_switching = false;
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_wifi_set_config failed: %s", esp_err_to_name(err));
        return false;
    }
    esp_wifi_connect();

    int bits = xEventGroupWaitBits(s_wifi_event_group, CONNECTED_BIT,
                                   pdFALSE, pdTRUE, timeout_ms / portTICK_PERIOD_MS);
    return (bits & CONNECTED_BIT) != 0;
}

// Save WiFi credentials to NVS
static esp_err_t wifi_save_to_nvs(const char *ssid, const char *pass)
{
    nvs_handle_t nvs;
    esp_err_t err = nvs_open(WIFI_NVS_NAMESPACE, NVS_READWRITE, &nvs);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_str(nvs, WIFI_NVS_KEY_SSID, ssid);
    if (err == ESP_OK && pass) {
        err = nvs_set_str(nvs, WIFI_NVS_KEY_PASS, pass);
    } else if (err == ESP_OK) {
        // 开放网络：清掉上一个 AP 的密码，否则开机自动重连会带着旧密码（authmode 阈值被抬到
        // WPA2），开放热点被过滤，表现为 "Haven't to connect to a suitable AP now!"。
        esp_err_t e = nvs_erase_key(nvs, WIFI_NVS_KEY_PASS);
        if (e != ESP_OK && e != ESP_ERR_NVS_NOT_FOUND) {
            err = e;
        }
    }
    if (err == ESP_OK) {
        err = nvs_commit(nvs);
    }
    nvs_close(nvs);
    return err;
}

/** 'join' command */
static struct {
    struct arg_int *timeout;
    struct arg_str *ssid;
    struct arg_str *password;
    struct arg_end *end;
} join_args;

static int cmd_join(int argc, char **argv)
{
    int nerrors = arg_parse(argc, argv, (void **)&join_args);
    if (nerrors != 0) {
        arg_print_errors(stderr, join_args.end, argv[0]);
        return 1;
    }

    const char *ssid = join_args.ssid->sval[0];
    const char *pass = join_args.password->count > 0 ? join_args.password->sval[0] : NULL;
    int timeout = join_args.timeout->count > 0 ? join_args.timeout->ival[0] : JOIN_TIMEOUT_MS;

    ESP_LOGI(TAG, "Connecting to '%s'...", ssid);
    bool connected = wifi_join(ssid, pass, timeout);
    if (!connected) {
        ESP_LOGW(TAG, "Connection timed out");
        return 1;
    }

    ESP_LOGI(TAG, "Connected");
    // Save to NVS on success
    esp_err_t err = wifi_save_to_nvs(ssid, pass);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "WiFi credentials saved to NVS");
    } else {
        ESP_LOGW(TAG, "Failed to save credentials: %s", esp_err_to_name(err));
    }
    return 0;
}

/** 'wifi_status' command */
static int cmd_wifi_status(int argc, char **argv)
{
    wifi_ap_record_t ap_info;
    esp_netif_ip_info_t ip_info;
    esp_netif_t *sta_netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");

    if (!s_wifi_initialized) {
        printf("WiFi not initialized\n");
        return 0;
    }

    if (esp_wifi_sta_get_ap_info(&ap_info) == ESP_OK) {
        printf("Connected to: %s\n", (char *)ap_info.ssid);
        printf("RSSI: %d\n", ap_info.rssi);
    } else {
        printf("Not connected\n");
    }

    if (sta_netif && esp_netif_get_ip_info(sta_netif, &ip_info) == ESP_OK) {
        printf("IP:   " IPSTR "\n", IP2STR(&ip_info.ip));
        printf("GW:   " IPSTR "\n", IP2STR(&ip_info.gw));
        printf("Mask: " IPSTR "\n", IP2STR(&ip_info.netmask));
    }

    // Show saved config
    nvs_handle_t nvs;
    if (nvs_open(WIFI_NVS_NAMESPACE, NVS_READONLY, &nvs) == ESP_OK) {
        char ssid[33] = {0};
        size_t len = sizeof(ssid);
        if (nvs_get_str(nvs, WIFI_NVS_KEY_SSID, ssid, &len) == ESP_OK) {
            printf("Saved SSID: %s\n", ssid);
        } else {
            printf("No saved WiFi config\n");
        }
        nvs_close(nvs);
    }

    return 0;
}

/** 'wifi_clear' command */
static int cmd_wifi_clear(int argc, char **argv)
{
    nvs_handle_t nvs;
    esp_err_t err = nvs_open(WIFI_NVS_NAMESPACE, NVS_READWRITE, &nvs);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS: %s", esp_err_to_name(err));
        return 1;
    }
    nvs_erase_all(nvs);
    nvs_commit(nvs);
    nvs_close(nvs);
    ESP_LOGI(TAG, "WiFi credentials cleared");
    return 0;
}

void register_wifi(void)
{
    join_args.timeout = arg_int0(NULL, "timeout", "<t>", "Connection timeout, ms");
    join_args.ssid = arg_str1(NULL, NULL, "<ssid>", "SSID of AP");
    join_args.password = arg_str0(NULL, NULL, "<pass>", "PSK of AP");
    join_args.end = arg_end(2);

    const esp_console_cmd_t join_cmd = {
        .command = "join",
        .help = "Join WiFi AP as a station",
        .hint = NULL,
        .func = &cmd_join,
        .argtable = &join_args
    };
    ESP_ERROR_CHECK(esp_console_cmd_register(&join_cmd));

    const esp_console_cmd_t status_cmd = {
        .command = "wifi_status",
        .help = "Show WiFi connection status and saved config",
        .hint = NULL,
        .func = &cmd_wifi_status,
    };
    ESP_ERROR_CHECK(esp_console_cmd_register(&status_cmd));

    const esp_console_cmd_t clear_cmd = {
        .command = "wifi_clear",
        .help = "Clear saved WiFi credentials from NVS",
        .hint = NULL,
        .func = &cmd_wifi_clear,
    };
    ESP_ERROR_CHECK(esp_console_cmd_register(&clear_cmd));
}

void wifi_auto_connect_from_nvs(void)
{
    nvs_handle_t nvs;
    if (nvs_open(WIFI_NVS_NAMESPACE, NVS_READONLY, &nvs) != ESP_OK) {
        return;
    }

    char ssid[33] = {0};
    char pass[65] = {0};
    size_t ssid_len = sizeof(ssid);
    size_t pass_len = sizeof(pass);

    esp_err_t err = nvs_get_str(nvs, WIFI_NVS_KEY_SSID, ssid, &ssid_len);
    if (err != ESP_OK || ssid_len == 0) {
        nvs_close(nvs);
        return;
    }

    // Password is optional
    nvs_get_str(nvs, WIFI_NVS_KEY_PASS, pass, &pass_len);
    nvs_close(nvs);

    ESP_LOGI(TAG, "Auto-connecting to saved AP '%s'...", ssid);

    // Non-blocking: init WiFi and start connect, don't wait for result
    wifi_init();
    wifi_config_t wifi_config = {0};
    strlcpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid));
    if (strlen(pass) > 0) {
        strlcpy((char *)wifi_config.sta.password, pass, sizeof(wifi_config.sta.password));
    }
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    esp_wifi_connect();
}
