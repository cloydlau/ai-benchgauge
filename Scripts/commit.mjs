import { ci } from './calmmit.mjs'
ci.run(['commit', ...process.argv.slice(2)])
