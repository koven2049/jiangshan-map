# jiangshan-map

中国历史疆域交互地图（静态站点，GitHub Pages 发布 + mini 本地服务双出口）。
本文件暂只含工程专属约束，harness 通用块由 `sync-harness.sh` 后续分发时自动前置。

## 本工程专属

**发布与部署。** 内容发布 = `./manage.sh deploy`：零传输，在本目录内 validate
（node scripts/validate_atlas.js）→ `git push origin`（koven2049/jiangshan-map 是
唯一发布目标；upstream 仓从不 fetch/push）。本地服务部署 = `./manage.sh
deploy-local`：rsync 到同机 `~/Services/jiangshan-map`（默认目标，须已存在），
只同步代码，`.rsync-exclude` 覆盖远端自增数据与密钥。

**托管（2026-11-13 规约）。** 双形态：生产 = mini `~/Services/jiangshan-map` 副本，
系统 LaunchDaemon `com.koven.jiangshan-map` 托管（模板 `deploy/com.koven.jiangshan-map.plist`
与线上一致，`./manage.sh install-daemon` 打印安装命令）；Test = 本目录 nohup + pidfile，
绝不托管给系统（install-daemon 拒绝无章检出）。**实例身份 = 部署盖章**：
deploy-local 成功后向目标副本写 `config/env=production`（唯一写入点），无章检出 = Test；
源副本带章拒绝部署（方向单向）；托管判定目录级（label 在系统域且监听进程属本目录），
托管态 stop 走免密 `svc-ctl` bootout 真停、start 幂等、restart 靠 kill+KeepAlive 免 sudo；
端口被别目录实例占用时诚实报错。`deploy`（git push）不落盘、不盖章。
