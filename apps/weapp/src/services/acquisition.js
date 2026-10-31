const hosts = new Set(['artificialanalysis.ai', 'epoch.ai', 'huggingface.co', 'vercel.com', 'ai-gateway.vercel.sh', 'docs.cloudbase.net', 'openrouter.ai'])
export function validGrant(grant) {
  return /^[A-Za-z0-9_-]{43}$/.test(grant?.token || '') && grant.expiresAt > Date.now()
}
export async function collectSources(platform, request, grant) {
  if (!validGrant(grant)) throw new Error('Invalid refresh grant')
  const specs = grant.acquisition?.resources
  if (!Array.isArray(specs) || !specs.length || specs.length > 3) throw new Error('Invalid acquisition plan')
  const resources = [], raw = []
  let size = 0
  for (const spec of specs) {
    let url = spec.url
    if (spec.revisionFrom != null) {
      const bytes = new Uint8Array(raw[spec.revisionFrom] || [])
      let text = ''
      for (let i = 0; i < bytes.length; i += 4096) text += String.fromCharCode(...bytes.subarray(i, i + 4096))
      const revision = JSON.parse(text).sha
      if (!/^[a-f0-9]{40}$/.test(revision || '')) throw new Error('Invalid dataset revision')
      url = url.replace('{revision}', revision)
    }
    const host = /^https:\/\/([^/?#:]+)(?:[/?]|$)/.exec(url || '')?.[1]
    if (!hosts.has(host) || !Number.isInteger(spec.maxBytes) || spec.maxBytes <= 0 || spec.maxBytes > 16 * 1024 * 1024) throw new Error('Invalid source URL')
    if (!validGrant(grant)) throw new Error('Expired refresh grant')
    try {
      const response = await request({ url, method: 'GET', timeout: 10000, responseType: 'arraybuffer', dataType: 'text', header: { Accept: spec.accept } })
      const bytes = response.data
      if (!(bytes instanceof ArrayBuffer) || bytes.byteLength > spec.maxBytes || (size += bytes.byteLength) > 17000000) throw new Error('Source too large')
      raw.push(bytes)
      resources.push({ url, data: platform.arrayBufferToBase64(bytes) })
    } catch (error) {
      if (!spec.optional) throw error
      raw.push(null); resources.push(null)
    }
  }
  return { resources }
}
