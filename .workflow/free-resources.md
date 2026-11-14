# free-resources.md — 免费方案速查（free-for.dev）

```
作用：选型 / 找方案灵感的第一入口。要免费资源（托管、CI、DB、监控、API、邮件…）
先来这里搜，再上官网核对额度。
何时读：任何"找个免费方案 / 有没有免费的 X"类任务，动手搜索前。
```

- 网站：<https://free-for.dev/>
- 内容源：GitHub `ripienaar/free-for-dev`（README 即全部内容，网站只是渲染层）
- 规模与活跃度：130k+ stars、1600+ 贡献者、纯 PR 驱动，更新频繁

## 收录标准（可信度来源）

- 只收 **as-a-Service**（SaaS / PaaS / IaaS），不收 self-hosted 软件；
- 必须是**永久免费层**，不是限时试用；按时间分桶的额度须至少持续一年；
- 不收录把 TLS 加密限制在付费层的服务。

## 分类速查（全站约 50 类，节选）

| 需求 | 对应分类 |
|---|---|
| 云额度 / 托管部署 | Major Cloud Providers、PaaS、Web Hosting、IaaS |
| CI/CD、代码质量 | CI/CD、Code Quality、Code Search、Testing |
| 数据库 / 数据 / API | Managed Data Services、APIs Data and ML、Artifact Repos |
| 监控 / 日志 | Monitoring、Log Management |
| 网络 | DNS、CDN and Protection、Tunneling |
| 安全 / 认证 | Security and PKI、Authentication |
| 其他 | Email、Generative AI、Docker Related、Messaging and Streaming、IDE |

## 怎么搜（省开销优先）

原则：**远程定点检索，不把内容搬回来**。README 是 MB 级大文件，clone 仓库 / 全量下载回来调研纯属浪费——先读本文档选分类，再定点检索只看需要的那一小段。

1. **浏览器**：打开 <https://free-for.dev/> 直接 Cmd+F 搜关键词——单页含全部条目，定点查找最快。
2. **GitHub 站内搜索**：`repo:ripienaar/free-for-dev <关键词>` 直接命中条目；README 顶部目录带锚点，点分类直达后只读该节。
3. **AI 抓取（最后手段）**：free-for.dev 是 JS 渲染页，WebFetch 只能拿到 "Loading..."。确需抓 raw README 时**禁止无关键词全量拉取**——先用 WebSearch / GitHub 搜索定到目标服务，抓取时给明确指令（只返回目标分类 / 服务的条目），不给"总结全文"类任务：
   `https://raw.githubusercontent.com/ripienaar/free-for-dev/master/README.md`

## 使用铁律

- **不下载回来调研**：不 clone 仓库、不把 README 存到本地再读；一律远程定点检索，最小化 token / 流量开销。
- **清单会过期**：免费层随时缩水 / 下线，"更新频繁" ≠ 实时准确。选中候选后**必须去官方站点核对当前额度与限制**，再落决策。
- 条目是众包的：描述 ≠ 官方承诺，一律以官网定价页为准。
- 采用某免费方案后，把「服务 + 免费额度 + 核对日期」记到对应工程 `.workflow/documentation.md`，便于追溯。
