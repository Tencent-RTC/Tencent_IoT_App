package com.tencent.iot.watchapp

import com.tencent.iot.watchapp.call.*
import com.tencent.iot.watchapp.config.*
import com.tencent.iot.watchapp.im.*

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class TencentUserSigGeneratorTest {
    @Test
    fun userIdUsesTheSharedPhoneIdentityRule() {
        assertEquals("9001_phone", WatchIdentity.userId(" 9001 "))
        assertEquals("9001_phone", WatchIdentity.userId("9001"))
    }

    @Test
    fun userSigIsDeterministicForTheSameInput() {
        val first = TencentUserSigGenerator.generate(
            sdkAppId = 1400000000L,
            userId = "9001_phone",
            secretKey = "local-secret",
            nowSeconds = 1_700_000_000L,
        )
        val second = TencentUserSigGenerator.generate(
            sdkAppId = 1400000000L,
            userId = "9001_phone",
            secretKey = "local-secret",
            nowSeconds = 1_700_000_000L,
        )

        assertEquals(first, second)
        assertTrue(first.isNotBlank())
        assertFalse(first.contains("/"))
        assertFalse(first.contains("+"))
    }

    @Test
    fun configuredImSdkCredentialsUseTheSharedIdentity() {
        if (WatchSdkConfig.IM_SDK_APP_ID == 0L || WatchSdkConfig.IM_SECRET_KEY.isBlank()) {
            assertThrows(IllegalArgumentException::class.java) {
                ImSdkAuth.forChannel("9001", nowSeconds = 1_700_000_000L)
            }
            return
        }
        val credentials = ImSdkAuth.forChannel("9001", nowSeconds = 1_700_000_000L)

        assertEquals(WatchSdkConfig.IM_SDK_APP_ID, credentials.sdkAppId)
        assertEquals("9001_phone", credentials.userId)
        assertTrue(credentials.userSig.isNotBlank())
    }
}
