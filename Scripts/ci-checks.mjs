import { ci } from './calmmit.mjs'
ci.run(['check', ...process.argv.slice(2)])
