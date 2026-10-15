import { createApp } from '@vue-mini/core'
import './app.css'

createApp(() => {
  const manager = wx.getUpdateManager?.()
  manager?.onUpdateReady(() => wx.showModal({
    title: '发现新版本', content: '新版本已准备好，重启后生效。', showCancel: false,
    confirmText: '重启更新', success: result => { if (result.confirm) manager.applyUpdate() },
  }))
  return { version: __APP_VERSION__ }
})
