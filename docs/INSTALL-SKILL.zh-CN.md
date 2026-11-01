# 安装、更新与同步 Skill

本文覆盖一件事：把 `skills/github-pr-media/SKILL.md` 放到本机各个 Coding Agent 的
用户级技能目录里，**并且在后续修改时保持一致**。

- 不需要改任何仓库的 `AGENTS.md`
- 不需要逐个项目安装（用户级目录对所有项目生效）
- 不需要手工 `cp`——用脚本，它会先判断你这台机器上到底装了哪些 Agent

## 为什么"先判断有没有装"

直接 `cp` 到 `~/.claude/skills/` 看起来最省事，但有个真实陷阱：**卸载 CLI 通常不会删除
`~/.claude` 这类配置目录**。于是目录还在、工具已经没了，脚本照样往里写，你就以为装好了。

所以判定分三档：

| 档位 | 依据 | 处理 |
| --- | --- | --- |
| 已安装 | 可执行文件在 `PATH` 上，或 `/Applications` 下有 App Bundle | 同步 |
| 疑似残留 | **只有**配置目录（`~/.claude` 等），没有 CLI 也没有 App | 跳过并标注 `looks uninstalled` |
| 未安装 | 两者都没有 | 跳过 |

被跳过的项会在输出里写明依据，你不至于"以为装了其实没装"。

## 一键安装 / 更新

```bash
GUIDE="$HOME/Tools/github-pr-media-guide"
"$GUIDE/scripts/install-skill.sh" --dry-run    # 先看计划，不写任何文件
"$GUIDE/scripts/install-skill.sh"              # 确认后执行
```

输出示例（这台机器）：

```
Skill source: ~/Tools/github-pr-media-guide/skills/github-pr-media/SKILL.md
Checksum:     5d45baf8

TOOL           DETECTED BY                        ACTION
-------------- ---------------------------------- ------
WorkBuddy      app /Applications/WorkBuddy.app    ok (checksum verified)
Claude Code    cli /Users/me/.local/bin/claude    ok (checksum verified)
Codex          cli /Users/me/.volta/bin/codex     ok (checksum verified)

Updated 3 agent(s), skipped 0, failed 0.
```

写入后会**逐份校验 sha256**，对不上直接报 `CHECKSUM MISMATCH` 并以非 0 退出——
避免出现"复制了一半"的文件。

### 选项

| 选项 | 作用 |
| --- | --- |
| `--dry-run` | 只打印计划，不写文件 |
| `--force claude` | 即使没检测到也同步（`workbuddy` / `claude` / `codex`，也接受工具全名） |
| `--target PATH` | 额外同步到一个自定义 skills 目录，可重复 |
| `-h` | 帮助 |

```bash
# 装到一个脚本还不认识的工具
"$GUIDE/scripts/install-skill.sh" --target ~/.some-agent/skills

# 只装某一个
"$GUIDE/scripts/install-skill.sh" --force codex
```

## 支持的 Agent 与检测依据

| Agent | 二进制 | App Bundle | 目标目录 |
| --- | --- | --- | --- |
| WorkBuddy | —（GUI 应用） | `/Applications/WorkBuddy.app` | `~/.workbuddy/skills/github-pr-media/` |
| Claude Code | `claude` | — | `~/.claude/skills/github-pr-media/` |
| Codex | `codex` | — | `~/.codex/skills/github-pr-media/` |

其它兼容 Agent Skills 规范的工具用 `--target` 接入，例如 Cursor 之类没有稳定约定的目录不要猜。

## 更新流程（唯一正确的顺序）

```bash
# 1. 改仓库里的源文件，不要改本机副本
$EDITOR "$GUIDE/skills/github-pr-media/SKILL.md"

# 2. 提交
cd "$GUIDE" && git add -A && git commit -m "skill: ..." && git push

# 3. 同步到本机所有已安装的 Agent
"$GUIDE/scripts/install-skill.sh"
```

> **不要反向操作。** 直接改 `~/.workbuddy/skills/github-pr-media/SKILL.md` 或
> `~/.claude/skills/...` 下的那份，下次同步会被源文件覆盖，改动静默消失。
> 本机副本是**产物**，不是源。

## 手动同步（不想跑脚本时）

脚本做的事就是三次 `cp`，只是多做了一层检测和校验：

```bash
GUIDE="$HOME/Tools/github-pr-media-guide"
for d in ~/.workbuddy/skills ~/.claude/skills ~/.codex/skills; do
  [ -d "$(dirname "$d")" ] || continue        # 对应的工具至少该有配置目录
  mkdir -p "$d/github-pr-media"
  cp "$GUIDE/skills/github-pr-media/SKILL.md" "$d/github-pr-media/SKILL.md"
done

# 校验
shasum -a 256 "$GUIDE/skills/github-pr-media/SKILL.md" ~/.claude/skills/github-pr-media/SKILL.md
```

手写版本没有 CLI/App 检测，也没有校验和比对，所以只在临时排障时用。

## 卸载

```bash
for d in ~/.workbuddy/skills ~/.claude/skills ~/.codex/skills; do
  rm -rf "$d/github-pr-media"
done
```

只删技能自己的子目录，不要动整个 `skills/`——那里还有别人的技能。

## 生效时机

技能在**会话开始时**加载。安装完成后，已经打开的会话看不到它，新开一个会话即可。
WorkBuddy 可以用技能设置的「已安装」页确认它出现在列表里。
