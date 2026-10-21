import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import pasteboard from '@ohos.pasteboard'
import window from '@ohos.window'
import { AppState, DeviceModel, DeviceSettings } from '../model/AppModel'
import {
  TXIoTUserInfo,
  TXIoTRoomInfo,
  TXIoTFamilyInfo,
  TXIoTDeviceInfo,
  TXIoTFamilyRole,
  TXIoTDeviceId,
  TXIoTErrorCode,
  TXIoTPageResult
} from '@tencentcloud/liteavsdk_iot'
import { VerticalMoreButton, ContextMenuBuilder, ContextMenuItem } from '../components/ContextMenu'
import {
  AppColor,
  AppRadius,
  PrimaryButton,
  DangerButton,
  CancelButton,
  SecondaryButton,
  DangerOutlineButton,
  PageTitleText,
  DialogTitleText,
  SecondaryText,
  SectionTitleText,
  BodyText,
  CaptionText,
  StandardInputField,
  DragHandle,
  MaskOverlay,
  DividerLine,
  GradientNavBar
} from '../components/AppTheme'
import { CommonBottomSheet } from '../components/CommonBottomSheet'
import { ConfirmDialog } from '../components/ConfirmDialog'

// ==================== 家庭管理路由入口（向后兼容：UserProfilePage 等仍以独立页面进入） ====================

@Entry
@Component
struct FamilyManagePage {
  build() {
    Column() {
      FamilyManageView({})
    }
    .width('100%').height('100%')
  }
}

// ==================== 家庭管理视图（独立页面） ====================

@Component
export struct FamilyManageView {
  @State selectedTab: number = 0
  // 家庭列表
  @State familyList: TXIoTFamilyInfo[] = []
  @State currentFamilyId: string = ''
  @State currentFamilyName: string = ''
  // 当前登录用户 ID（用于成员管理 isSelf 判断）
  @State currentUserId: string = ''
  // 设备版本号：每次设备列表加载完成后 +1，传给子组件触发重新渲染
  @State deviceVersion: number = 0
  @State isLoadingFamilies: boolean = false
  // 弹窗状态
  @State showCreateFamilyDialog: boolean = false
  @State showRenameFamilyDialog: boolean = false
  @State showDeleteFamilyDialog: boolean = false
  @State showLeaveFamilyDialog: boolean = false
  @State newFamilyName: string = ''
  @State renameFamilyText: string = ''
  // 状态栏高度（沉浸式标题栏，对齐 Android paddingTop 36dp）
  @StorageProp('statusBarHeight') statusBarHeight: number = 48

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  goBack() {
    router.back()
  }

  // 沉浸式状态栏：透明背景 + 白色图标（对齐 Android setImmersiveStatusBar）
  setupImmersiveStatusBar() {
    const context = getContext(this) as Context
    window.getLastWindow(context, (err, win) => {
      if (err.code) {
        console.error(`❌ setupImmersiveStatusBar error: ${JSON.stringify(err)}`)
        return
      }
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#ffffff'
      })
      win.setWindowLayoutFullScreen(true)
      const avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      const statusBarHeight = avoidArea.topRect.height
      AppStorage.setOrCreate<number>('statusBarHeight', statusBarHeight)
    })
  }

  aboutToAppear() {
    this.setupImmersiveStatusBar()
    const userInfo = AppState.engine().getLoginUserInfo()
    this.currentUserId = (userInfo && userInfo.userId) ? userInfo.userId : ''
    this.currentFamilyId = AppState.currentFamilyId
    this.currentFamilyName = AppState.currentFamilyName || ''
    this.loadFamilyList()
  }

  loadFamilyList() {
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    this.isLoadingFamilies = true
    fm.getFamilyList({
      onSuccess: (list: TXIoTFamilyInfo[]) => {
        this.isLoadingFamilies = false
        this.familyList = list
        // 同步当前家庭名称
        const current = list.find(f => f.familyId === this.currentFamilyId)
        if (current) {
          this.currentFamilyName = current.name || ''
          AppState.currentFamilyName = this.currentFamilyName
        } else if (list.length > 0) {
          this.selectFamily(list[0])
        }
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoadingFamilies = false
        this.showToast(errorMessage || '获取家庭列表失败')
      }
    })
  }

  selectFamily(family: TXIoTFamilyInfo) {
    this.currentFamilyId = family.familyId
    this.currentFamilyName = family.name || ''
    AppState.currentFamilyId = family.familyId
    AppState.currentFamilyName = family.name || ''
    // 切换家庭后重新加载该家庭的设备列表
    // 这样 DeviceSharingPanel / SharedToMePanel 的 @Watch(familyId) 触发时 AppState.devices 已是新家庭数据
    this.reloadDevicesForFamily(family.familyId)
  }

  /**
   * 切换家庭后重新加载设备列表
   * 对应 iOS: DeviceViewModel.getDeviceList(familyId:) 在 onChange(of: deviceViewModel.devices) 触发前更新数据
   */
  reloadDevicesForFamily(familyId: string) {
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      AppState.devices = []
      this.deviceVersion++
      return
    }
    dm.getDeviceList(familyId, '', {
      onSuccess: (result: TXIoTPageResult<TXIoTDeviceInfo>) => {
        const deviceList = result.dataList || []
        const settings: DeviceSettings = {
          motionDetection: true,
          soundAlarm: true,
          nightVision: true
        }
        const devices: DeviceModel[] = deviceList.map((info: TXIoTDeviceInfo): DeviceModel => ({
          id: info.deviceId?.deviceName || '',
          name: info.aliasName || info.deviceId?.deviceName || '',
          location: info.roomId || '',
          online: info.status?.isOnline ?? false,
          signal: '强',
          firmware: '',
          addTime: new Date().toISOString(),
          settings: settings,
          productId: info.deviceId?.productId || '',
          deviceName: info.deviceId?.deviceName || '',
          familyId: info.familyId || '',
          roomId: info.roomId || '',
          iconUrl: info.iconUrl || '',
          isShared: false
        } as DeviceModel))
        AppState.devices = devices
        this.deviceVersion++
        console.info(`✅ 家庭切换后重新加载设备: ${devices.length} 台，版本: ${this.deviceVersion}`)
      },
      onError: (_errorCode: TXIoTErrorCode, _errorMessage: string) => {
        // 加载失败或无设备，也要更新版本号触发子组件刷新（清空旧数据）
        AppState.devices = []
        this.deviceVersion++
      }
    })
  }

  dismissCreateFamilyDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showCreateFamilyDialog = false
    })
  }

  dismissRenameFamilyDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showRenameFamilyDialog = false
    })
  }

  dismissDeleteFamilyDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showDeleteFamilyDialog = false
    })
  }

  dismissLeaveFamilyDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showLeaveFamilyDialog = false
    })
  }

  createFamily() {
    const name = this.newFamilyName.trim()
    if (!name) {
      this.showToast('请输入家庭名称');
      return
    }
    this.dismissCreateFamilyDialog()
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    fm.createFamily(name, {
      onSuccess: (result: TXIoTFamilyInfo) => {
        this.newFamilyName = ''
        this.showToast('家庭创建成功')
        // 对齐 Android：创建成功标记变更并自动选中新家庭
        AppState.familyListChanged = true
        if (result && result.familyId) {
          this.selectFamily(result)
        }
        this.loadFamilyList()
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '创建家庭失败')
      }
    })
  }

  updateFamilyName() {
    const name = this.renameFamilyText.trim()
    if (!name) {
      this.showToast('请输入家庭名称');
      return
    }
    this.dismissRenameFamilyDialog()
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    const newInfo = { familyId: this.currentFamilyId, name: name } as TXIoTFamilyInfo
    fm.updateFamilyInfo(newInfo, {
      onSuccess: (_: void) => {
        this.currentFamilyName = name
        AppState.currentFamilyName = name
        const idx = this.familyList.findIndex(f => f.familyId === this.currentFamilyId)
        if (idx >= 0) {
          this.familyList[idx].name = name
        }
        this.showToast('家庭名称已修改')
        // 对齐 Android：重命名也标记家庭列表变更
        AppState.familyListChanged = true
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '修改失败')
      }
    })
  }

  deleteCurrentFamily() {
    if (!this.currentFamilyId) {
      return
    }
    this.dismissDeleteFamilyDialog()
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    fm.deleteFamily(this.currentFamilyId, {
      onSuccess: (_: void) => {
        this.showToast('家庭已删除')
        // 对齐 Android：标记变更并 finish 退回设备列表页；
        // 由设备列表页重载家庭列表并自动选中下一个家庭（onFamilyListLoaded 兜底第一个）
        AppState.familyListChanged = true
        this.goBack()
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '删除失败')
      }
    })
  }

  /**
   * 退出家庭（对齐 iOS: leaveFamily）
   * 调用 removeMemberFromFamily 移除当前用户自己
   */
  leaveFamily() {
    if (!this.currentFamilyId) {
      return
    }
    const userInfo = AppState.engine().getLoginUserInfo()
    if (!userInfo || !userInfo.userId) {
      this.showToast('未登录或获取用户信息失败')
      return
    }
    this.dismissLeaveFamilyDialog()
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    fm.removeMemberFromFamily(this.currentFamilyId, userInfo.userId, {
      onSuccess: (_: void) => {
        this.showToast('已退出家庭')
        // 对齐 Android leaveFamily：标记家庭列表变更后退回
        AppState.familyListChanged = true
        this.goBack()
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '退出失败')
      }
    })
  }

  /**
   * 家庭管理"⋯"菜单内容（Windows 资源管理器风格）
   * 对齐 iOS: 修改名称 / 新建家庭 / 退出家庭 / 删除家庭
   */
  @Builder
  private familyMenuBuilder() {
    ContextMenuBuilder([
      {
        text: '修改名称',
        icon: '✎',
        onAction: () => {
          this.renameFamilyText = this.currentFamilyName
          this.showRenameFamilyDialog = true
        }
      } as ContextMenuItem,
      {
        text: '新建家庭',
        icon: '＋',
        onAction: () => {
          this.showCreateFamilyDialog = true
        }
      } as ContextMenuItem,
      {
        text: '退出家庭',
        icon: '🚪',
        onAction: () => {
          this.showLeaveFamilyDialog = true
        }
      } as ContextMenuItem,
      { separator: true } as ContextMenuItem,
      {
        text: '删除家庭',
        icon: '🗑',
        color: '#FF4444',
        onAction: () => {
          this.showDeleteFamilyDialog = true
        }
      } as ContextMenuItem,
    ])
  }

  build() {
    Column() {
      // 顶部导航栏
      GradientNavBar({
        title: this.currentFamilyName || '加载中...',
        onBack: () => {
          this.goBack()
        }
      }) {
        VerticalMoreButton({
          btnSize: 44,
          color: AppColor.TextOnPrimary,
          textSize: 22,
        }) {
          this.familyMenuBuilder()
        }
      }

      // Tab 切换（对齐 iOS：4 Tab + 底部指示线）
      Row() {
        Button() {
          Text('成员管理')
            .fontSize(14)
            .fontColor(this.selectedTab === 0 ? AppColor.Brand : AppColor.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.None })
            .padding({ top: 3 })
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor(Color.Transparent)
        .border(
          { width: { bottom: 2 }, color: { bottom: this.selectedTab === 0 ? AppColor.Brand : Color.Transparent } })
        .borderRadius(0)
        .onClick(() => {
          this.selectedTab = 0
        })

        Button() {
          Text('房间管理')
            .fontSize(14)
            .fontColor(this.selectedTab === 1 ? AppColor.Brand : AppColor.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.None })
            .padding({ top: 3 })
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor(Color.Transparent)
        .border(
          { width: { bottom: 2 }, color: { bottom: this.selectedTab === 1 ? AppColor.Brand : Color.Transparent } })
        .borderRadius(0)
        .onClick(() => {
          this.selectedTab = 1
        })

        Button() {
          Text('设备列表')
            .fontSize(14)
            .fontColor(this.selectedTab === 2 ? AppColor.Brand : AppColor.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.None })
            .padding({ top: 3 })
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor(Color.Transparent)
        .border(
          { width: { bottom: 2 }, color: { bottom: this.selectedTab === 2 ? AppColor.Brand : Color.Transparent } })
        .borderRadius(0)
        .onClick(() => {
          this.selectedTab = 2
        })

        Button() {
          Text('分享给我')
            .fontSize(14)
            .fontColor(this.selectedTab === 3 ? AppColor.Brand : AppColor.TextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.None })
            .padding({ top: 3 })
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor(Color.Transparent)
        .border(
          { width: { bottom: 2 }, color: { bottom: this.selectedTab === 3 ? AppColor.Brand : Color.Transparent } })
        .borderRadius(0)
        .onClick(() => {
          this.selectedTab = 3
        })
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .backgroundColor(AppColor.BgCard)
      .border({ width: { bottom: 0.5 }, color: { bottom: '#ECEEF2' } })

      // 内容区
      if (this.selectedTab === 0) {
        FamilyMemberPanel({
          familyId: this.currentFamilyId,
          currentUserId: this.currentUserId,
          onLeaveFamily: () => {
            this.showLeaveFamilyDialog = true
          }
        })
      } else if (this.selectedTab === 1) {
        RoomManagePanel({ familyId: this.currentFamilyId })
      } else if (this.selectedTab === 2) {
        DeviceSharingPanel({ familyId: this.currentFamilyId, deviceVersion: this.deviceVersion })
      } else {
        SharedToMePanel({ familyId: this.currentFamilyId, deviceVersion: this.deviceVersion })
      }

      // ==================== 弹窗区域（统一使用 CommonBottomSheet / ConfirmDialog，对齐 iOS） ====================

      // 新建家庭弹窗（对齐 iOS: CommonBottomSheet title "新建家庭", confirmTitle "创建"）
      CommonBottomSheet({
        show: $showCreateFamilyDialog,
        title: '新建家庭',
        showCaption: false,
        confirmText: '创建',
        cancelText: '取消',
        onConfirm: () => {
          this.createFamily()
        },
        onCancel: () => {
        }
      }) {
        TextInput({ placeholder: '请输入家庭名称', text: this.newFamilyName })
          .attributeModifier(StandardInputField)
          .onChange(val => {
            this.newFamilyName = val
          })
      }

      // 修改家庭名称弹窗（对齐 iOS: CommonBottomSheet title "修改家庭名称", confirmTitle "确定"）
      CommonBottomSheet({
        show: $showRenameFamilyDialog,
        title: '修改家庭名称',
        showCaption: false,
        confirmText: '确定',
        cancelText: '取消',
        onConfirm: () => {
          this.updateFamilyName()
        },
        onCancel: () => {
        }
      }) {
        TextInput({ placeholder: '请输入新名称', text: this.renameFamilyText })
          .attributeModifier(StandardInputField)
          .onChange(val => {
            this.renameFamilyText = val
          })
      }

      // 删除家庭确认弹窗（对齐 iOS: alert "删除家庭"）
      ConfirmDialog({
        show: $showDeleteFamilyDialog,
        title: '删除家庭',
        message: `确定要删除家庭「${this.currentFamilyName}」吗？此操作不可撤销。`,
        confirmText: '删除',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          this.deleteCurrentFamily()
        },
        onCancel: () => {
        }
      })

      // 退出家庭确认弹窗（对齐 iOS: CommonBottomSheet title "退出家庭", confirmStyle .danger）
      ConfirmDialog({
        show: $showLeaveFamilyDialog,
        title: '退出家庭',
        message: '确定要退出当前家庭吗？退出后您将不再是该家庭的成员。',
        confirmText: '退出',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          this.leaveFamily()
        },
        onCancel: () => {
        }
      })
    }
    .width('100%').height('100%')
    .backgroundColor(AppColor.BgPage)
  }
}

// ==================== 房间管理面板 ====================

@Component
struct RoomManagePanel {
  @Prop familyId: string = ''
  @State rooms: TXIoTRoomInfo[] = []
  @State isLoading: boolean = false
  @State showCreateDialog: boolean = false
  @State showRenameDialog: boolean = false
  @State showDeleteDialog: boolean = false
  @State selectedRoom: TXIoTRoomInfo | null = null
  @State newRoomName: string = ''
  @State renameText: string = ''
  // 绑定设备到房间（移入）
  @State showBindDeviceDialog: boolean = false
  @State roomForBinding: TXIoTRoomInfo | null = null
  @State allDevices: DeviceModel[] = []
  @State isLoadingDevices: boolean = false
  // 解绑设备出房间（移出）
  @State showUnbindDeviceSheet: boolean = false
  @State roomForUnbinding: TXIoTRoomInfo | null = null
  @State devicesInRoomForUnbind: DeviceModel[] = []
  // 移出设备确认弹窗
  @State showUnbindDeviceDialog: boolean = false
  @State deviceToUnbind: DeviceModel | null = null

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  aboutToAppear() {
    this.loadRooms()
  }

  loadRooms() {
    if (!this.familyId) {
      return
    }
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    this.isLoading = true
    fm.getRoomList(this.familyId, {
      onSuccess: (roomList: TXIoTRoomInfo[]) => {
        this.isLoading = false
        this.rooms = roomList
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoading = false
        this.showToast(errorMessage || '获取房间列表失败')
      }
    })
  }

  loadAllDevices() {
    if (!this.familyId) {
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    this.isLoadingDevices = true
    dm.getDeviceList(this.familyId, '', {
      onSuccess: (result: TXIoTPageResult<TXIoTDeviceInfo>) => {
        this.isLoadingDevices = false
        // 对齐 Android loadOwnDevices：用接口响应构建列表，而非可能过期的 AppState 缓存
        this.allDevices = this.mapDeviceInfoList(result.dataList || [])
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoadingDevices = false
        this.showToast(errorMessage || '获取设备列表失败')
      }
    })
  }

  /** 用接口响应映射 DeviceModel 列表（对齐 Android deviceList.addAll(pageResult.dataList)） */
  private mapDeviceInfoList(dataList: TXIoTDeviceInfo[]): DeviceModel[] {
    const settings: DeviceSettings = { motionDetection: true, soundAlarm: true, nightVision: true }
    return dataList.map((info: TXIoTDeviceInfo) => {
      return {
        id: info.deviceId?.deviceName || '',
        name: info.aliasName || info.deviceId?.deviceName || '',
        location: info.roomId || '',
        online: info.status?.isOnline ?? false,
        signal: '强',
        firmware: '',
        addTime: '',
        settings: settings,
        productId: info.deviceId?.productId || '',
        deviceName: info.deviceId?.deviceName || '',
        familyId: info.familyId || '',
        roomId: info.roomId || '',
        iconUrl: info.iconUrl || '',
        isShared: false
      } as DeviceModel
    })
  }

  dismissRenameDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showRenameDialog = false
    })
  }

  dismissDeleteDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showDeleteDialog = false
    })
  }

  dismissBindDeviceDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showBindDeviceDialog = false
    })
  }

  dismissUnbindDeviceSheet() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showUnbindDeviceSheet = false
    })
  }

  dismissUnbindDeviceDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showUnbindDeviceDialog = false
    })
  }

  createRoom() {
    const name = this.newRoomName.trim()
    if (!name) {
      this.showToast('请输入房间名称');
      return
    }
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showCreateDialog = false
    })
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    fm.createRoom(this.familyId, name, {
      onSuccess: (_: TXIoTRoomInfo) => {
        this.newRoomName = ''
        this.showToast('房间创建成功')
        this.loadRooms()
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '创建房间失败')
      }
    })
  }

  renameRoom() {
    const name = this.renameText.trim()
    if (!name || !this.selectedRoom) {
      return
    }
    this.dismissRenameDialog()
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    fm.setRoomName(this.familyId, this.selectedRoom.roomId, name, {
      onSuccess: (_: void) => {
        const idx = this.rooms.findIndex(r => r.roomId === this.selectedRoom?.roomId)
        if (idx >= 0) {
          this.rooms[idx].name = name
        }
        this.showToast('房间已重命名')
        this.selectedRoom = null
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '重命名失败')
        this.selectedRoom = null
      }
    })
  }

  deleteRoom() {
    if (!this.selectedRoom) {
      return
    }
    const roomId = this.selectedRoom.roomId
    this.dismissDeleteDialog()
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    fm.deleteRoom(this.familyId, roomId, {
      onSuccess: (_: void) => {
        this.rooms = this.rooms.filter(r => r.roomId !== roomId)
        this.showToast('房间已删除')
        this.selectedRoom = null
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '删除失败')
        this.selectedRoom = null
      }
    })
  }

  bindDeviceToRoom(device: DeviceModel) {
    if (!this.roomForBinding) {
      return
    }
    const roomId = this.roomForBinding.roomId
    const roomName = this.roomForBinding.name || ''
    this.dismissBindDeviceDialog()
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = device.productId || ''
    deviceId.deviceName = device.deviceName || device.id
    dm.addDeviceToRoom(deviceId, this.familyId, roomId, {
      onSuccess: (_: void) => {
        this.showToast(`设备已移入「${roomName}」`)
        this.loadRooms()
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '绑定失败')
      }
    })
  }

  unbindDeviceFromRoom() {
    if (!this.deviceToUnbind) {
      return
    }
    const device = this.deviceToUnbind
    this.dismissUnbindDeviceDialog()
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      this.deviceToUnbind = null
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = device.productId || ''
    deviceId.deviceName = device.deviceName || device.id
    dm.removeDeviceFromRoom(deviceId, this.familyId, {
      onSuccess: (_: void) => {
        this.showToast('设备已移出房间')
        this.loadRooms()
        this.deviceToUnbind = null
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '移出失败')
        this.deviceToUnbind = null
      }
    })
  }

  // 辅助方法：返回已在当前房间的设备（避免在 build() UI 块中使用 const 声明）
  devicesInRoom(): DeviceModel[] {
    return this.allDevices.filter(d => d.roomId === this.roomForBinding?.roomId)
  }

  // 辅助方法：返回不在当前房间的设备
  devicesNotInRoom(): DeviceModel[] {
    return this.allDevices.filter(d => d.roomId !== this.roomForBinding?.roomId)
  }

  /**
   * 加载指定房间中的设备（用于"将设备从房间移出"弹窗）
   * 对齐 iOS: loadDevicesInRoom(room)
   */
  loadDevicesInRoom(room: TXIoTRoomInfo) {
    if (!this.familyId) {
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    this.isLoadingDevices = true
    dm.getDeviceList(this.familyId, '', {
      onSuccess: (result: TXIoTPageResult<TXIoTDeviceInfo>) => {
        this.isLoadingDevices = false
        // 对齐 Android：用接口响应过滤当前房间设备；之前依赖 AppState.devices 缓存，
        // 移入设备后缓存未刷新（roomId 仍为旧值），导致过滤结果为空显示「暂无设备」
        this.devicesInRoomForUnbind = this.mapDeviceInfoList(result.dataList || [])
          .filter(d => d.roomId === room.roomId)
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoadingDevices = false
        this.showToast(errorMessage || '获取设备列表失败')
      }
    })
  }

  /**
   * 选中房间 → 移入设备（对齐 iOS: selectRoomForBind）
   */
  selectRoomForBind(room: TXIoTRoomInfo) {
    this.roomForBinding = room
    this.allDevices = AppState.devices
    this.showBindDeviceDialog = true
  }

  /**
   * 选中房间 → 移出设备（对齐 iOS: selectRoomForUnbind）
   */
  selectRoomForUnbind(room: TXIoTRoomInfo) {
    this.roomForUnbinding = room
    this.loadDevicesInRoom(room)
    this.showUnbindDeviceSheet = true
  }

  /**
   * 房间行 ⋮ 菜单（对齐 iOS: showRoomMorePopup）
   * 重命名房间 / 移入设备到房间 / 将设备从房间移出 / 删除房间
   */
  @Builder
  roomMenuBuilder(room: TXIoTRoomInfo) {
    ContextMenuBuilder([
      {
        text: '重命名房间',
        icon: '✎',
        onAction: () => {
          this.selectedRoom = room
          this.renameText = room.name || ''
          this.showRenameDialog = true
        }
      } as ContextMenuItem,
      {
        text: '移入设备到房间',
        icon: '→',
        onAction: () => {
          this.selectRoomForBind(room)
        }
      } as ContextMenuItem,
      {
        text: '将设备从房间移出',
        icon: '←',
        onAction: () => {
          this.selectRoomForUnbind(room)
        }
      } as ContextMenuItem,
      { separator: true } as ContextMenuItem,
      {
        text: '删除房间',
        icon: '🗑',
        color: '#FF4444',
        onAction: () => {
          this.selectedRoom = room
          this.showDeleteDialog = true
        }
      } as ContextMenuItem,
    ])
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column({ space: 12 }) {
          Text('⏳').fontSize(40)
          Text('加载中...').fontSize(14).fontColor(AppColor.TextSecondary)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.rooms.length === 0) {
        Column({ space: 12 }) {
          Text('🚪').fontSize(60)
          Text('暂无房间').fontSize(16).fontColor(AppColor.TextSecondary)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 房间列表（对齐 iOS: ScrollView + VStack(spacing:10) of individual card rows）
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.rooms, (room: TXIoTRoomInfo) => {
              Row({ space: 12 }) {
                // 图标圈：#EEF4FF 44dp（对齐 iOS Circle 44x44）
                Stack() {
                  Text('🚪').fontSize(20)
                }
                .width(44).height(44).borderRadius(22)
                .backgroundColor('#EEF4FF')

                // 信息
                Column({ space: 4 }) {
                  Text(room.name || '未命名房间')
                    .fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
                  Text(`${room.deviceCount} 台设备`)
                    .fontSize(12).fontColor(AppColor.TextSecondary)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                // ⋮ 菜单按钮（重命名 / 移入设备 / 移出设备 / 删除，对齐 iOS RoomRowView Menu）
                VerticalMoreButton({
                  btnSize: 32,
                  color: AppColor.TextSecondary,
                  textSize: 18,
                }) {
                  this.roomMenuBuilder(room)
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(AppColor.BgCard)
              .borderRadius(12)
              .border({ width: 1, color: '#E8EAF0' })
            })
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 12
          })
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }

      // 新建房间按钮（对齐 iOS: 底部主按钮，全宽 44dp 高）
      Row() {
        Button() {
          Row({ space: 8 }) {
            Text('＋').fontSize(16).fontColor('#FFFFFF')
            Text('新建房间').fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Normal)
          }
        }
        .attributeModifier(PrimaryButton)
        .layoutWeight(1).height(44)
        .onClick(() => {
          this.showCreateDialog = true
        })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 22
      })

      // 新建房间弹窗（对齐 iOS: CommonBottomSheet title "🚪 新建房间", confirmTitle "创建"）
      CommonBottomSheet({
        show: $showCreateDialog,
        title: '🚪 新建房间',
        showCaption: false,
        confirmText: '创建',
        cancelText: '取消',
        onConfirm: () => {
          this.createRoom()
        },
        onCancel: () => {
        }
      }) {
        Column({ space: 4 }) {
          Text('请输入房间名称')
            .fontSize(13).fontColor('#6A6E78')
            .width('100%')
          TextInput({ placeholder: '请输入房间名称', text: this.newRoomName })
            .attributeModifier(StandardInputField)
            .onChange(val => {
              this.newRoomName = val
            })
        }
        .width('100%').padding({ left: 20, right: 20 })
      }

      // 重命名弹窗（对齐 iOS: CommonBottomSheet title "重命名房间", confirmTitle "确定"）
      CommonBottomSheet({
        show: $showRenameDialog,
        title: '重命名房间',
        showCaption: false,
        confirmText: '确定',
        cancelText: '取消',
        onConfirm: () => {
          this.renameRoom()
        },
        onCancel: () => {
          this.selectedRoom = null
        }
      }) {
        Column({ space: 4 }) {
          Text('请输入新名称')
            .fontSize(13).fontColor('#6A6E78')
            .width('100%')
          TextInput({ placeholder: '请输入新名称', text: this.renameText })
            .attributeModifier(StandardInputField)
            .onChange(val => {
              this.renameText = val
            })
        }
        .width('100%').padding({ left: 20, right: 20 })
      }

      // 删除确认弹窗（对齐 iOS: CommonBottomSheet title "删除房间", confirmTitle "删除", confirmStyle .danger）
      ConfirmDialog({
        show: $showDeleteDialog,
        title: '删除房间',
        message: `确定要删除房间「${this.selectedRoom?.name || ''}」吗？`,
        confirmText: '删除',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          this.deleteRoom()
        },
        onCancel: () => {
          this.selectedRoom = null
        }
      })

      // 移入设备弹窗（对齐 iOS: bindDeviceSheet — 仅展示不在当前房间的设备）
      CommonBottomSheet({
        show: $showBindDeviceDialog,
        title: '移入设备到房间',
        caption: this.roomForBinding?.name || '',
        showCaption: true,
        showConfirm: false,
        cancelText: '取消',
        onCancel: () => {
        }
      }) {
        if (this.devicesNotInRoom().length === 0) {
          Column({ space: 12 }) {
            Text('📹').fontSize(50)
            Text('暂无设备可移入').fontSize(15).fontColor(AppColor.TextSecondary)
          }
          .width('100%').padding({ top: 24, bottom: 24 })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.devicesNotInRoom(), (device: DeviceModel) => {
              ListItem() {
                Row({ space: 12 }) {
                  Stack() {
                    Text('📹').fontSize(18)
                  }
                  .width(44).height(44).borderRadius(22)
                  .backgroundColor('#EEF4FF')

                  Column({ space: 4 }) {
                    Text(device.name).fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
                    Text(device.roomId ? '其他房间' : '未分配房间')
                      .fontSize(12).fontColor(AppColor.TextSecondary)
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)

                  Button('移入')
                    .height(32)
                    .fontSize(13)
                    .fontColor('#006EFF')
                    .fontWeight(FontWeight.Normal)
                    .backgroundColor(Color.Transparent)
                    .border({ width: 1.5, color: '#006EFF', radius: 6 })
                    .padding({ left: 12, right: 12 })
                    .onClick(() => this.bindDeviceToRoom(device))
                }
                .width('100%').height(56)
                .padding({ left: 4, right: 4 })
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .constraintSize({ maxHeight: 360 })
        }
      }

      // 移出设备弹窗（对齐 iOS: unbindDeviceSheet — 仅展示当前房间内的设备）
      CommonBottomSheet({
        show: $showUnbindDeviceSheet,
        title: '将设备从房间移出',
        caption: this.roomForUnbinding?.name || '',
        showCaption: true,
        showConfirm: false,
        cancelText: '取消',
        onCancel: () => {
        }
      }) {
        if (this.isLoadingDevices) {
          Column({ space: 12 }) {
            Text('⏳').fontSize(40)
            Text('加载设备列表...').fontSize(14).fontColor(AppColor.TextSecondary)
          }
          .width('100%').padding({ top: 24, bottom: 24 })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.devicesInRoomForUnbind.length === 0) {
          Column({ space: 12 }) {
            Text('📹').fontSize(50)
            Text(this.roomForUnbinding ? `「${this.roomForUnbinding.name || ''}」暂无设备` : '暂无设备')
              .fontSize(15).fontColor(AppColor.TextSecondary)
          }
          .width('100%').padding({ top: 24, bottom: 24 })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.devicesInRoomForUnbind, (device: DeviceModel) => {
              ListItem() {
                Row({ space: 12 }) {
                  Stack() {
                    Text('📹').fontSize(18)
                  }
                  .width(44).height(44).borderRadius(22)
                  .backgroundColor('#EEF4FF')

                  Column({ space: 4 }) {
                    Text(device.name).fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
                    Text('当前房间').fontSize(12).fontColor('#52c41a')
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)

                  Button('移出')
                    .height(32)
                    .fontSize(13)
                    .fontColor('#FF4444')
                    .fontWeight(FontWeight.Normal)
                    .backgroundColor(Color.Transparent)
                    .border({ width: 1.5, color: '#FF4444', radius: 6 })
                    .padding({ left: 12, right: 12 })
                    .onClick(() => {
                      this.deviceToUnbind = device
                      this.dismissUnbindDeviceSheet()
                      this.showUnbindDeviceDialog = true
                    })
                }
                .width('100%').height(56)
                .padding({ left: 4, right: 4 })
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .constraintSize({ maxHeight: 360 })
        }
      }

      // 移出房间确认弹窗（对齐 iOS: CommonBottomSheet title "将设备从房间移出", confirmTitle nil）
      ConfirmDialog({
        show: $showUnbindDeviceDialog,
        title: '将设备从房间移出',
        message: `确定要将设备「${this.deviceToUnbind?.name || ''}」移出房间吗？移出后设备将不属于任何房间。`,
        confirmText: '移出',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          this.unbindDeviceFromRoom()
        },
        onCancel: () => {
          this.deviceToUnbind = null
        }
      })
    }
    .width('100%').layoutWeight(1)
  }
}

// ==================== 成员管理面板 ====================
// 对齐 iOS: FamilyMemberView + MemberRowView
// - 自己显示"退出"按钮（触发 onLeaveFamily 回调），他人显示"删除"按钮
// - 主标题显示 userId，副标题显示"昵称: nickName"（对齐 iOS MemberRowView）

@Component
struct FamilyMemberPanel {
  @Prop familyId: string = ''
  @Prop currentUserId: string = ''
  onLeaveFamily: () => void = () => {
  }
  @State members: TXIoTUserInfo[] = []
  @State isLoading: boolean = false
  // 创建邀请 Token（对应 iOS: createFamilyInviteToken）
  @State showInviteTokenDialog: boolean = false
  @State inviteTokenJson: string = ''
  // 加入家庭（对应 iOS: joinFamilyAsMember）
  @State showJoinFamilyDialog: boolean = false
  @State joinToken: string = ''
  // 移除成员（对应 iOS: removeMemberFromFamily）
  @State showDeleteDialog: boolean = false
  @State memberToDelete: TXIoTUserInfo | null = null

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  aboutToAppear() {
    this.loadMembers()
  }

  loadMembers() {
    if (!this.familyId) {
      this.showToast('未找到家庭信息')
      return
    }
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    this.isLoading = true
    fm.getMemberList(this.familyId, {
      onSuccess: (members: TXIoTUserInfo[]) => {
        this.isLoading = false
        this.members = members
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoading = false
        this.showToast(errorMessage || '获取成员列表失败')
      }
    })
  }

  dismissMemberDeleteDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showDeleteDialog = false
    })
  }

  /**
   * 判断成员是否为当前登录用户自己（对齐 iOS: MemberRowView.isSelf）
   */
  isSelf(member: TXIoTUserInfo): boolean {
    return this.currentUserId.length > 0 && member.userId === this.currentUserId
  }

  /**
   * 创建家庭邀请 Token
   * 对应 iOS: family.createFamilyInviteToken { token, errorCode, errorMessage in ... }
   */
  createInviteToken() {
    if (!this.familyId) {
      this.showToast('未找到家庭信息')
      return
    }
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    fm.createFamilyInviteToken(this.familyId, {
      onSuccess: (token: string) => {
        this.inviteTokenJson = token
        this.showInviteTokenDialog = true
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '创建邀请 Token 失败')
      }
    })
  }

  /**
   * 通过邀请 Token 加入家庭
   * 对应 iOS: family.joinFamilyAsMember(inviteToken) { errorCode, errorMessage in ... }
   */
  joinFamily() {
    const token = this.joinToken.trim()
    if (!token) {
      this.showToast('请输入有效的邀请 Token')
      return
    }
    if (!this.familyId) {
      this.showToast('未找到家庭信息')
      return
    }
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showJoinFamilyDialog = false
    })
    fm.joinFamilyAsMember(token, {
      onSuccess: (_: void) => {
        this.showToast('已成功加入家庭')
        this.joinToken = ''
        // 对齐 Android joinFamily 成功后 finishWithResult：标记家庭列表变更，
        // 设备列表页 onPageShow 检测后会重载家庭列表，切换弹窗即可看到新加入的家庭
        AppState.familyListChanged = true
        this.loadMembers()
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '加入失败')
      }
    })
  }

  /**
   * 移除家庭成员
   * 对应 iOS: family.removeMemberFromFamily(userId) { errorCode, errorMessage in ... }
   */
  removeMember(member: TXIoTUserInfo) {
    if (!this.familyId) {
      return
    }
    const fm = AppState.engine().getFamilyManager()
    if (!fm) {
      this.showToast('家庭管理器未初始化')
      return
    }
    fm.removeMemberFromFamily(this.familyId, member.userId, {
      onSuccess: (_: void) => {
        this.showToast('已移除成员')
        this.members = this.members.filter(m => m.userId !== member.userId)
        this.dismissMemberDeleteDialog()
        this.memberToDelete = null
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '移除失败')
        this.dismissMemberDeleteDialog()
        this.memberToDelete = null
      }
    })
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column({ space: 12 }) {
          Text('⏳').fontSize(40)
          Text('加载中...').fontSize(14).fontColor(AppColor.TextSecondary)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.members.length === 0) {
        Column({ space: 12 }) {
          Text('👥').fontSize(60)
          Text('暂无家庭成员').fontSize(16).fontColor(AppColor.TextSecondary)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 成员列表（对齐 iOS: ScrollView + VStack(spacing:10) of individual card rows）
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.members, (member: TXIoTUserInfo) => {
              Row({ space: 12 }) {
                // 头像圆形背景（对齐 iOS: 44x44 Circle, isSelf=warning 色, 他人=品牌色）
                Stack() {
                  Text(member.userId ? member.userId.substring(0, 1) : '?')
                    .fontSize(18).fontWeight(FontWeight.Normal)
                    .fontColor(this.isSelf(member) ? '#fa8c16' : '#006EFF')
                }
                .width(44).height(44).borderRadius(22)
                .backgroundColor(this.isSelf(member) ? '#FFF3E8' : '#EEF4FF')

                // 信息（对齐 iOS: 主标题 userId, 副标题"昵称: nickName"）
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(member.userId)
                      .fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
                    if (member.role === TXIoTFamilyRole.ADMIN) {
                      Text('管理员')
                        .fontSize(11)
                        .fontColor('#FFFFFF')
                        .padding({
                          left: 6,
                          right: 6,
                          top: 2,
                          bottom: 2
                        })
                        .backgroundColor('#006EFF')
                        .borderRadius(4)
                    }
                    if (this.isSelf(member)) {
                      Text('我')
                        .fontSize(11)
                        .fontColor('#FFFFFF')
                        .padding({
                          left: 6,
                          right: 6,
                          top: 2,
                          bottom: 2
                        })
                        .backgroundColor('#fa8c16')
                        .borderRadius(4)
                    }
                  }

                  Text('昵称: ' + (member.nickName || ''))
                    .fontSize(12).fontColor(AppColor.TextSecondary)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                // 操作按钮（对齐 iOS: 自己=退出, 他人=删除, .sheetBorder cornerRadius:6）
                if (this.isSelf(member)) {
                  Button('退出')
                    .height(32)
                    .fontSize(13)
                    .fontColor('#FF4444')
                    .fontWeight(FontWeight.Normal)
                    .backgroundColor(Color.Transparent)
                    .border({ width: 1.5, color: '#FF4444', radius: 6 })
                    .padding({ left: 12, right: 12 })
                    .onClick(() => {
                      this.onLeaveFamily()
                    })
                } else {
                  Button('删除')
                    .height(32)
                    .fontSize(13)
                    .fontColor('#FF4444')
                    .fontWeight(FontWeight.Normal)
                    .backgroundColor(Color.Transparent)
                    .border({ width: 1.5, color: '#FF4444', radius: 6 })
                    .padding({ left: 12, right: 12 })
                    .onClick(() => {
                      this.memberToDelete = member
                      this.showDeleteDialog = true
                    })
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(AppColor.BgCard)
              .borderRadius(12)
              .border({ width: 1, color: '#E8EAF0' })
            })
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 12
          })
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }

      // 操作按钮区（对齐 iOS: 底部 创建邀请 + 加入家庭）
      Row({ space: 12 }) {
        // 创建邀请按钮（主按钮）
        Button() {
          Row({ space: 8 }) {
            Text('👤＋').fontSize(16).fontColor('#FFFFFF')
            Text('创建邀请').fontSize(15).fontColor('#FFFFFF').fontWeight(FontWeight.Normal)
          }
        }
        .attributeModifier(PrimaryButton)
        .layoutWeight(1).height(44)
        .onClick(() => {
          this.createInviteToken()
        })

        // 加入家庭按钮（描边按钮）
        Button() {
          Row({ space: 8 }) {
            Text('🔑').fontSize(16)
            Text('加入家庭').fontSize(15).fontColor('#006EFF').fontWeight(FontWeight.Normal)
          }
        }
        .attributeModifier(SecondaryButton)
        .layoutWeight(1).height(44)
        .onClick(() => {
          this.showJoinFamilyDialog = true
        })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 22
      })

      // 邀请 Token 展示弹窗（对齐 iOS: CommonBottomSheet title "🔑 家庭邀请码", confirmTitle "📋 复制"）
      CommonBottomSheet({
        show: $showInviteTokenDialog,
        title: '🔑 家庭邀请码',
        showCaption: false,
        confirmText: '📋 复制',
        cancelText: '取消',
        onConfirm: () => {
          const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.inviteTokenJson)
          const systemPasteboard = pasteboard.getSystemPasteboard()
          systemPasteboard.setDataSync(pasteboardData)
          this.showToast('已复制到剪贴板')
        },
        onCancel: () => {
          this.inviteTokenJson = ''
        }
      }) {
        Column() {
          Text(this.inviteTokenJson)
            .fontSize(15)
            .fontWeight(FontWeight.Normal)
            .fontColor(AppColor.TextPrimary)
            .fontFamily('monospace')
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .backgroundColor('#F7F8FA')
            .borderRadius(8)
            .border({ width: 1, color: AppColor.BorderInput, radius: 8 })
            .textAlign(TextAlign.Start)
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%').padding({ left: 20, right: 20 })
      }

      // 加入家庭弹窗（对齐 iOS: CommonBottomSheet title "🔗 加入家庭", confirmTitle "确定"）
      CommonBottomSheet({
        show: $showJoinFamilyDialog,
        title: '🔗 加入家庭',
        showCaption: false,
        confirmText: '确定',
        cancelText: '取消',
        onConfirm: () => {
          this.joinFamily()
        },
        onCancel: () => {
          this.joinToken = ''
        }
      }) {
        Column({ space: 4 }) {
          Text('请输入邀请码')
            .fontSize(13).fontColor('#6A6E78')
            .width('100%')
          TextInput({ placeholder: '请输入邀请码', text: this.joinToken })
            .attributeModifier(StandardInputField)
            .onChange(val => {
              this.joinToken = val
            })
        }
        .width('100%').padding({ left: 20, right: 20 })
      }

      // 删除成员确认弹窗（对齐 iOS: CommonBottomSheet title "删除成员", confirmTitle "删除", confirmStyle .danger）
      ConfirmDialog({
        show: $showDeleteDialog,
        title: '删除成员',
        message: `确定要将 "${this.memberToDelete?.userId || ''}" 从家庭中移除吗？`,
        confirmText: '删除',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          if (this.memberToDelete) {
            this.removeMember(this.memberToDelete)
          }
        },
        onCancel: () => {
          this.memberToDelete = null
        }
      })
    }
    .width('100%').layoutWeight(1)
  }
}

// ==================== 设备列表面板（管理自己设备的分享） ====================
// 对齐 iOS: DeviceSharingView
// - 展示自有设备列表（过滤掉分享设备）
// - 每个设备行带 ⋮ 菜单：创建分享 / 已分享用户
// - sharedUserCounts 显示每个设备已分享的用户数

@Component
struct DeviceSharingPanel {
  @Prop familyId: string = ''
  @Prop @Watch('onDeviceVersionChange') deviceVersion: number = 0
  @State devices: DeviceModel[] = []
  @State selectedDeviceId: string = ''
  @State sharedUsers: TXIoTUserInfo[] = []
  @State isLoadingUsers: boolean = false
  // 分享用户数缓存（key: deviceKey(device)）
  // 必须是 @State 且更新时整体重建：build 中通过 getSharedUserCount 读取它建立依赖，
  // SDK 回调赋值后 Text 才会自动刷新（对齐 Android 回调直接更新 TextView 的效果）
  @State sharedUserCounts: Map<string, number> = new Map()
  // 移除单个分享用户确认弹窗
  @State showRemoveUserDialog: boolean = false
  @State userToRemove: TXIoTUserInfo | null = null
  // 已分享用户列表弹窗
  @State showSharedUsersDialog: boolean = false
  // 创建分享 Token 弹窗（对应 iOS: ShareTokenSheet）
  @State showShareTokenDialog: boolean = false
  @State shareTokenJson: string = ''

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  dismissRemoveUserDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showRemoveUserDialog = false
    })
  }

  dismissSharedUsersDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showSharedUsersDialog = false
    })
  }

  /**
   * 加载设备列表（仅自有设备，对齐 iOS: deviceViewModel.devices.filter { !$0.isShared }）
   * 对应 iOS: DeviceSharingView.onAppear -> deviceViewModel.devices
   */
  aboutToAppear() {
    this.reloadDevices()
  }

  /**
   * 重新加载设备列表（家庭切换时也会调用）
   */
  reloadDevices() {
    // 仅展示自有设备（过滤掉分享设备）
    this.devices = AppState.devices.filter(d => !d.isShared)
    this.selectedDeviceId = ''
    this.sharedUsers = []
    // 加载所有设备的分享用户数
    this.loadAllSharedUserCounts()
  }

  /**
   * 监听 deviceVersion 变化，家庭切换设备加载完成后触发刷新
   */
  onDeviceVersionChange() {
    this.reloadDevices()
  }

  getFamilyId(): string {
    return this.familyId || AppState.currentFamilyId
  }

  deviceKey(device: DeviceModel): string {
    return `${device.productId || ''}/${device.deviceName || device.id}`
  }

  findSelectedDevice(): DeviceModel | null {
    return this.devices.find(d => this.deviceKey(d) === this.selectedDeviceId) || null
  }

  /**
   * 加载所有自有设备的分享用户数（对齐 iOS: loadAllSharedUserCounts）
   */
  loadAllSharedUserCounts() {
    const fid = this.getFamilyId()
    if (!fid || this.devices.length === 0) {
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      return
    }
    for (const device of this.devices) {
      const pid = device.productId || ''
      const dn = device.deviceName || device.id
      if (!pid || !dn) {
        continue
      }
      const deviceId = new TXIoTDeviceId()
      deviceId.productId = pid
      deviceId.deviceName = dn
      dm.getDeviceSharedUsers(deviceId, {
        onSuccess: (users: TXIoTUserInfo[]) => {
          this.updateSharedUserCount(this.deviceKey(device), users.length)
        },
        onError: (_errorCode: TXIoTErrorCode, _errorMessage: string) => {
        }
      })
    }
  }

  updateSharedUserCount(key: string, count: number) {
    // 不可变重建以触发 @State 观察（直接 set 不保证跨 API 版本可观察）
    const next = new Map(this.sharedUserCounts)
    next.set(key, count)
    this.sharedUserCounts = next
  }

  getSharedUserCount(key: string): number {
    return this.sharedUserCounts.get(key) || 0
  }

  /**
   * 加载指定设备的分享用户列表（对齐 iOS: loadSharedUsers(for:)）
   */
  loadSharedUsers(device: DeviceModel, onComplete?: () => void) {
    const fid = this.getFamilyId()
    const pid = device.productId || ''
    const dn = device.deviceName || device.id
    if (!fid || !pid || !dn) {
      if (onComplete) {
        onComplete()
      }
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      if (onComplete) {
        onComplete()
      }
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = pid
    deviceId.deviceName = dn
    this.isLoadingUsers = true
    dm.getDeviceSharedUsers(deviceId, {
      onSuccess: (users: TXIoTUserInfo[]) => {
        this.isLoadingUsers = false
        this.sharedUsers = users
        if (onComplete) {
          onComplete()
        }
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.isLoadingUsers = false
        this.showToast(errorMessage || '获取分享用户失败')
        if (onComplete) {
          onComplete()
        }
      }
    })
  }

  /**
   * 创建设备分享 Token（对齐 iOS: createShareToken()）
   */
  createShareToken(device: DeviceModel) {
    const fid = this.getFamilyId()
    const pid = device.productId || ''
    const dn = device.deviceName || device.id
    if (!fid || !pid || !dn) {
      this.showToast('未找到家庭或设备信息')
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = pid
    deviceId.deviceName = dn
    dm.createDeviceSharingToken(fid, deviceId, {
      onSuccess: (token: string) => {
        const payload: Record<string, string> = {
          'productId': pid,
          'deviceName': dn,
          'token': token
        }
        this.shareTokenJson = JSON.stringify(payload, null, 2)
        this.showShareTokenDialog = true
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '创建分享 Token 失败')
      }
    })
  }

  /**
   * 移除单个分享用户（对齐 iOS: removeSharedUser(_:from:)）
   */
  removeSharedUser(user: TXIoTUserInfo) {
    const device = this.findSelectedDevice()
    if (!device) {
      return
    }
    const pid = device.productId || ''
    const dn = device.deviceName || device.id
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = pid
    deviceId.deviceName = dn
    dm.removeDeviceSharedUser(deviceId, user.userId, {
      onSuccess: (_: void) => {
        this.showToast('已移除分享用户')
        this.sharedUsers = this.sharedUsers.filter(u => u.userId !== user.userId)
        this.updateSharedUserCount(this.deviceKey(device), this.sharedUsers.length)
        this.dismissRemoveUserDialog()
        this.userToRemove = null
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '移除失败')
        this.dismissRemoveUserDialog()
        this.userToRemove = null
      }
    })
  }

  // ---- 菜单动作 ----

  onMenuCreateShare(device: DeviceModel) {
    this.selectedDeviceId = this.deviceKey(device)
    this.createShareToken(device)
  }

  onMenuShowSharedUsers(device: DeviceModel) {
    this.selectedDeviceId = this.deviceKey(device)
    this.sharedUsers = []
    this.loadSharedUsers(device, () => {
      this.showSharedUsersDialog = true
    })
  }

  @Builder
  deviceMenuBuilder(device: DeviceModel) {
    ContextMenuBuilder([
      {
        text: '创建分享',
        icon: '↗',
        onAction: () => {
          this.onMenuCreateShare(device)
        }
      } as ContextMenuItem,
      {
        text: '已分享用户',
        icon: '👥',
        onAction: () => {
          this.onMenuShowSharedUsers(device)
        }
      } as ContextMenuItem,
    ])
  }

  build() {
    Column() {
      if (this.devices.length === 0) {
        // 无设备空状态（对齐 iOS: emptyStateView）
        Column({ space: 12 }) {
          Text('📷').fontSize(40)
          Text('暂无设备').fontSize(14).fontColor(AppColor.TextSecondary)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 设备列表（对齐 iOS: deviceListView → ScrollView + VStack of device rows）
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.devices, (device: DeviceModel) => {
              Row({ space: 12 }) {
                // 设备图标圈
                Stack() {
                  Text('📹').fontSize(18)
                }
                .width(44).height(44).borderRadius(22)
                .backgroundColor('#EEF4FF')

                // 设备信息
                Column({ space: 4 }) {
                  Text(device.name)
                    .fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
                  Text(`${this.getSharedUserCount(this.deviceKey(device))} 位用户`)
                    .fontSize(12).fontColor(AppColor.TextSecondary)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                // ⋮ 菜单按钮（创建分享 / 已分享用户）
                VerticalMoreButton({
                  btnSize: 32,
                  color: AppColor.TextSecondary,
                  textSize: 18,
                }) {
                  this.deviceMenuBuilder(device)
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(AppColor.BgCard)
              .borderRadius(12)
              .border({ width: 1, color: '#E8EAF0' })
            })
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 12
          })
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }

      // ==================== 弹窗区域 ====================

      // 移除分享用户确认弹窗（对齐 iOS: alert "移除分享用户"）
      ConfirmDialog({
        show: $showRemoveUserDialog,
        title: '移除分享用户',
        message: `确定要移除用户 "${this.userToRemove?.userId || ''}" 的分享权限吗？`,
        confirmText: '移除',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          if (this.userToRemove) {
            this.removeSharedUser(this.userToRemove)
          }
        },
        onCancel: () => {
          this.userToRemove = null
        }
      })

      // 已分享用户列表弹窗（对齐 iOS: sharedUsersSheet）
      CommonBottomSheet({
        show: $showSharedUsersDialog,
        title: '已分享用户',
        caption: this.findSelectedDevice()?.name || '',
        showCaption: true,
        showConfirm: false,
        cancelText: '取消',
        onCancel: () => {
        }
      }) {
        if (this.isLoadingUsers) {
          Column({ space: 12 }) {
            Text('⏳').fontSize(40)
            Text('加载中...').fontSize(14).fontColor(AppColor.TextSecondary)
          }
          .width('100%').padding({ top: 24, bottom: 24 })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.sharedUsers.length === 0) {
          Column({ space: 12 }) {
            Text('😶').fontSize(32)
            Text('暂无分享用户').attributeModifier(CaptionText)
          }
          .width('100%').padding({ top: 24, bottom: 24 })
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.sharedUsers, (user: TXIoTUserInfo, index: number) => {
              ListItem() {
                Column() {
                  Row({ space: 12 }) {
                    // 头像圈
                    Stack() {
                      Text(user.userId ? user.userId.substring(0, 1) : '?')
                        .fontSize(17).fontWeight(FontWeight.Normal).fontColor('#006EFF')
                    }
                    .width(40).height(40).borderRadius(20)
                    .backgroundColor('#EEF4FF')

                    Column({ space: 2 }) {
                      Text(user.userId)
                        .fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
                      Text('ID: ' + user.userId)
                        .attributeModifier(CaptionText)
                    }
                    .layoutWeight(1).alignItems(HorizontalAlign.Start)

                    // 移除按钮
                    Text('移除')
                      .fontSize(13)
                      .fontColor('#FF4D4F')
                      .padding({
                        left: 12,
                        right: 12,
                        top: 6,
                        bottom: 6
                      })
                      .backgroundColor('#FFF1F0')
                      .borderRadius(6)
                      .border({ width: 1, color: '#FFCCC7' })
                      .onClick(() => {
                        this.userToRemove = user
                        // 对齐 Android：点「移除」先关闭已分享用户列表弹窗（sheet.dismiss()），
                        // 再弹确认框，避免两个同层级弹窗堆叠导致确认框被压在下方不可见
                        this.dismissSharedUsersDialog()
                        this.showRemoveUserDialog = true
                      })
                  }
                  .width('100%').height(56)
                  .padding({ left: 4, right: 4 })

                  if (index < this.sharedUsers.length - 1) {
                    Column().width('100%').height(0.5).backgroundColor('#ECEEF2')
                      .margin({ left: 52 })
                  }
                }
                .width('100%')
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .constraintSize({ maxHeight: 360 })
        }
      }

      // 创建分享 Token 弹窗（对齐 iOS: shareTokenSheet）
      CommonBottomSheet({
        show: $showShareTokenDialog,
        title: '🔑 设备分享码',
        showCaption: false,
        confirmText: '📋 复制分享码',
        cancelText: '取消',
        onConfirm: () => {
          const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareTokenJson)
          const systemPasteboard = pasteboard.getSystemPasteboard()
          systemPasteboard.setDataSync(pasteboardData)
          this.showToast('已复制到剪贴板')
        },
        onCancel: () => {
          this.shareTokenJson = ''
        }
      }) {
        Column() {
          Scroll() {
            Text(this.shareTokenJson)
              .fontSize(13)
              .fontColor(AppColor.TextPrimary)
              .fontFamily('monospace')
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({
                left: 12,
                right: 12,
                top: 10,
                bottom: 10
              })
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .height(132)
          .backgroundColor('#F7F8FA')
          .borderRadius(8)
          .border({ width: 1, color: AppColor.BorderInput, radius: 8 })
        }
        .width('100%').padding({ left: 20, right: 20 })
      }
    }
    .width('100%').layoutWeight(1)
  }
}

// ==================== 分享给我面板（管理别人分享给我的设备） ====================
// 对齐 iOS: SharedToMeView
// - 展示分享给我的设备列表
// - 每个设备行带"解除绑定"按钮
// - 底部"绑定分享"按钮

@Component
struct SharedToMePanel {
  @Prop familyId: string = ''
  @Prop @Watch('onDeviceVersionChange') deviceVersion: number = 0
  @State sharedToMeDevices: DeviceModel[] = []
  @State isLoading: boolean = false
  // 解除绑定确认弹窗
  @State showUnbindDialog: boolean = false
  @State deviceToUnbind: DeviceModel | null = null
  // 绑定分享设备弹窗
  @State showBindShareDialog: boolean = false
  @State bindShareJson: string = ''

  showToast(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  dismissUnbindDialog() {
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.showUnbindDialog = false
    })
  }

  aboutToAppear() {
    this.loadSharedToMeDevices()
  }

  /**
   * 监听 deviceVersion 变化，家庭切换后触发刷新
   */
  onDeviceVersionChange() {
    this.loadSharedToMeDevices()
  }

  getFamilyId(): string {
    return this.familyId || AppState.currentFamilyId
  }

  /**
   * 加载分享给我的设备列表（对齐 iOS: loadSharedToMeDevices）
   */
  loadSharedToMeDevices() {
    const fid = this.getFamilyId()
    if (!fid) {
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      return
    }
    this.isLoading = true
    dm.getDeviceListSharedWithMe('', {
      onSuccess: (result: TXIoTPageResult<TXIoTDeviceInfo>) => {
        this.isLoading = false
        const deviceList = result.dataList || []
        const settings: DeviceSettings = {
          motionDetection: true,
          soundAlarm: true,
          nightVision: true
        }
        const devices: DeviceModel[] = deviceList.map((info: TXIoTDeviceInfo): DeviceModel => ({
          id: info.deviceId?.deviceName || '',
          name: info.aliasName || info.deviceId?.deviceName || '',
          location: info.roomId || '',
          online: info.status?.isOnline ?? false,
          signal: '强',
          firmware: '',
          addTime: new Date().toISOString(),
          settings: settings,
          productId: info.deviceId?.productId || '',
          deviceName: info.deviceId?.deviceName || '',
          familyId: info.familyId || '',
          roomId: info.roomId || '',
          iconUrl: info.iconUrl || '',
          isShared: true
        } as DeviceModel))
        this.sharedToMeDevices = devices
        console.info(`✅ 分享给我的设备: ${devices.length} 台`)
      },
      onError: (_errorCode: TXIoTErrorCode, _errorMessage: string) => {
        this.isLoading = false
        // 加载失败，清空列表
        this.sharedToMeDevices = []
      }
    })
  }

  /**
   * 解除绑定（对齐 iOS: revokeSharedToMeDevice → unbindDeviceSharedWithMe）
   */
  unbindSharedDevice() {
    if (!this.deviceToUnbind) {
      return
    }
    const device = this.deviceToUnbind
    const pid = device.productId || ''
    const dn = device.deviceName || device.id
    this.dismissUnbindDialog()
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      this.deviceToUnbind = null
      return
    }
    const deviceId = new TXIoTDeviceId()
    deviceId.productId = pid
    deviceId.deviceName = dn
    dm.unbindDeviceSharedWithMe(deviceId, {
      onSuccess: (_: void) => {
        this.showToast('已解除绑定')
        this.sharedToMeDevices = this.sharedToMeDevices.filter(
          d => !(d.productId === device.productId && d.deviceName === device.deviceName)
        )
        this.deviceToUnbind = null
      },
      onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
        this.showToast(errorMessage || '解除绑定失败')
        this.deviceToUnbind = null
      }
    })
  }

  /**
   * 绑定分享设备（对齐 iOS: bindSharedDevice）
   * 通过 JSON 字符串解析 productId/deviceName/token
   */
  bindSharedDevice() {
    const jsonString = this.bindShareJson.trim()
    if (!jsonString) {
      this.showToast('请输入有效的分享内容')
      return
    }
    const fid = this.getFamilyId()
    if (!fid) {
      this.showToast('未找到家庭ID')
      return
    }
    const dm = AppState.engine().getDeviceManager()
    if (!dm) {
      this.showToast('设备管理器未初始化')
      return
    }
    try {
      const json: Record<string, string> = JSON.parse(jsonString) as Record<string, string>
      const productId = json['productId'] || ''
      const deviceName = json['deviceName'] || ''
      const token = json['token'] || ''
      if (!productId || !deviceName || !token) {
        this.showToast('无效的分享内容，请确认格式正确')
        return
      }
      animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        this.showBindShareDialog = false
      })
      const deviceId = new TXIoTDeviceId()
      deviceId.productId = productId
      deviceId.deviceName = deviceName
      dm.bindDeviceSharedWithMe(deviceId, token, {
        onSuccess: (_: void) => {
          this.showToast('设备绑定成功')
          this.bindShareJson = ''
          this.loadSharedToMeDevices()
        },
        onError: (_errorCode: TXIoTErrorCode, errorMessage: string) => {
          this.showToast(errorMessage || '绑定失败')
        }
      })
    } catch (err) {
      this.showToast('无效的分享内容，请确认格式正确')
    }
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column({ space: 12 }) {
          Text('⏳').fontSize(40)
          Text('加载中...').fontSize(14).fontColor(AppColor.TextSecondary)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.sharedToMeDevices.length === 0) {
        // 无设备空状态（对齐 iOS: emptyStateView）
        Column({ space: 12 }) {
          Text('📷').fontSize(40)
          Text('暂无分享给我的设备').fontSize(14).fontColor(AppColor.TextSecondary)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 设备列表（对齐 iOS: ScrollView + VStack of device rows）
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.sharedToMeDevices, (device: DeviceModel) => {
              Row({ space: 12 }) {
                // 设备图标圈
                Stack() {
                  Text('📹').fontSize(18)
                }
                .width(44).height(44).borderRadius(22)
                .backgroundColor('#EEF4FF')

                // 设备信息
                Column({ space: 4 }) {
                  Text(device.name)
                    .fontSize(15).fontWeight(FontWeight.Normal).fontColor(AppColor.TextPrimary)
                  Text('ProductId: ' + (device.productId || ''))
                    .fontSize(12).fontColor(AppColor.TextSecondary)
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                // 解除绑定按钮（对齐 iOS: "解除绑定"）
                Button('解除绑定')
                  .height(32)
                  .fontSize(13)
                  .fontColor('#FF4444')
                  .fontWeight(FontWeight.Normal)
                  .backgroundColor(Color.Transparent)
                  .border({ width: 1.5, color: '#FF4444', radius: 6 })
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.deviceToUnbind = device
                    this.showUnbindDialog = true
                  })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(AppColor.BgCard)
              .borderRadius(12)
              .border({ width: 1, color: '#E8EAF0' })
            })
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 80
          })
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }

      // 绑定分享按钮（固定在底部，对齐 iOS: bindShareButton）
      Row() {
        Button() {
          Row({ space: 6 }) {
            Text('🔗').fontSize(14)
            Text('绑定分享').fontSize(14).fontColor('#006EFF').fontWeight(FontWeight.Normal)
          }
        }
        .attributeModifier(SecondaryButton)
        .layoutWeight(1).height(44)
        .onClick(() => {
          this.showBindShareDialog = true
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 22 })

      // ==================== 弹窗区域 ====================

      // 解除绑定确认弹窗（对齐 iOS: unbindSheet）
      ConfirmDialog({
        show: $showUnbindDialog,
        title: '解除绑定',
        message: `确定要解除与「${this.deviceToUnbind?.name || ''}」的绑定吗？解除后该设备将不再显示。`,
        confirmText: '确定解除',
        confirmDanger: true,
        cancelText: '取消',
        onConfirm: () => {
          this.unbindSharedDevice()
        },
        onCancel: () => {
          this.deviceToUnbind = null
        }
      })

      // 绑定分享设备弹窗（对齐 iOS: bindShareSheet）
      CommonBottomSheet({
        show: $showBindShareDialog,
        title: '🔗 绑定分享设备',
        showCaption: false,
        confirmText: '确定',
        cancelText: '取消',
        onConfirm: () => {
          this.bindSharedDevice()
        },
        onCancel: () => {
          this.bindShareJson = ''
        }
      }) {
        Column({ space: 4 }) {
          Text('请输入设备分享码')
            .fontSize(13).fontColor('#6A6E78')
            .width('100%')
          TextArea({ placeholder: '请粘贴分享 JSON 内容', text: this.bindShareJson })
            .width('100%')
            .height(132)
            .fontSize(15)
            .fontColor(AppColor.TextPrimary)
            .placeholderColor('#B0B7C3')
            .backgroundColor('#F7F8FA')
            .borderRadius(8)
            .border({ width: 1, color: AppColor.BorderInput, radius: 8 })
            .padding(14)
            .onChange((val: string) => {
              this.bindShareJson = val
            })
        }
        .width('100%').padding({ left: 20, right: 20 })
      }
    }
    .width('100%').layoutWeight(1)
  }
}
