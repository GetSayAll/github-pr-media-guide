# GitHub PR 截图附件操作手册

> **版本**：1.1 · **核对日期**：2026-11-01
> **适用**：GitHub.com、macOS、GitHub CLI（`gh` ≥ 2.99.0，实测 2.103.3）
> **场景**：App / Web UI 变更时，把 Before/After 截图附加到 Pull Request，让 Reviewer 直接看到结果，同时**不把截图提交进 Git 仓库**。

## 1.1 相对 1.0 的修正

| 编号 | 修正内容 | 原因 |
| --- | --- | --- |
| 0 | 新增「第 0 步：环境自检」 | 1.0 把版本要求写在正文中段，照着往下抄会先撞 `unknown flag: --attach` |
| 3 | 区分「部分上传失败」与「全部上传失败」 | 只有部分失败才会留下 PR；全部失败时 **PR 根本没被创建** |
| 4 | 权限不足的实际表现是 **404**，不是 403 | 服务端对 `READ`/`TRIAGE` 权限返回 404，按 403 排查会走偏 |
| 5 | 补齐视频体积上限 | 图片 10 MB、视频 100 MB（Free 套餐服务端 10 MB），两者不同 |
| 6 | 补「路径回退到 cwd」 | `--body-file` 的相对路径找不到时会回退到当前工作目录，写错不一定报错 |
| 7 | 说明 `#alt` 只对**追加**的文件生效 | body 里已引用的图保留 body 自身写的 alt text |
| 8 | 补「同一文件不能 attach 两次」 | 官方文档明确限制 |
| 9 | 精确化 GHES 支持范围 | gh 直接拒绝 GHES，但 `ghe.com` 数据驻留租户可用 |
| 10 | WebP 标注为「需实测」 | gh 客户端接受，但官方《Attaching files》的图片类型列表未列 WebP |
| 11 | 补私有仓库的验证边界 | 私有仓库附件需认证，`curl` 探活不可靠 |
| 12 | 自检命令改用 `grep -c` | `gh ... --help \| grep -q` 会因 SIGPIPE + `pipefail` 误报"缺少参数" |

## 第 0 步：环境自检（先跑这个，30 秒）

**不要跳过。** 1.0 版最常见的失败不是权限也不是路径，而是 `gh` 版本太旧。

```bash
gh --version                                     # 需要 ≥ 2.99.0

for c in create edit comment; do
  n="$(gh pr "$c" --help 2>/dev/null | grep -c -- '--attach')"
  printf 'gh pr %-8s --attach: %s hit(s)\n' "$c" "$n"
done

gh auth status
```

> **别用 `gh pr create --help | grep -q -- '--attach'` 做判断。**
> `grep -q` 命中第一条就退出，`gh` 收到 SIGPIPE，加上 `set -o pipefail` 后整条管道返回 141，会把一个完全正常的 `gh` 判成"缺少该参数"。上面用 `grep -c`（读完整个输入）就是为了避开这个陷阱——本手册 1.1 的第一版草稿正是栽在这里。

判定：

| 现象 | 结论 | 处理 |
| --- | --- | --- |
| 三条都是 `1 hit(s)` 或更多 | 环境达标 | 继续 |
| 出现 `0 hit(s)`／`unknown flag: --attach` | 版本 < 2.99.0 | `brew upgrade gh`，再重跑本步 |
| `gh: command not found` | 未安装 | `brew install gh` |
| `auth status` 无目标仓库的写权限 | 权限不足 | 见 §8「404」一行 |

也可以直接跑本仓库的脚本，它一次性检查版本、`--attach` 可用性、登录身份和目标仓库写权限：

```bash
# GUIDE 是手册克隆到的位置；下面这条在工作目录=你的项目时也能跑
GUIDE="$HOME/Tools/github-pr-media-guide"
"$GUIDE/scripts/pr-check-env.sh" <owner>/<repo>
```

> **别在手册仓库里跑不带参数的自检。** 那样它检查的是手册仓库本身——你是它的 owner，
> 所有项都会通过，但你的 PR 目标根本没有被验证。脚本 v1.1 会对这个情况直接告警。

## 1. 推荐方案与基本原则

**推荐：GitHub 原生媒体附件 + `gh --attach`。** 不需要匿名图床、对象存储或额外账号；截图由 GitHub 托管，PR 正文里插入的是 GitHub 生成的 URL，不产生新的 Git 跟踪文件，也不增加仓库的对象历史体积。

原则：

1. **截图存放在 Git 工作区之外**，例如 `$TMPDIR` 下的独立临时目录；不要把图片放进仓库再"用完删掉"——一旦 `git add .` 就进了历史。
2. **PR 描述承载最终版截图**；开发过程中的轮次验证图作为 PR 评论补充，保留上下文。
3. **使用 `--body-file` + `--attach`**：先在 Markdown 里写本地相对路径，上传时由 `gh` 原位替换为托管 URL，正文结构和 alt text 都保留。
4. 图片**单张 ≤ 10 MB**；只上传与本次改动相关、且已检查过隐私内容的真实截图。
5. 上传失败时**先判断是哪一类失败**（见 §3 第四步下方的说明），再决定要不要重试——`gh` 可能部分成功并返回非零退出码。

### 支持范围（2026-11-01 核对）

- 创建 PR：`gh pr create --attach`
- 更新 PR 描述：`gh pr edit --attach`
- 评论附图：`gh pr comment --attach`
- `--attach` 可重复指定，**单次命令最多 50 个文件**（`gh` 内置上限）
- 支持格式：`.png` `.jpg` `.jpeg` `.gif` `.webp` `.svg` `.mp4` `.mov` `.webm`
- 需要目标仓库的 **write / maintain / admin** 权限（`read`、`triage` 会被拒，且服务端返回 **404**）
- 仅 GitHub.com；`gh` 对 GitHub Enterprise Server **直接拒绝**上传（`ghe.com` 数据驻留租户不受影响）

> **可见性**：公开仓库的附件**无需登录**即可访问；私有／内部仓库的附件仅限对该仓库有访问权限的人查看。不要把密钥、真实用户信息或企业敏感内容放进截图。

## 2. 环境准备

### 2.1 安装或升级 GitHub CLI

```bash
brew install gh     # 尚未安装
brew upgrade gh     # 已安装，升级到支持 --attach 的版本
gh --version
```

`--attach` 随 `gh` v2.99.0（2026-09-01 发布）引入。若你的包管理器版本滞后，可用 `gh upgrade` 或直接从 <https://github.com/cli/cli/releases> 取最新包。

### 2.2 登录并确认仓库权限

```bash
gh auth login --web
gh auth status

# 在目标仓库的工作区中执行
gh repo view --json nameWithOwner --jq .nameWithOwner
```

上传使用 `gh` 已有的凭据：`gh auth login` 产生的 OAuth token，或 **classic PAT**。GitHub Apps 的安装令牌只有部分被接受，**不要假设 GitHub Actions 自带的 `GITHUB_TOKEN` 或 fine-grained PAT 一定能上传**——先在测试 PR 上验证凭据。

## 3. 创建 PR 并上传 Before/After 截图（标准流程）

以下命令在**目标仓库根目录**运行；临时文件全部放在仓库之外。

### 第一步：创建截图临时目录

```bash
ASSET_DIR="$(mktemp -d "${TMPDIR%/}/pr-media.XXXXXX")"
echo "$ASSET_DIR"

cp /path/to/before.png "$ASSET_DIR/before.png"
cp /path/to/after.png  "$ASSET_DIR/after.png"
```

`${TMPDIR%/}` 去掉 macOS `$TMPDIR` 结尾的斜杠，否则拼出 `//` 的双斜杠路径（功能不受影响，但日志里很难看）。

采集截图：

```bash
# iOS Simulator（需先 booted）
xcrun simctl io booted screenshot "$ASSET_DIR/after.png"

# macOS App：交互式选区 / 窗口
screencapture -i "$ASSET_DIR/after.png"
screencapture -i -W "$ASSET_DIR/after.png"   # 仅窗口，带阴影
```

> **Before 截图必须来自修改前的真实界面**，不要从 After 反推、伪造或补造。拿不到就删掉 Before 小节，并在 PR 里说明——这比一张假的对比图诚实得多。

### 第二步：编写 PR 描述

保存为 `$ASSET_DIR/pr-body.md`（仓库内也提供可直接复制的 `templates/pr-body.md`）：

```markdown
## 变更摘要
- 优化设置页面布局
- 调整按钮间距与视觉层级

## 验证情况
- [x] 本地编译通过
- [x] 模拟器或真实设备中检查 UI

## UI 截图

### Before（修改前）
![修改前的设置页面](./before.png)

### After（修改后）
![修改后的设置页面](./after.png)
```

> **路径解析规则**：`--body-file` 里的图片路径**相对于该 body 文件所在目录**；在该目录找不到时，**回退到当前工作目录**再找一次。所以路径写错不一定报错，可能悄悄用了另一份同名文件——文件名尽量带上状态后缀。

### 第三步：推送分支并创建 PR

```bash
git status --short          # 确认没有截图被暂存
git push -u origin HEAD

gh pr create \
  --base main \
  --title "feat: 优化设置页面布局" \
  --body-file "$ASSET_DIR/pr-body.md" \
  --attach "$ASSET_DIR/before.png" \
  --attach "$ASSET_DIR/after.png"
```

`gh` 会上传媒体文件，把正文里匹配到的本地路径**原位替换**为 GitHub 托管 URL，并保留 Markdown 结构。没有被正文引用的附件，按传入顺序追加到正文末尾。

> `--attach` **不能与 `gh pr create --web` 或 `--dry-run` 组合**，会在参数校验阶段直接报错。

### 第四步：区分两类失败（关键）

`gh` 的流程是「**先上传，再创建 PR**」，所以失败的后果完全不同：

| 情况 | PR 是否已创建 | 退出码 | 处理 |
| --- | --- | --- | --- |
| 全部附件上传失败 | **否** | 非 0 | 报错含 `no pull request was created`。**不要**去 `gh pr list` 找 PR，直接修问题重跑 |
| 部分成功部分失败 | 是 | 非 0 | 新 PR 的 URL 仍会打印到 stdout。用 `gh pr view` 确认，再单独补传失败的图 |
| 权限 / 主机不支持 | **否** | 非 0 | 上传器在创建流程开始前就构建并校验，所以这类错误发生在任何创建动作之前 |

另外，**不要重复执行 `gh pr create`**。确认方式：

```bash
gh pr list --head "$(git branch --show-current)"
gh pr view --web
gh pr view --json body --jq .body    # 看实际写入的正文和 URL
git status --short                   # 截图不应出现在这里
```

最后**在浏览器里确认图片真的能显示**、顺序和说明正确、且没有敏感内容。

## 4. 已有 PR 的三种更新方式

### 4.1 在描述末尾追加一张截图（最简单）

```bash
gh pr edit 123 --attach "$ASSET_DIR/after.png#更新后的设置页面"
```

不提供 `--body`／`--body-file` 时，`gh pr edit` **保留原描述**，把附件追加到末尾。`#` 之后的字符串作为 alt text——**只对追加的文件生效**（见 4.2 的说明）。

### 4.2 把图片嵌入正文指定位置（推荐用于最终版）

先读取当前正文，**避免覆盖别人刚写的内容**：

```bash
gh pr view 123 --json body --jq .body > "$ASSET_DIR/current-pr-body.md"
```

在期望位置加上：

```markdown
### After（更新后）
![最新设置页面](./after.png)
```

然后：

```bash
gh pr edit 123 \
  --body-file "$ASSET_DIR/current-pr-body.md" \
  --attach "$ASSET_DIR/after.png"
```

**注意**：

- `--body-file` 会**整体替换**描述。操作前确认没有人并发更新正文。
- 正文里**已经引用**的图片会保留正文自己写的 alt text；此时 `--attach path#alt` 里的 `#alt` 被忽略。想让 alt 生效，就写在 Markdown 里，而不是写在参数里。
- 已有 GitHub 托管 URL 可以原样保留，不必重新上传旧图。
- 更新同一张图时**替换旧的引用**，不要叠加——Reviewer 不需要看五代历史截图。

### 4.3 用评论记录每一轮验证（推荐用于开发过程）

```bash
gh pr comment 123 \
  --body "第二轮 UI 验证：调整了按钮间距。" \
  --attach "$ASSET_DIR/after.png#第二轮验证截图"
```

建议：主描述只留最终 Before/After，迭代过程用评论补充。

## 5. 体积与格式控制

上限（2026-11-01 核对）：

| 类型 | `gh` 客户端上限 | 服务端上限 |
| --- | --- | --- |
| 图片 / GIF | 10 MB | 10 MB |
| 视频 | 100 MB | Free 套餐 10 MB；付费套餐 100 MB |

`gh` 对视频放宽到 100 MB 是因为它无法在请求前得知账户套餐，真正的限制由服务端把关。

```bash
# 查看大小（字节）
stat -f%z "$ASSET_DIR/after.png"

# 长边压到 1600px
sips -Z 1600 "$ASSET_DIR/after.png" --out "$ASSET_DIR/after-resized.png"

# PNG 仍过大且不需要透明度时转 JPEG
sips -s format jpeg "$ASSET_DIR/after.png" --out "$ASSET_DIR/after.jpg"
```

转换后**同步改 Markdown 里的路径和 `--attach` 的路径**。UI 细节（字体渲染、1px 细线、圆角边缘）优先保留 PNG，JPEG 的色度抽样会让这些细节失真，Reviewer 可能误判成实现问题。

**视频**：用 `![](video.mp4)` 引用，且该引用**必须独占一个段落**，否则渲染成链接而不是播放器。编码建议 H.264，兼容性最好；视频没有 alt text。

## 6. Coding Agent 规范（可复制到 AGENTS.md / CLAUDE.md）

```markdown
### Pull Request UI Media Policy

- When a change affects visible App UI, capture genuine screenshots from a
  working build, simulator, or device whenever the environment permits.
- Prefer Before/After screenshots if both states are actually available.
  Never fabricate a "Before" image or claim a screenshot was verified
  without producing and inspecting it.
- Keep generated screenshots outside the Git working tree (use a temporary
  directory). Never stage or commit PR-only screenshots to the repository.
- Use GitHub CLI >= 2.99.0 and `gh pr create/edit/comment --attach` to upload
  screenshots as native GitHub attachments; do not depend on anonymous hosts.
- For the final PR description, author Markdown with local image references
  and pass the same image files using `--attach` so gh rewrites URLs in place.
  Alt text written in the Markdown wins over `#alt` on the flag.
- Keep images below 10 MB (videos: 10 MB on free plans, 100 MB on paid) and
  remove private/sensitive data before uploading.
- Uploads happen before the PR is created. If every attachment fails, no PR
  exists; if only some fail, the PR exists with a nonzero exit code and its
  URL is printed. Check which case you are in before retrying.
- Verify the rendered PR and `git status` after publication. If screenshots
  cannot be captured, explain that limitation; do not fabricate evidence.
```

工作流：**改代码 → 构建/运行 → 截图（临时目录）→ 写 PR Markdown → `gh --attach` → 浏览器验证 → 查 Git 状态**。

## 7. 脚本

| 脚本 | 用途 |
| --- | --- |
| `scripts/pr-check-env.sh` | 自检 `gh` 版本、`--attach` 可用性、登录身份、目标仓库写权限 |
| `scripts/pr-media-comment.sh` | 给已有 PR 追加一条带多张附件的评论，不改动原描述 |
| `scripts/install-skill.sh` | 检测本机装有哪些 Coding Agent，把 `skills/github-pr-media` 同步进去并校验 sha256 |

```bash
GUIDE="$HOME/Tools/github-pr-media-guide"    # 手册克隆到的位置
cd /path/to/your-project                     # 要发 PR 的那个仓库

# 自检（不传参数时检查当前目录所属仓库；传 owner/repo 更明确）
"$GUIDE/scripts/pr-check-env.sh"

# 给已有 PR 追加一条带图的评论（-R 可省略，省略时用当前仓库）
"$GUIDE/scripts/pr-media-comment.sh" 123 \
  /path/to/after.png '/path/to/detail.png#详情页'

# 用 -R 指定别的仓库、用 -b 自定义评论正文
"$GUIDE/scripts/pr-media-comment.sh" -R owner/repo -b "第三轮验证" 123 ./after.png
```

脚本已在克隆时自带可执行权限（git 记录为 `100755`），无需 `chmod`。若你的环境不保留权限位，再执行 `chmod +x "$GUIDE"/scripts/*.sh`。

两个脚本都会在上传前完成本地校验（版本、文件存在、格式、体积、权限），但**最终结果以 GitHub 的返回为准**。

## 8. 常见问题与风险

| 问题 | 处理方法 |
| --- | --- |
| `unknown flag: --attach` | `gh` < 2.99.0。`brew upgrade gh` 后重跑 §0 自检。 |
| 报错 `404` / `could not resolve to a Repository` | 大概率是**权限不足**而非仓库不存在：`read`、`triage` 权限的服务端返回就是 404。用 `gh auth status` 确认身份，确认对目标仓库有 write 以上权限。 |
| `attaching files is not supported on GitHub Enterprise Server` | 目标主机是 GHES。`ghe.com` 数据驻留租户不受此限。 |
| 本地图片路径上传后没被替换 | 检查三处是否一致：`--body-file` 所在目录、Markdown 里的相对路径、`--attach` 的实参路径。注意路径会回退到 cwd，可能匹配到了另一份同名文件。 |
| 报错 `cannot attach the same file twice` | 同一个文件不能重复 attach。Before/After 若指向同一路径，先复制成两个不同文件名。 |
| 图片 > 10 MB / 视频上传被拒 | 缩小或压缩；视频受套餐限制（Free 10 MB）。 |
| `gh` 返回非 0，但 GitHub 上有 PR | 属于**部分上传失败**：PR 已创建，用 `gh pr comment --attach` 补传缺的图。 |
| `gh` 返回非 0，且提示 `no pull request was created` | **全部上传失败，PR 未创建**。修完问题重跑 `gh pr create`，不用担心重复。 |
| 需要覆盖旧版 After 图 | 读正文 → 换成新的本地路径 → `gh pr edit --body-file ... --attach ...`。 |
| 想彻底删除图片 | 从正文删掉引用**不等于**附件本体已被物理删除；不要把它当可控的私有对象存储。 |
| 想把附件当官网/CDN 用 | 不要。PR 附件适合代码审查，正式资产用专门的对象存储。 |
| CI 里用 `GITHUB_TOKEN` 上传失败 | 不要假设它对媒体上传可用；看 §2.2，或把上传放在已登录且有写权限的宿主上。 |

## 9. 项目落地建议

对常驻的 Coding Agent（Issue → 改代码 → 测试 → PR）：

- **生成位置**：`$TMPDIR/pr-media.XXXXXX`，仓库外。
- **输入**：真实截图、可选 Before、`pr-body.md`。
- **发布**：首次 `gh pr create --body-file ... --attach ...`；增量验证 `gh pr comment --attach ...`；调整主描述 `gh pr edit`。
- **检查点**：截图真实且清晰、无敏感数据、单张 ≤ 10 MB、PR 渲染正常、`git status` 干净。
- **异常处理**：先判断是「全部失败（无 PR）」还是「部分失败（有 PR）」，再补偿；绝不盲目重复创建。
- **权限边界**：Agent 用独立凭据，只给目标仓库所需最小权限。

## 10. 官方参考资料

均为 GitHub 官方文档／官方仓库，2026-11-01 核对：

1. GitHub Changelog — GitHub CLI: Media in issues, pull requests, and comments（2026-09-01）：
   <https://github.blog/changelog/2026-09-01-github-cli-media-in-issues-pull-requests-and-comments/>
2. GitHub Docs — Attaching files with GitHub CLI：
   <https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli>
3. GitHub Docs — Attaching files（体积上限、可见性、支持的格式）：
   <https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files>
4. GitHub CLI — `gh pr create`：<https://cli.github.com/manual/gh_pr_create>
5. GitHub CLI — `gh pr edit`：<https://cli.github.com/manual/gh_pr_edit>
6. GitHub CLI — `gh pr comment`：<https://cli.github.com/manual/gh_pr_comment>
7. GitHub CLI — `gh auth login`：<https://cli.github.com/manual/gh_auth_login>

### 附录：关键结论的源码依据

本手册中容易写错、且容易互相抄错的几条，均在 `cli/cli` **v2.103.3** 源码中确认：

| 结论 | 依据 |
| --- | --- |
| 单命令 50 个文件上限 | `internal/attachments/flags.go` — `maxAttachments = 50` |
| 图片 10 MB / 视频 100 MB | `internal/attachments/userasset.go` — `maxImageBytes`、`maxVideoBytes` |
| 允许的扩展名 | `internal/attachments/userasset.go` — `contentTypes` |
| 权限白名单 `ADMIN/MAINTAIN/WRITE`，其余 404 | `internal/attachments/client.go` — `uploadPermissions`、`checkPermission` |
| GHES 被直接拒绝 | `internal/attachments/client.go` — `checkHost` |
| `--attach` 与 `--web`／`--dry-run` 互斥 | `pkg/cmd/pr/create/create.go` — `MutuallyExclusive` |
| 上传失败先于创建，全部失败则不建 PR | `pkg/cmd/pr/create/create.go` — `submitPR` 中 `uploadResult.Uploaded == 0` 分支 |
| body-file 路径相对其目录，回退 cwd | `gh pr create/edit/comment --help` 正文 |

WebP 一项是唯一未完全对上的：`gh` 客户端接受 `.webp`，但官方《Attaching files》的图片类型列表里只列了 PNG / GIF / JPEG / SVG。**首次使用 WebP 时请先在一张图上实测**，不要批量上传。

---

**结论**：PR 的 UI 截图优先用 `gh --attach`。它同时满足「Reviewer 能直接看图」和「Git 仓库不背媒体负担」，也便于 Coding Agent 在无浏览器环境下自动执行。
