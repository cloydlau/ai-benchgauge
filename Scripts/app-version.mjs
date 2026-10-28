import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// Public versions use a Beijing calendar date. Platform metadata uses the same
// date split into numeric fields, within Apple's and Windows' field limits.
export function dateVersion(value) {
  if (typeof value !== 'string' || value.length !== 8 || !/^[1-9]\d{7}$/.test(value)) throw new Error('Application version must be a valid YYYYMMDD date')
  const year = Number(value.slice(0, 4)), month = Number(value.slice(4, 6)), day = Number(value.slice(6))
  const date = new Date(0)
  date.setUTCFullYear(year, month - 1, day)
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    throw new Error('Application version must be a valid YYYYMMDD date')
  }
  return value
}

export function createAutoVersion(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now)
  return dateVersion(['year', 'month', 'day'].map(type => parts.find(part => part.type === type).value).join(''))
}

export function platformVersion(value) {
  const date = dateVersion(value)
  return [date.slice(0, 4), date.slice(4, 6), date.slice(6)].map(Number).join('.')
}

export function readAppVersion(root, override) {
  const version = dateVersion(JSON.parse(readFileSync(join(root, 'config/app.json'), 'utf8')).version)
  if (override && dateVersion(override) !== version) throw new Error('MP_VERSION must match config/app.json; use Scripts/bump-version.sh to change every platform together')
  return version
}
