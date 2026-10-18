# 本机原生构建缓存

`Scripts/build-cache.mjs` 管理本仓库的可重建缓存。Mac 打包、完整/Swift 测试、iOS 构建检查和手机构建/安装共用 `work/build-cache/native.lock`，同一时间执行一个受管理的原生构建任务；完整测试和发布检查不减少、不跳过。源码变动仍按原有测试签名判定通过结果是否有效。

常用缓存继续复用：Swift 使用固定的 `.build`、`work/unit-test-build`、`work/clang-modules` 和 `work/swiftpm-cache`；iOS 使用 `work/ios-build`、`work/ios-deploy/DerivedData`、`work/ios-deploy/CheckDerivedData` 内明确列出的 Build、模块、索引等缓存组件，不删除整个父目录中的日志或测试报告。Mac 在复制应用和完成签名后、iOS 在安装完成后、Swift 在覆盖率校验后才释放缓存使用权。

每个任务结束时自动检查登记目录：超过 7 天未使用的缓存优先回收；总量超过 20 GiB 时按登记的最后使用时间从旧到新回收。新接管的固定缓存从本次登记开始计时，不根据目录名或不可靠的文件访问时间推断历史。20 GiB 是软目标；仍被使用、无法检测、测量/删除失败的目录保留，并在 `work/build-cache/latest-cleanup.json` 报告。该预算只覆盖本仓库登记的缓存，不代表整个 `work/`、全部 Xcode 数据或系统交换空间的上限。

删除前检查目录各级均为实际目录，读取进程参数判断是否有手动构建正在使用该路径，并用 `lsof` 检查打开的文件。缓存内部链接按链接本身统计/删除，不遍历目标。没有 `ps` / `lsof` 或检查受限时跳过回收；Windows 等环境仍可构建，但不能声称已完成自动回收。锁属主包含 PID、进程启动时间和随机 token；不能确认身份的锁不按年龄强行抢占。回收崩溃后的锁还需要确认原缓存不再被进程使用。清理错误不会把失败的编译变成通过，也不会改变已完成命令的退出码。

状态和登记信息保存在忽略的 `work/build-cache/` 下，不保存命令参数、账号或环境变量。常用命令：

```sh
node Scripts/build-cache.mjs status  # 查看登记、运行锁和最近一次回收结果
node Scripts/build-cache.mjs clean   # 闲置时按同样规则回收；有构建锁就退出
```

一次性测试/截图应使用临时缓存入口，避免又在每个任务目录留下几 GB 编译产物：

```sh
node Scripts/build-cache.mjs run temporary -- zsh -c '
  export CLANG_MODULE_CACHE_PATH="$BENCHGAUGE_TEMP_CACHE/clang"
  swift build --scratch-path "$BENCHGAUGE_TEMP_CACHE/swift" --product leaderboard-menu
  # 在此使用产物；退出前将需要保留的截图/报告导出到 work/<任务名>/。
'
```

Xcode 临时任务同样将 `-derivedDataPath` 指向 `$BENCHGAUGE_TEMP_CACHE/DerivedData`。命令结束后，无论成功或失败，临时缓存都会尝试回收；仍有进程使用时保留，后续受管理任务结束时再检查。不要把源码、正式归档、崩溃符号、截图或唯一一份交付产物放入临时缓存，也不要在其中嵌套 `./test.sh`、`./make-app.sh` 等已经获取同一把锁的入口。

回收器不会扫描任意 `work/<任务名>` 并猜测用途，不处理账号、模拟器、系统缓存或交换空间。之前留下的未登记目录需要单独核查；后续任务通过上述入口获得自动回收。需要保留的正式发布归档和崩溃符号始终放在登记缓存之外。
