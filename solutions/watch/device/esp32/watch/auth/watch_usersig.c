#include "watch/usersig.h"

#include <stdio.h>
#include <string.h>
#include <time.h>
#include <zlib.h>

typedef struct {
  uint32_t h[8];
  uint64_t total;
  uint8_t buffer[64];
  size_t used;
} watch_sha256_t;

static const uint32_t k_sha256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
    0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
    0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
    0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
    0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
    0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb,
    0xbef9a3f7, 0xc67178f2};

static uint32_t watch_rotr(uint32_t value, unsigned int bits) {
  return (value >> bits) | (value << (32u - bits));
}

static void watch_sha256_block(watch_sha256_t *ctx, const uint8_t *input) {
  uint32_t words[64];
  for (unsigned int i = 0; i < 16; ++i) {
    words[i] = ((uint32_t)input[i * 4] << 24) | ((uint32_t)input[i * 4 + 1] << 16) |
               ((uint32_t)input[i * 4 + 2] << 8) | input[i * 4 + 3];
  }
  for (unsigned int i = 16; i < 64; ++i) {
    uint32_t s0 = watch_rotr(words[i - 15], 7) ^ watch_rotr(words[i - 15], 18) ^
                  (words[i - 15] >> 3);
    uint32_t s1 = watch_rotr(words[i - 2], 17) ^ watch_rotr(words[i - 2], 19) ^
                  (words[i - 2] >> 10);
    words[i] = words[i - 16] + s0 + words[i - 7] + s1;
  }

  uint32_t a = ctx->h[0], b = ctx->h[1], c = ctx->h[2], d = ctx->h[3];
  uint32_t e = ctx->h[4], f = ctx->h[5], g = ctx->h[6], h = ctx->h[7];
  for (unsigned int i = 0; i < 64; ++i) {
    uint32_t s1 = watch_rotr(e, 6) ^ watch_rotr(e, 11) ^ watch_rotr(e, 25);
    uint32_t choose = (e & f) ^ (~e & g);
    uint32_t t1 = h + s1 + choose + k_sha256[i] + words[i];
    uint32_t s0 = watch_rotr(a, 2) ^ watch_rotr(a, 13) ^ watch_rotr(a, 22);
    uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
    uint32_t t2 = s0 + majority;
    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }
  ctx->h[0] += a;
  ctx->h[1] += b;
  ctx->h[2] += c;
  ctx->h[3] += d;
  ctx->h[4] += e;
  ctx->h[5] += f;
  ctx->h[6] += g;
  ctx->h[7] += h;
}

static void watch_sha256_init(watch_sha256_t *ctx) {
  static const uint32_t initial[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                     0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  memcpy(ctx->h, initial, sizeof(initial));
  ctx->total = 0;
  ctx->used = 0;
}

static void watch_sha256_update(watch_sha256_t *ctx, const uint8_t *input, size_t length) {
  ctx->total += length;
  while (length > 0) {
    size_t take = sizeof(ctx->buffer) - ctx->used;
    if (take > length) take = length;
    memcpy(ctx->buffer + ctx->used, input, take);
    ctx->used += take;
    input += take;
    length -= take;
    if (ctx->used == sizeof(ctx->buffer)) {
      watch_sha256_block(ctx, ctx->buffer);
      ctx->used = 0;
    }
  }
}

static void watch_sha256_final(watch_sha256_t *ctx, uint8_t output[32]) {
  uint64_t bit_length = ctx->total * 8;
  uint8_t marker = 0x80;
  uint8_t zero = 0;
  watch_sha256_update(ctx, &marker, 1);
  while (ctx->used != 56) watch_sha256_update(ctx, &zero, 1);
  uint8_t length[8];
  for (unsigned int i = 0; i < 8; ++i) length[i] = (uint8_t)(bit_length >> (56 - 8 * i));
  watch_sha256_update(ctx, length, sizeof(length));
  for (unsigned int i = 0; i < 8; ++i) {
    output[i * 4] = (uint8_t)(ctx->h[i] >> 24);
    output[i * 4 + 1] = (uint8_t)(ctx->h[i] >> 16);
    output[i * 4 + 2] = (uint8_t)(ctx->h[i] >> 8);
    output[i * 4 + 3] = (uint8_t)ctx->h[i];
  }
}

void watch_usersig_sha256(const uint8_t *msg, size_t len, uint8_t out[32]) {
  watch_sha256_t ctx;
  watch_sha256_init(&ctx);
  watch_sha256_update(&ctx, msg, len);
  watch_sha256_final(&ctx, out);
}

void watch_usersig_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg,
                               size_t msg_len, uint8_t out[32]) {
  uint8_t normalized_key[64] = {0};
  if (key_len > sizeof(normalized_key)) {
    watch_usersig_sha256(key, key_len, normalized_key);
  } else {
    memcpy(normalized_key, key, key_len);
  }
  uint8_t ipad[64], opad[64];
  for (unsigned int i = 0; i < 64; ++i) {
    ipad[i] = normalized_key[i] ^ 0x36;
    opad[i] = normalized_key[i] ^ 0x5c;
  }

  uint8_t inner[32];
  watch_sha256_t ctx;
  watch_sha256_init(&ctx);
  watch_sha256_update(&ctx, ipad, sizeof(ipad));
  watch_sha256_update(&ctx, msg, msg_len);
  watch_sha256_final(&ctx, inner);
  watch_sha256_init(&ctx);
  watch_sha256_update(&ctx, opad, sizeof(opad));
  watch_sha256_update(&ctx, inner, sizeof(inner));
  watch_sha256_final(&ctx, out);
}

static int watch_base64(const uint8_t *input, size_t length, char *output, size_t capacity) {
  static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  size_t required = ((length + 2) / 3) * 4;
  if (required + 1 > capacity) return -1;
  size_t written = 0;
  for (size_t i = 0; i < length; i += 3) {
    uint32_t value = (uint32_t)input[i] << 16;
    if (i + 1 < length) value |= (uint32_t)input[i + 1] << 8;
    if (i + 2 < length) value |= input[i + 2];
    output[written++] = alphabet[(value >> 18) & 0x3f];
    output[written++] = alphabet[(value >> 12) & 0x3f];
    output[written++] = i + 1 < length ? alphabet[(value >> 6) & 0x3f] : '=';
    output[written++] = i + 2 < length ? alphabet[value & 0x3f] : '=';
  }
  output[written] = '\0';
  return (int)written;
}

static int watch_escape_json(const char *input, char *output, size_t capacity) {
  size_t written = 0;
  for (const unsigned char *p = (const unsigned char *)input; *p; ++p) {
    char escaped[8];
    const char *replacement = NULL;
    if (*p == '"') replacement = "\\\"";
    else if (*p == '\\') replacement = "\\\\";
    else if (*p < 0x20) {
      (void)snprintf(escaped, sizeof(escaped), "\\u%04x", *p);
      replacement = escaped;
    }
    if (!replacement) {
      if (written + 2 > capacity) return -1;
      output[written++] = (char)*p;
      continue;
    }
    size_t n = strlen(replacement);
    if (written + n + 1 > capacity) return -1;
    memcpy(output + written, replacement, n);
    written += n;
  }
  if (written >= capacity) return -1;
  output[written] = '\0';
  return (int)written;
}

int watch_usersig_generate_at(uint32_t sdk_app_id, const char *secret_key, const char *user_id,
                              uint32_t expire_sec, int64_t now, char *out, size_t out_size) {
  if (sdk_app_id == 0 || !secret_key || !secret_key[0] || !user_id || !user_id[0] ||
      expire_sec == 0 || !out || out_size == 0) {
    return -1;
  }

  char content[512];
  int content_len = snprintf(content, sizeof(content),
                             "TLS.identifier:%s\nTLS.sdkappid:%u\nTLS.time:%lld\nTLS.expire:%u\n",
                             user_id, (unsigned)sdk_app_id, (long long)now, (unsigned)expire_sec);
  if (content_len <= 0 || (size_t)content_len >= sizeof(content)) return -1;

  uint8_t mac[32];
  watch_usersig_hmac_sha256((const uint8_t *)secret_key, strlen(secret_key),
                            (const uint8_t *)content, (size_t)content_len, mac);
  char signature[64];
  if (watch_base64(mac, sizeof(mac), signature, sizeof(signature)) < 0) return -1;

  char escaped_user_id[384];
  if (watch_escape_json(user_id, escaped_user_id, sizeof(escaped_user_id)) < 0) return -1;
  char document[768];
  int document_len = snprintf(document, sizeof(document),
                              "{\"TLS.ver\":\"2.0\",\"TLS.identifier\":\"%s\","
                              "\"TLS.sdkappid\":%u,\"TLS.expire\":%u,\"TLS.time\":%lld,"
                              "\"TLS.sig\":\"%s\"}",
                              escaped_user_id, (unsigned)sdk_app_id, (unsigned)expire_sec,
                              (long long)now, signature);
  if (document_len <= 0 || (size_t)document_len >= sizeof(document)) return -1;

  uint8_t compressed[1024];
  z_stream stream;
  memset(&stream, 0, sizeof(stream));
  if (deflateInit2(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, 9, 1, Z_DEFAULT_STRATEGY) != Z_OK) {
    return -1;
  }
  stream.next_in = (Bytef *)document;
  stream.avail_in = (uInt)document_len;
  stream.next_out = compressed;
  stream.avail_out = (uInt)sizeof(compressed);
  int result = deflate(&stream, Z_FINISH);
  uLong compressed_len = stream.total_out;
  deflateEnd(&stream);
  if (result != Z_STREAM_END) return -1;

  int output_len = watch_base64(compressed, (size_t)compressed_len, out, out_size);
  if (output_len < 0) return -1;
  for (int i = 0; i < output_len; ++i) {
    if (out[i] == '+') out[i] = '*';
    else if (out[i] == '/') out[i] = '-';
    else if (out[i] == '=') out[i] = '_';
  }
  return output_len;
}

int watch_usersig_generate(uint32_t sdk_app_id, const char *secret_key, const char *user_id,
                           uint32_t expire_sec, char *out, size_t out_size) {
  return watch_usersig_generate_at(sdk_app_id, secret_key, user_id, expire_sec,
                                   (int64_t)time(NULL), out, out_size);
}
