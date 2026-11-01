# github-pr-media-guide

把 **Before / After 界面截图**作为 GitHub 原生附件贴到 Pull Request 上：
Reviewer 能直接看到真实界面，而截图**不会进入 Git 仓库**。

> 本手册的每条非显然结论都已对照 `cli/cli` **v2.103.3** 源码和 GitHub 官方文档核实（2026-11-01），
> 两个脚本都实测过。依据对照表在手册末尾。

[English](README.en.md) · [完整手册](docs/PR-MEDIA-GUIDE.zh-CN.md)

## 前置条件

1. `gh` ≥ **2.99.0**（`--attach` 从这个版本才有，2026-09-01 发布）
2. 对目标仓库有 **write / maintain / admin** 权限（`read`、`triage` 会失败，而且报的是 404）
3. GitHub.com（GitHub Enterprise Server 不支持；`ghe.com` 数据驻留租户可以）

## 5 分钟上手

```bash
# ① 把手册放到任意位置。它是只读参考，不需要是 git 仓库。
git clone https://github.com/GetSayAll/github-pr-media-guide ~/Tools/github-pr-media-guide
GUIDE="$HOME/Tools/github-pr-media-guide"

# ② 进入「你要发 PR 的那个项目」，自检环境
cd /path/to/your-project
"$GUIDE/scripts/pr-check-env.sh"

# ③ 截图存到仓库之外
ASSET_DIR="$(mktemp -d "${TMPDIR%/}/pr-media.XXXXXX")"
xcrun simctl io booted screenshot "$ASSET_DIR/after.png"   # 模拟器
# screencapture -i "$ASSET_DIR/after.png"                   # macOS 交互选区

# ④ 复制模板，按实际情况改
cp "$GUIDE/templates/pr-body.md" "$ASSET_DIR/pr-body.md"

# ⑤ 发布（仍在上面的项目目录里）
gh pr create --base main --title "feat: 优化设置页面布局" \
  --body-file "$ASSET_DIR/pr-body.md" \
  --attach "$ASSET_DIR/before.png" \
  --attach "$ASSET_DIR/after.png"
```

**全程只在一个工作目录里操作**：`cd` 到你的项目后，手册相关命令一律用 `"$GUIDE/..."` 绝对路径调用。

> 为什么反复强调：如果直接在手册仓库里跑 `./scripts/pr-check-env.sh`，
> 它检查的是**手册仓库本身**（你是它的 owner，权限自然是 ADMIN），看起来全绿，
> 但你的 PR 目标是另一个仓库。v1.1 的脚本现在会对这种情况直接给出警告。

## 我该看哪一份

| 你的情况 | 去哪 |
| --- | --- |
| 只想确认这台机器的 `gh` 能不能用 | 跑 `"$GUIDE/scripts/pr-check-env.sh"` |
| 手动给 PR 加 Before/After | [手册 §3](docs/PR-MEDIA-GUIDE.zh-CN.md) |
| 已有 PR，只想补几张图 | [手册 §4](docs/PR-MEDIA-GUIDE.zh-CN.md) 或 `scripts/pr-media-comment.sh` |
| 让 AI Agent 全自动做 | 见下面「装到 Agent 里」 |
| 上传报错 / 退出码非 0 | [手册 §8 常见问题](docs/PR-MEDIA-GUIDE.zh-CN.md) |

## 装到 Agent 里

[`skills/github-pr-media/SKILL.md`](skills/github-pr-media/SKILL.md) 是给 Coding Agent 用的规则文件，
**不含任何项目私有信息，也不需要改任何仓库的 `AGENTS.md`**——装到用户级目录，所有项目自动生效。

```bash
"$GUIDE/scripts/install-skill.sh" --dry-run   # 先看它打算装到哪
"$GUIDE/scripts/install-skill.sh"             # 确认后执行
```

脚本会**先判断这台机器装了哪些 Agent**，只往真实存在的那些里写：

| 工具 | 检测依据 | 目标目录 |
| --- | --- | --- |
| WorkBuddy | `/Applications/WorkBuddy.app` | `~/.workbuddy/skills/github-pr-media/` |
| Claude Code | `claude` 在 `PATH` 上 | `~/.claude/skills/github-pr-media/` |
| Codex | `codex` 在 `PATH` 上 | `~/.codex/skills/github-pr-media/` |

> **只有配置目录不算装了。** 卸载 CLI 通常不会删 `~/.claude` 这类目录，所以
> 「目录存在但工具已卸」会被明确标注 `looks uninstalled` 并跳过，避免你以为装好了。
> 写入后逐份比对 sha256，不一致直接报错。

装好之后，Agent 遇到「UI 改动要贴截图」会自己走这套流程：临时目录截图 → 写本地路径的 Markdown →
`gh --attach` → 按失败类型判断要不要重试 → 验证渲染和 `git status`。

### 以后怎么更新

改仓库里的 `skills/github-pr-media/SKILL.md` → 提交 → 重跑 `install-skill.sh`。
**不要直接改本机副本**，那是产物，下次同步会被覆盖。

完整说明（检测规则、`--force` / `--target`、手动同步、卸载、生效时机）见
[安装与同步](docs/INSTALL-SKILL.zh-CN.md)。

## 目录结构

| 路径 | 是什么 |
| --- | --- |
| [`docs/PR-MEDIA-GUIDE.zh-CN.md`](docs/PR-MEDIA-GUIDE.zh-CN.md) | 完整手册：流程、失败分类、体积限制、FAQ、源码依据附录 |
| [`docs/INSTALL-SKILL.zh-CN.md`](docs/INSTALL-SKILL.zh-CN.md) | 技能的安装、更新、同步与卸载 |
| [`skills/github-pr-media/SKILL.md`](skills/github-pr-media/SKILL.md) | 可被 Agent 直接加载的规则文件 |
| [`scripts/install-skill.sh`](scripts/install-skill.sh) | 检测本机已装的 Agent，安装/更新技能并校验 sha256 |
| [`scripts/pr-check-env.sh`](scripts/pr-check-env.sh) | 自检：`gh` 版本、`--attach` 是否可用、登录身份、目标仓库写权限 |
| [`scripts/pr-media-comment.sh`](scripts/pr-media-comment.sh) | 给已有 PR 追加一条带多张附件的评论，不改原描述 |
| [`templates/pr-body.md`](templates/pr-body.md) · [`.en.md`](templates/pr-body.en.md) | 含 Before/After 小节的 PR 模板 |

## 四个真会咬人的坑

1. **`gh` 太旧。** `--attach` 从 **v2.99.0** 起才有。旧版只回一句 `unknown flag: --attach`，
   而大多数人会先去查权限，白花一小时。先跑自检。

2. **退出码非 0 不等于「没有 PR」。** 上传发生在创建**之前**：
   全部上传失败 → **PR 没被创建**（报错含 `no pull request was created`）；
   部分失败 → **PR 已经创建了**，URL 打到 stdout，退出码仍非 0。盲目重跑 `gh pr create` 就会出重复 PR。

3. **权限不足长得像 404。** 服务端对 `read` / `triage` 返回的是 404，「repository not found」通常
   意思是「去要写权限」，不是仓库名写错了。

4. **`gh ... --help | grep -q -- '--attach'` 会骗你。** `grep -q` 命中就退出，`gh` 收 SIGPIPE，
   配合 `set -o pipefail` 会把一个正常的 `gh` 判成缺参数。用 `grep -c`。
   （写本手册 v1.1 时就是这么被坑的，自检脚本已绕开。）

## 核实过的关键事实

| 结论 | 依据 |
| --- | --- |
| 单命令最多 50 个文件 | `internal/attachments/flags.go` — `maxAttachments = 50` |
| 图片 10 MB、视频 100 MB（客户端） | `internal/attachments/userasset.go` |
| 视频服务端：Free 10 MB / 付费 100 MB | GitHub Docs — Attaching files |
| 仅 `ADMIN`/`MAINTAIN`/`WRITE` 可传，其余 404 | `internal/attachments/client.go` |
| GHES 被客户端直接拒绝 | `internal/attachments/client.go` — `checkHost` |
| `--attach` 不能配 `--web` / `--dry-run` | `pkg/cmd/pr/create/create.go` |
| 全部失败 → PR 未创建 | `pkg/cmd/pr/create/create.go` — `submitPR` |

## 许可

MIT，见 [LICENSE](LICENSE)。
