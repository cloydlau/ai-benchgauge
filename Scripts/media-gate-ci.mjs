import { ci } from './calmmit.mjs'
process.env.BASE_SHA = process.argv[2] || process.env.BASE_SHA || ''
process.env.HEAD_SHA = process.argv[3] || process.env.HEAD_SHA || 'HEAD'
ci.runModule('check-media-review')
