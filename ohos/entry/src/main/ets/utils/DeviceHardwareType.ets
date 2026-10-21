/**
 * 设备硬件类型判定（对齐 Android: common/util/DeviceHardwareType.kt）
 * 通过 productId 白名单识别吸顶灯，其余默认按摄像头处理。
 */
export class DeviceHardwareType {
  /** 吸顶灯产品 ID 白名单，包含 Android Demo 使用的产品。 */
  private static readonly CEILING_LAMP_PRODUCT_IDS: string[] = [
    '988BYEG00X',
  ]

  static isCeilingLamp(productId: string): boolean {
    return DeviceHardwareType.CEILING_LAMP_PRODUCT_IDS.indexOf(productId) >= 0
  }

  static isCamera(productId: string): boolean {
    return !DeviceHardwareType.isCeilingLamp(productId)
  }

  /** 设备详情页路由（对齐 Android getDetailEntry 的分发逻辑） */
  static getDetailRoute(productId: string): string {
    return DeviceHardwareType.isCeilingLamp(productId) ? 'pages/LampDetailPage' : 'pages/DeviceDetailPage'
  }
}
