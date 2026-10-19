import { ci } from './calmmit.mjs'

const { runPrivacyGuideCli } = await ci.load('privacy-guide')
process.exitCode = runPrivacyGuideCli({ root: ci.root })
