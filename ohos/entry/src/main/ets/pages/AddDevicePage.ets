/**
 * 添加设备页面 —— 对齐 Android AddDeviceActivity
 *
 * 结构：渐变头部 → 滚动区域(扫码区/分隔线/绑定家庭/签名/添加按钮)
 * 说明：Android 版仅「绑定家庭 + 签名」两个表单项（签名即绑定凭证，
 *       ProductId/DeviceName 扫码解析后不展示、不参与 bindDevice）。
 */

import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import { scanBarcode, scanCore } from '@kit.ScanKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { AppState } from '../model/AppModel'
import {
  TXIoTDeviceInfo,
  TXIoTFamilyInfo,
  TXIoTErrorCode
} from '@tencentcloud/liteavsdk_iot'
import {
  AppColor,
  AppRadius,
  AppFontSize,
  PrimaryHeroButton,
  SecondaryText,
  GradientNavBar
} from '../components/AppTheme'
import { CommonBottomSheet } from '../components/CommonBottomSheet'

@Entry
@Component
struct AddDevicePage {
  @State signature: string = ''
  @State isLoading: boolean = false
  // 家庭选择
  @State familyList: TXIoTFamilyInfo[] = []
  @State currentFamilyId: string = ''
  @State currentFamilyName: string = '请选择家庭'
  @State showFamilyPicker: boolean = false

  aboutToAppear() {
    this.loadFamilyList()
  }

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  // 对齐 Android：返回无未保存确认弹窗（其 showUnsavedChangesDialog 为空实现直接 finish）
  goBack() {
    router.back()
  }

  loadFamilyList() {
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      return
    }
    fm.getFamilyList({
      onSuccess: (list: TXIoTFamilyInfo[]) => {
        this.familyList = list
        // 对齐 Android onFamilyListLoaded：优先沿用全局当前家庭（用户在设备列表页选中的家庭），
        // 仅当它不在列表中时兜底第一个家庭；空列表显示提示
        if (list.length > 0) {
          const existing = list.find(f => f.familyId === AppState.currentFamilyId)
          this.selectFamily(existing || list[0])
        } else {
          this.currentFamilyName = '暂无家庭，请先在设备列表创建'
        }
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        // 对齐 Android：拉取家庭列表失败时 toast
        this.showToast(`获取家庭列表失败：${errorMessage}`)
      }
    })
  }

  private dismissFamilyPicker(): void {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showFamilyPicker = false
    })
  }

  selectFamily(family: TXIoTFamilyInfo) {
    this.currentFamilyId = family.familyId
    this.currentFamilyName = family.name || '未命名'
    this.dismissFamilyPicker()
  }

  // 对齐 Android showFamilySelectDialog：家庭列表为空时仅 toast，不弹窗
  private onFamilySelectorClick(): void {
    if (this.familyList.length === 0) {
      this.showToast('暂无家庭，请先在设备列表创建')
      return
    }
    this.showFamilyPicker = true
  }

  // 扫码功能
  async scanQRCode() {
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: false
      }
      const result = await scanBarcode.startScanForResult(getContext(this), options)
      // 对齐 Android handleQRCodeResult：结果非空 → 解析并提示扫描成功；为空 → 提示扫描失败
      if (result && result.originalValue) {
        // 对齐 Android parseQRCodeContent：仅回填签名输入框（ProductId/DeviceName 解析后不展示），
        // 解析异常静默兜底（不复制 Android 的 has("ProductId") 笔误，见 backlog 附录 B）
        try {
          const json = JSON.parse(result.originalValue) as Record<string, string>
          const parsedSignature = json['Signature'] || ''
          if (parsedSignature) {
            this.signature = parsedSignature
          }
        } catch (e) {
          console.error(`AddDevicePage 二维码解析失败: ${e}`)
        }
        this.showToast('二维码扫描成功')
      } else {
        this.showToast('二维码扫描失败')
      }
    } catch (error) {
      const err = error as BusinessError
      if (err.code !== 1000500001) {
        this.showToast('扫码失败：' + err.message)
      }
    }
  }

  async handleAddDevice() {
    // 对齐 Android 校验顺序：先签名（「请扫描二维码」），后家庭（「请先选择家庭」）
    if (!this.signature) {
      this.showToast('请扫描二维码')
      return
    }
    if (!this.currentFamilyId) {
      this.showToast('请先选择家庭')
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('获取设备管理器失败，请重试')
      return
    }

    this.isLoading = true
    dm.bindDevice(this.currentFamilyId, this.signature, {
      onSuccess: (_: TXIoTDeviceInfo) => {
        this.isLoading = false
        // 对齐 Android onBindDeviceSuccess：toast 后 finish，列表由设备列表页 onPageShow 刷新
        this.showToast(`绑定到[${this.currentFamilyName}]成功`)
        router.back()
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoading = false
        this.showToast(errorMessage || '设备绑定失败')
      }
    })
  }

  build() {
    Stack() {
      Column() {
        // ===== 顶部渐变导航栏 =====
        GradientNavBar({
          title: '添加设备', onBack: () => {
            this.goBack()
          }
        })

        // ===== 白色内容区 =====
        Scroll() {
          Column() {
            // 二维码扫描区域
            Column({ space: 14 }) {
              Image($r('app.media.startIcon'))
                .width(48).height(48)
                .fillColor(AppColor.Brand)
                .visibility(Visibility.None)

              // 用文字模拟二维码图标
              Column() {
                Text('📷').fontSize(40)
              }
              .width(72).height(72)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Text('扫描设备二维码')
                .fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
            }
            .width(150)
            .height(150)
            .border({
              width: 2,
              color: AppColor.BorderInput,
              style: BorderStyle.Dashed,
              radius: 16
            })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .alignSelf(ItemAlign.Center)
            .onClick(() => this.scanQRCode())

            // 分隔线
            Row() {
              Column().layoutWeight(1).height(1).backgroundColor(AppColor.BorderInput)
              Text('或手动输入')
                .attributeModifier(SecondaryText).fontSize(13)
                .margin({ left: 14, right: 14 })
              Column().layoutWeight(1).height(1).backgroundColor(AppColor.BorderInput)
            }
            .width('100%')
            .margin({ top: 16, bottom: 16 })

            // 手动输入表单
            Column({ space: 0 }) {
              // 绑定家庭
              Text('绑定家庭')
                .fontSize(13).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
                .margin({ bottom: 8 })

              Row() {
                Column() {
                  Text('🏠').fontSize(14)
                }
                .width(18).height(18)
                .justifyContent(FlexAlign.Center)

                Text(this.currentFamilyName)
                  .fontSize(15)
                  .fontColor(this.currentFamilyId ? AppColor.TextPrimary : AppColor.TextTertiary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: 12 })

                Text('切换')
                  .fontSize(13).fontColor(AppColor.Brand)
              }
              .width('100%')
              .height(52)
              .padding({ left: 16, right: 16 })
              .backgroundColor(AppColor.BgInput)
              .borderRadius(12)
              .margin({ bottom: 16 })
              .onClick(() => {
                this.onFamilySelectorClick()
              })

              // 签名
              Text('签名')
                .fontSize(13).fontWeight(FontWeight.Bold).fontColor(AppColor.TextPrimary)
                .margin({ bottom: 8 })

              Row() {
                Text('🔑').fontSize(14)
                TextInput({ placeholder: '请输入签名', text: this.signature })
                  .layoutWeight(1)
                  .height('100%')
                  .backgroundColor(Color.Transparent)
                  .border({ width: 0 })
                  .fontSize(15)
                  .fontColor(AppColor.TextPrimary)
                  .placeholderColor(AppColor.TextPlaceholder)
                  .maxLength(256)
                  .onChange(val => {
                    this.signature = val
                  })
                  .margin({ left: 12 })
              }
              .width('100%')
              .height(52)
              .padding({ left: 16, right: 16 })
              .backgroundColor(AppColor.BgInput)
              .borderRadius(12)
              .margin({ bottom: 28 })

              // 添加设备按钮（对齐 Android：添加中… / 添加设备）
              Button(this.isLoading ? '添加中…' : '添加设备')
                .attributeModifier(PrimaryHeroButton)
                .enabled(!this.isLoading)
                .onClick((): void => {
                  this.handleAddDevice()
                })
            }
            .alignItems(HorizontalAlign.Start)
          }
          .padding({
            top: 38,
            left: 28,
            right: 28,
            bottom: 22
          })
        }
        .layoutWeight(1)
        .width('100%')
        // 对齐 Android ScrollView(fillViewport) 贴顶；ArkUI Scroll 的 align 默认 Center，需显式指定
        .align(Alignment.Top)
        .backgroundColor(AppColor.BgCard)
      }
      .width('100%').height('100%')
      .backgroundColor(AppColor.BgCard)

      // 家庭选择弹窗（对齐 iOS AddDeviceView.familyPickerSheet: CommonBottomSheet）
      CommonBottomSheet({
        show: $showFamilyPicker,
        title: '🏠 选择家庭',
        caption: `当前：${this.currentFamilyName}`,
        showCaption: true,
        showConfirm: false,
        cancelText: '取消',
        onCancel: () => {
        }
      }) {
        if (this.familyList.length === 0) {
          Text('暂无家庭，请先在设备列表创建')
            .fontSize(16)
            .fontColor(AppColor.TextSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 24, bottom: 24 })
        } else {
          Column() {
            ForEach(this.familyList, (family: TXIoTFamilyInfo) => {
              Row({ space: 14 }) {
                Column() {
                  Text('🏠').fontSize(17)
                }
                .width(40)
                .height(40)
                .borderRadius(20)
                .backgroundColor('#EEF4FF')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Text(family.name || '未命名家庭')
                  .fontSize(15).fontColor(AppColor.TextPrimary).layoutWeight(1).maxLines(1)

                if (family.familyId === this.currentFamilyId) {
                  Text('✓')
                    .fontSize(15)
                    .fontColor(AppColor.Brand)
                    .fontWeight(FontWeight.Normal)
                    .width(24)
                    .height(24)
                    .textAlign(TextAlign.Center)
                }
              }
              .width('100%').height(60)
              .padding({ left: 20, right: 20 })
              .onClick(() => this.selectFamily(family))
            })
          }
          .width('100%')
        }
      }
    }
  }
}
