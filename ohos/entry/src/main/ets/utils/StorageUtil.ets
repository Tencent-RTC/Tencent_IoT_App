import preferences from '@ohos.data.preferences'
import { UserModel, DeviceModel } from '../model/AppModel'

const PREF_NAME = 'iot_app_prefs'
const KEY_USERS = 'users'
const KEY_CURRENT_USER = 'currentUser'
const DEVICES_PREFIX = 'devices_'

let pref: preferences.Preferences | null = null

async function getPreferences(context: Context): Promise<preferences.Preferences> {
  if (!pref) {
    pref = await preferences.getPreferences(context, PREF_NAME)
  }
  return pref
}

export async function saveUsers(context: Context, users: UserModel[]): Promise<void> {
  const p = await getPreferences(context)
  await p.put(KEY_USERS, JSON.stringify(users))
  await p.flush()
}

export async function getUsers(context: Context): Promise<UserModel[]> {
  const p = await getPreferences(context)
  const val = await p.get(KEY_USERS, '[]') as string
  return JSON.parse(val) as UserModel[]
}

export async function saveCurrentUser(context: Context, user: UserModel | null): Promise<void> {
  const p = await getPreferences(context)
  if (user) {
    await p.put(KEY_CURRENT_USER, JSON.stringify(user))
  } else {
    await p.delete(KEY_CURRENT_USER)
  }
  await p.flush()
}

export async function getCurrentUser(context: Context): Promise<UserModel | null> {
  const p = await getPreferences(context)
  const val = await p.get(KEY_CURRENT_USER, '') as string
  if (!val) {
    return null
  }
  return JSON.parse(val) as UserModel
}

export async function saveDevices(context: Context, userId: string, devices: DeviceModel[]): Promise<void> {
  const p = await getPreferences(context)
  await p.put(DEVICES_PREFIX + userId, JSON.stringify(devices))
  await p.flush()
}

export async function getDevices(context: Context, userId: string): Promise<DeviceModel[]> {
  const p = await getPreferences(context)
  const val = await p.get(DEVICES_PREFIX + userId, '[]') as string
  return JSON.parse(val) as DeviceModel[]
}
