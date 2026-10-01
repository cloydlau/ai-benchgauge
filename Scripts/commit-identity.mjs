import { ci } from './calmmit.mjs'
export const { ownerIdentity, HUMAN, avatarForModel, resolveModelAvatar, detectModelName, emailForModel, resolveCommitIdentity, withCommitIdentity, withCommitIdentityCommand, commitIdentityEnv, formatCommitIdentity, commitArgs } = await ci.load('commit-identity')
