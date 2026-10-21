/**
 * 消息中心页面 —— 对齐 iOS MessageListView
 *
 * 新 SDK 已移除 SDK 消息接口，本页面只展示推送通知。
 * 结构：渐变头部(返回+标题+清空) → 推送消息列表（可展开详情）
 */

import router from '@ohos.router'
import emitter from '@ohos.events.emitter'
import { AppState, PushMessageItem, PUSH_MSG_EVENT_ID } from '../model/AppModel'
import {
  AppColor,
  GradientNavBar,
  DialogTitleText,
  SecondaryText,
  DangerButton,
  CancelButton
} from '../components/AppTheme'

// ==================== 消息中心页面 ====================

@Entry
@Component
struct MessageListPage {
  @State pushMessages: PushMessageItem[] = []
  @State expandedId: string = ''
  @State showClearDialog: boolean = false
  private emitterListener: emitter.InnerEvent = { eventId: PUSH_MSG_EVENT_ID }

  aboutToAppear() {
    this.syncPushMessages()
    emitter.on(this.emitterListener, (eventData) => {
      try {
        const itemStr = eventData?.data?.['item'] as string
        if (itemStr) {
          const raw = JSON.parse(itemStr) as PushMessageItem
          this.pushMessages = [raw, ...this.pushMessages].slice(0, 200)
        }
      } catch (e) {
        console.error('解析推送消息失败: ' + e)
      }
    })
  }

  onPageShow() {
    this.syncPushMessages()
  }

  aboutToDisappear() {
    emitter.off(PUSH_MSG_EVENT_ID)
  }

  syncPushMessages() {
    this.pushMessages = [...AppState.pushMessages]
  }

  // 类型标签（对齐 iOS PushMessageItem.typeLabel）
  getTypeLabel(type: number): string {
    if (type === 0) {
      return '状态变更'
    }
    return '未知'
  }

  // 子类型标签（对齐 iOS PushMessageItem.subTypeLabel）
  getSubTypeLabel(subType: number): string {
    if (subType === 0) {
      return '上线'
    }
    if (subType === 1) {
      return '下线'
    }
    return ''
  }

  // 类型颜色（对齐 iOS PushMessageItem.typeColor）
  getTypeColor(type: number, subType: number): string {
    if (type === 0) {
      return subType === 0 ? AppColor.Success : AppColor.TextSecondary
    }
    return AppColor.Brand
  }

  formatTime(ms: number): string {
    const d = new Date(ms)
    const m = String(d.getMonth() + 1).padStart(2, '0')
    const day = String(d.getDate()).padStart(2, '0')
    const h = String(d.getHours()).padStart(2, '0')
    const min = String(d.getMinutes()).padStart(2, '0')
    const s = String(d.getSeconds()).padStart(2, '0')
    return `${m}-${day} ${h}:${min}:${s}`
  }

  goBack() {
    router.back()
  }

  clearMessages() {
    AppState.clearPushMessages()
    this.pushMessages = []
    this.showClearDialog = false
  }

  build() {
    Column() {
      // ===== 顶部渐变导航栏（对齐 iOS headerBanner + navBar）=====
      GradientNavBar({
        title: '消息中心', onBack: () => {
          this.goBack()
        }
      }) {
        if (this.pushMessages.length > 0) {
          Button() {
            Text('🗑').fontSize(16)
          }
          .width(44).height(44)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showClearDialog = true
          })
        } else {
          Column().width(44).height(44)
        }
      }

      // ===== 推送通知内容区域（对齐 iOS pushNotificationContent）=====
      if (this.pushMessages.length === 0) {
        // 空状态（对齐 iOS: bell.slash + 暂无推送消息）
        Column({ space: 14 }) {
          Text('🔕').fontSize(60)
          Text('暂无推送消息')
            .fontSize(16).fontColor(AppColor.TextSecondary)
          Text('设备上线/下线等消息将在此显示')
            .fontSize(13).fontColor(AppColor.TextTertiary)
            .textAlign(TextAlign.Center)
            .padding({ left: 40, right: 40 })
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(AppColor.BgPage)
      } else {
        // 推送消息列表（对齐 iOS: List plain style, white bg）
        List({ space: 0 }) {
          ForEach(this.pushMessages, (item: PushMessageItem) => {
            ListItem() {
              Column({ space: 0 }) {
                // 主行（对齐 iOS PushMessageRowView 主行）
                Row({ space: 10 }) {
                  // 类型标签
                  Text(this.getTypeLabel(item.type))
                    .fontSize(11)
                    .fontColor('#ffffff')
                    .fontWeight(FontWeight.Medium)
                    .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                    .backgroundColor(this.getTypeColor(item.type, item.subType))
                    .borderRadius(4)

                  // 设备信息（对齐 iOS deviceInfoView）
                  Column({ space: 2 }) {
                    Text(item.productId + '/' + item.deviceName)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(AppColor.TextPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row({ space: 6 }) {
                      if (this.getSubTypeLabel(item.subType)) {
                        Text(this.getSubTypeLabel(item.subType))
                          .fontSize(11)
                          .fontColor(this.getTypeColor(item.type, item.subType))
                      }
                      Text(this.formatTime(item.messageTime))
                        .fontSize(11)
                        .fontColor(AppColor.TextTertiary)
                    }
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)

                  // 展开箭头（对齐 iOS expandChevron）
                  Text(this.expandedId === item.id ? '∧' : '∨')
                    .fontSize(12)
                    .fontColor(AppColor.TextTertiary)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .onClick(() => {
                  this.expandedId = this.expandedId === item.id ? '' : item.id
                })

                // 展开详情（对齐 iOS expandedDetails）
                if (this.expandedId === item.id) {
                  Column({ space: 6 }) {
                    Divider().color(AppColor.Divider)
                    Text('产品ID: ' + item.productId)
                      .fontSize(11)
                      .fontColor(AppColor.TextSecondary)
                      .fontFamily('monospace')
                      .width('100%')
                    Text('设备名: ' + item.deviceName)
                      .fontSize(11)
                      .fontColor(AppColor.TextSecondary)
                      .fontFamily('monospace')
                      .width('100%')
                    Text('时间: ' + this.formatTime(item.messageTime))
                      .fontSize(11)
                      .fontColor(AppColor.TextSecondary)
                      .fontFamily('monospace')
                      .width('100%')
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 12 })
                }
              }
              .width('100%')
              .backgroundColor(AppColor.BgCard)
            }
            .border({ width: { bottom: 1 }, color: { bottom: AppColor.Divider } })
          }, (item: PushMessageItem) => item.id)
        }
        .width('100%').layoutWeight(1)
        .backgroundColor(AppColor.BgCard)
      }

      // ===== 清空确认弹窗（对齐 iOS alert: 清空推送）=====
      if (this.showClearDialog) {
        Stack() {
          Column()
            .width('100%').height('100%')
            .backgroundColor(AppColor.BgMask)
            .onClick(() => {
              this.showClearDialog = false
            })

          Column({ space: 12 }) {
            Text('清空推送')
              .attributeModifier(DialogTitleText)
            Text('确定要清空所有推送消息吗？')
              .attributeModifier(SecondaryText).textAlign(TextAlign.Center)
            Row({ space: 12 }) {
              Button('取消')
                .attributeModifier(CancelButton).layoutWeight(1)
                .onClick(() => {
                  this.showClearDialog = false
                })
              Button('清空')
                .attributeModifier(DangerButton).layoutWeight(1)
                .onClick(() => {
                  this.clearMessages()
                })
            }
            .width('100%')
          }
          .width('85%').padding(28)
          .backgroundColor(AppColor.BgCard).borderRadius(12)
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 }).zIndex(100)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(AppColor.BgPage)
  }
}
