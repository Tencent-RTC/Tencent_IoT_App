/**
 * ConfirmDialog —— 确认弹窗控件（基于 CommonBottomSheet，文字使用正常正文风格）
 *
 * 结构：
 *   DragHandle → 标题(DialogTitleText,居中) → 提示消息(SecondaryText,居中) → 确定/取消按钮(并排)
 *
 * 与 CommonBottomSheet 的区别：
 *   - 提示语使用 SecondaryText（14px，#9DA3B0）正常正文风格，而非 CaptionText（12px）
 *   - 无自定义内容区域（@BuilderParam），专用于纯确认场景
 *
 * 使用示例：
 *   ConfirmDialog({
 *     show: $showDialog,
 *     title: '删除确认',
 *     message: '确定要删除该记录吗？此操作不可撤销。',
 *     confirmText: '删除',
 *     confirmDanger: true,         // 可选，危险操作使用红色按钮
 *     cancelText: '取消',
 *     onConfirm: () => { ... },
 *     onCancel: () => { ... }
 *   })
 */

import { AppColor, PrimaryButton, DangerButton, CancelButton, DialogTitleText, BodyText, DragHandle } from './AppTheme'

@Component
export struct ConfirmDialog {
  // 是否显示（外部 @State → $ 传入）
  @Link show: boolean
  // 标题文字
  title: string = ''
  // 提示消息文字（@Prop 确保父组件动态拼接的 message 能实时同步）
  @Prop message: string = ''
  // 确定按钮文字
  confirmText: string = '确定'
  // 确定按钮图标（可选，留空则不显示图标）
  confirmIcon: string = ''
  // 确定按钮是否使用危险样式（红色渐变，用于删除/撤销等操作）
  confirmDanger: boolean = false
  // 取消按钮文字
  cancelText: string = '取消'
  // 确定回调（不会自动关闭弹窗，由调用者控制关闭时机）
  onConfirm: () => void = () => {
  }
  // 取消回调（蒙层点击也会触发）
  onCancel: () => void = () => {
  }

  close() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.show = false
    })
  }

  handleCancel() {
    this.onCancel()
    this.close()
  }

  build() {
    if (this.show) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 蒙层：半透明黑色遮罩，点击关闭
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppColor.BgMask)
          .onClick(() => {
            this.handleCancel()
          })
          .transition(TransitionEffect.opacity(0).animation({ duration: 200, curve: Curve.EaseOut }))

        // 底部抽屉内容面板
        Column() {
          // 拖动指示条
          DragHandle()

          // 标题（DialogTitleText 风格，居中对齐）
          Text(this.title)
            .attributeModifier(DialogTitleText)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 18 })
            .padding({ left: 32, right: 32 })

          // 提示消息（BodyText 风格，正常正文，居中）
          if (this.message.length > 0) {
            Text(this.message)
              .attributeModifier(BodyText)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 28 })
              .padding({ left: 16, right: 16 })
          }

          // 按钮行：确定 + 取消（并排一行）
          Row({ space: 12 }) {
            // 确定按钮
            if (this.confirmDanger) {
              Button(this.confirmText)
                .attributeModifier(DangerButton)
                .layoutWeight(1)
                .onClick(() => {
                  this.onConfirm()
                })
            } else {
              Button() {
                Row({ space: 6 }) {
                  if (this.confirmIcon.length > 0) {
                    Text(this.confirmIcon).fontSize(14).fontColor('#FFFFFF')
                  }
                  Text(this.confirmText).fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Normal)
                }
              }
              .attributeModifier(PrimaryButton)
              .layoutWeight(1)
              .onClick(() => {
                this.onConfirm()
              })
            }

            // 取消按钮
            Button(this.cancelText)
              .attributeModifier(CancelButton)
              .layoutWeight(1)
              .onClick(() => {
                this.handleCancel()
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ top: 28, bottom: 28 })
        }
        .width('100%')
        .backgroundColor(AppColor.BgCard)
        .borderRadius({ topLeft: 24, topRight: 24 })
        .transition(
          TransitionEffect.translate({ y: 400 })
            .combine(TransitionEffect.opacity(0))
            .animation({ duration: 300, curve: Curve.EaseOut })
        )
      }
      .width('100%').height('100%')
      .position({ x: 0, y: 0 }).zIndex(100)
    }
  }
}
