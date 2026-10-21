/**
 * CommonBottomSheet —— 通用底部抽屉弹窗控件（对齐 iOS CommonBottomSheet.swift）
 *
 * 结构（与 iOS 一致）：
 *   拖动指示条 → 标题(居中) → 提示语(居中,可选) → 自定义内容 → 确定/取消按钮(并排)
 *
 * 使用示例：
 *   CommonBottomSheet({
 *     show: $showMyDialog,
 *     title: '操作确认',
 *     caption: '确定要执行此操作吗？',
 *     showCaption: true,            // 可选，默认 true
 *     confirmText: '确定',
 *     confirmIcon: '✓',            // 可选，留空不显示图标
 *     confirmDanger: false,        // 可选，危险操作使用红色按钮
 *     confirmOutlined: false,      // 可选，描边样式（品牌色描边，对齐 iOS .outlined）
 *     confirmEnabled: true,        // 可选，false 时按钮置灰不可点（对齐 iOS confirmEnabled）
 *     showConfirm: true,           // 可选，false 时隐藏确定按钮
 *     cancelText: '取消',
 *     onConfirm: () => { ... },    // 确认回调，不会自动关闭弹窗
 *     onCancel: () => { ... }      // 取消回调（蒙层点击也会触发）
 *   }) {
 *     // 自定义内容区域
 *     Text('这里是调用者自由展示的内容')
 *   }
 *
 * 外部关闭弹窗：
 *   在 onConfirm / onCancel 中通过将 @State 变量设为 false 来关闭。
 *   建议使用 animateTo 包裹以获得过渡动画：
 *     animateTo({ duration: 300, curve: Curve.EaseInOut }, () => { this.showMyDialog = false })
 */

import {
  AppColor,
  AppFontSize,
  AppHeight,
  AppRadius,
  PrimaryButton,
  DangerButton,
  CancelButton,
  DialogTitleText,
  CaptionText,
  DragHandle
} from './AppTheme'

@Component
export struct CommonBottomSheet {
  // 是否显示（外部 @State → $ 传入）
  @Link show: boolean
  // 标题文字
  title: string = ''
  // 提示语文字（@Prop 确保父组件动态拼接的 caption 能实时同步，避免初次创建后不再更新）
  @Prop caption: string = ''
  // 是否显示提示语
  showCaption: boolean = true
  // 确定按钮文字
  confirmText: string = '确定'
  // 确定按钮图标（可选，留空则不显示图标）
  confirmIcon: string = ''
  // 确定按钮是否使用危险样式（红色渐变，用于删除/撤销等操作）
  confirmDanger: boolean = false
  // 确定按钮是否使用描边样式（品牌色描边，对齐 iOS .outlined）
  confirmOutlined: boolean = false
  // 确定按钮是否可用（false 时置灰不可点击，对齐 iOS confirmEnabled）
  // @Prop 确保父组件动态计算的 enabled 状态能实时同步（如别名输入框非空校验）
  @Prop confirmEnabled: boolean = true
  // 是否显示确定按钮（默认 true，设为 false 时取消按钮撑满宽度）
  showConfirm: boolean = true
  // 取消按钮文字
  cancelText: string = '取消'
  // 确定回调（不会自动关闭弹窗，由调用者控制关闭时机）
  onConfirm: () => void = () => {
  }
  // 取消回调（蒙层点击也会触发）
  onCancel: () => void = () => {
  }
  // 自定义内容区域（调用者通过尾随闭包传入）
  @BuilderParam content: () => void = this.emptyContent

  @Builder
  emptyContent() {
  }

  // 确定按钮内容（图标 + 文字），文字颜色随样式变化
  @Builder
  confirmButtonContent() {
    Row({ space: 6 }) {
      if (this.confirmIcon.length > 0) {
        Text(this.confirmIcon)
          .fontSize(14)
          .fontColor(this.confirmOutlined ? AppColor.Brand : AppColor.TextOnPrimary)
      }
      Text(this.confirmText)
        .fontSize(AppFontSize.H3)
        .fontColor(this.confirmOutlined ? AppColor.Brand : AppColor.TextOnPrimary)
        .fontWeight(FontWeight.Normal)
    }
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
            .margin({ top: 11 })
            .padding({ left: 24, right: 24 })

          // 提示语（居中对齐，对齐 iOS hint：13 号字、次级色、水平 24、顶部 6）
          if (this.showCaption && this.caption.length > 0) {
            Text(this.caption)
              .attributeModifier(CaptionText)
              .fontSize(13)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24, top: 6 })
          }

          // 自定义内容展示区域（调用者自由定义，固定顶部 12 间距）
          Column() {
            this.content()
          }
          .padding({ top: 12 })

          // 按钮行：确定 + 取消（并排一行）
          Row({ space: 12 }) {
            // 确定按钮
            if (this.showConfirm) {
              if (this.confirmOutlined) {
                // 描边样式：品牌色文字 + 品牌色描边 + 卡片底色（对齐 iOS .outlined）
                Button() {
                  this.confirmButtonContent()
                }
                .width('100%')
                .height(AppHeight.Button)
                .borderRadius(AppRadius.Button)
                .backgroundColor(AppColor.BgCard)
                .border({ width: 1, color: AppColor.Brand, radius: AppRadius.Button })
                .layoutWeight(1)
                .enabled(this.confirmEnabled)
                .opacity(this.confirmEnabled ? 1 : 0.5)
                .onClick(() => {
                  this.onConfirm()
                })
              } else {
                // 主色 / 危险样式：渐变填充
                Button() {
                  this.confirmButtonContent()
                }
                .attributeModifier(this.confirmDanger ? DangerButton : PrimaryButton)
                .layoutWeight(1)
                .enabled(this.confirmEnabled)
                .opacity(this.confirmEnabled ? 1 : 0.5)
                .onClick(() => {
                  this.onConfirm()
                })
              }
            }

            // 取消按钮（带描边，对齐 iOS cancel）
            Button(this.cancelText)
              .attributeModifier(CancelButton)
              .layoutWeight(1)
              .border({ width: 1, color: AppColor.BorderInput, radius: AppRadius.Button })
              .onClick(() => {
                this.handleCancel()
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20 })
          .margin({ top: 16, bottom: 40 })
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
