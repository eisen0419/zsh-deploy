# zsh-deploy

> **一键把新机器装成「现代化 zsh 工作环境」的部署脚本**
> oh-my-zsh + 6 个常用插件 + 主题 + 自动适配 macOS / Linux 的 sed/awk 差异

[原脚本（Gitee）](https://gitee.com/xuchaoxin1375/scripts/blob/main/wp/woocommerce/woo_df/sh/deploy_omz.sh) → 重写：跨平台兼容、参数化、幂等、防破坏。

---

## 目录

- [它能做什么](#它能做什么)
- [为什么不直接用原脚本](#为什么不直接用原脚本)
- [快速开始](#快速开始)
- [依赖](#依赖)
- [插件清单](#插件清单)
- [命令行参数](#命令行参数)
- [使用示例](#使用示例)
- [它会改你 zshrc 的哪些地方](#它会改你-zshrc-的哪些地方)
- [设计决策](#设计决策)
- [常见问题](#常见问题)
- [开发与贡献](#开发与贡献)

---

## 它能做什么

执行一次脚本，从零得到：

1. **oh-my-zsh** 安装（可选 GitHub / Gitee 镜像，国内友好）
2. **6 个常用插件** 自动 `git clone` 到 `~/.oh-my-zsh/custom/plugins/`
3. **`~/.zshrc` 改写** ：
   - 重写 `plugins=(...)` 数组，把启用插件加进去
   - 插入围栏区段（`# >>> tag` / `# <<< tag`）便于二次幂等更新
   - 主题改为 `random`（候选 `ys` 和 `junkfood`）
4. **跨平台 sed/awk 兼容**：macOS BSD 工具与 GNU 工具差异自动处理
5. **失败可恢复**：插件 clone 失败不影响其他步骤；每个步骤都是幂等的，重跑安全

适用场景：**新装的 Mac / VPS / Ubuntu / Debian** 一键拉环境，或在 Linux 服务器批量初始化 dotfiles 时调用。

不适用场景：已有大量 zshrc 自定义配置的老机器（脚本会重写 `plugins=(...)` 和 `ZSH_THEME`，请先备份）。

---

## 为什么不直接用原脚本

原脚本（Gitee）在 macOS 上跑会踩多个坑。本仓库的改动：

| 改进 | 说明 |
|------|------|
| **macOS sed 真正适配** | `_sed_inplace` 自动用 `gsed` / GNU `sed` / BSD `sed`。原脚本 `alias sed=gsed` 在非交互 bash 不展开，会失效 |
| **BSD awk 多行变量** | macOS 自带 awk 不支持 `awk -v var="多行字符串"`。改用 awk `getline` 从临时文件读入数组，POSIX 兼容 |
| **严格模式** | `set -euo pipefail`，任何命令失败立即停 |
| **Bash 4+ 守卫** | 显式检查 `BASH_VERSINFO`，给出 `brew install bash` 提示 |
| **镜像参数化** | `--mirror github\|gitee`，去掉 hardcode 的个人镜像 URL |
| **插件函数化** | 6 个 `git clone` 收敛成数组 + 单一循环 |
| **`exec zsh` 改为可选** | 原脚本默认替换当前进程，对自动化脚本不友好；本脚本默认不 exec，加 `--exec-zsh` 才执行 |

---

## 快速开始

### 一行部署（GitHub raw）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eisen0419/zsh-deploy/main/deploy_omz.sh)
```

### 国内服务器（Gitee 镜像）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eisen0419/zsh-deploy/main/deploy_omz.sh) \
  --install-omz gitee --mirror gitee
```

### macOS 显式调用 brew bash

macOS 自带 bash 是 3.2，脚本要求 ≥ 4。如果 PATH 没把 `/opt/homebrew/bin` 排在 `/bin` 前面，需要显式指定：

```bash
brew install bash
/opt/homebrew/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/eisen0419/zsh-deploy/main/deploy_omz.sh)"
```

### 本地 clone 后跑

```bash
git clone https://github.com/eisen0419/zsh-deploy.git
cd zsh-deploy
bash deploy_omz.sh --help
bash deploy_omz.sh
```

---

## 依赖

| 工具 | 说明 | 缺失时 |
|------|------|--------|
| `bash >= 4` | 脚本用了 `declare -A` / `${var,,}` 等 bash 4+ 语法 | macOS 需 `brew install bash` 后用 `/opt/homebrew/bin/bash` 跑 |
| `git` / `curl` / `zsh` | 基础工具 | 自行安装；缺失会立即退出 |
| `gsed`（仅 macOS） | GNU sed | 脚本会自动 `brew install gnu-sed` |
| `oh-my-zsh` | 由脚本自动安装 | 已存在则跳过 |

**Linux**：通常 bash 4+、GNU sed、GNU awk 都已就绪，无需额外操作。

**macOS**：必装 brew bash + gnu-sed（gnu-sed 脚本自动装；bash 需手动）。

---

## 插件清单

| 插件 | 默认 | 作用 | 仓库 |
|------|------|------|------|
| `zsh-completions` | ✅ | 大量第三方工具补全 | [zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions) |
| `zsh-autocomplete` | ✅ | 实时菜单式补全 | [marlonrichert/zsh-autocomplete](https://github.com/marlonrichert/zsh-autocomplete) |
| `zsh-autosuggestions` | ✅ | 历史命令灰色提示（fish 风格） | [zsh-users/zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) |
| `zsh-syntax-highlighting` | ✅ | 命令语法高亮 | [zsh-users/zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) |
| `zsh-history-substring-search` | ✅ | ↑↓ 按子串搜索历史 | [zsh-users/zsh-history-substring-search](https://github.com/zsh-users/zsh-history-substring-search) |
| `you-should-use` | ❌ | alias 提醒（你定义的 alias 你忘了用） | [MichaelAquilina/zsh-you-should-use](https://github.com/MichaelAquilina/zsh-you-should-use) |

每个插件都可以通过命令行参数关闭或重新启用，见下表。

---

## 命令行参数

```
Usage: bash deploy_omz.sh [options]

Options:
  -o,    --install-omz [default|github|gitee|false]
         oh-my-zsh 安装源（default = 用 install.ohmyz.sh 官方一键脚本）
  -m,    --mirror [github|gitee]
         插件 git 源（默认 github）
  -O,    --omz-only
         只装 oh-my-zsh，不装任何插件
  -zc,   --install-zsh-completions [true|false]
  -zac,  --install-zsh-autocomplete [omz|std|false]
         omz: 走 oh-my-zsh plugins 数组方式加载
         std: 直接 source 插件 .plugin.zsh 文件
         false: 不启用
  -zasp, --install-zsh-autosuggestions [true|false]
  -zysu, --install-zsh-you-should-use [true|false]
  -zshp, --install-zsh-syntax-highlighting [true|false]
  -zhssp,--install-zsh-history-substring-search [true|false]
         --zsh-custom <dir>      覆盖 ZSH_CUSTOM 路径
         --exec-zsh              结束时 exec zsh（默认不执行）
  -h,    --help
```

---

## 使用示例

### 1. 默认一键（最常用）

```bash
bash deploy_omz.sh
```

装 omz + 5 个默认插件 + 改 zshrc，跑完后手动开新 zsh 即可生效。

### 2. 国内服务器 / 网络受限环境

```bash
bash deploy_omz.sh --install-omz gitee --mirror gitee
```

omz 安装走 Gitee 镜像（自动改 install.sh 里的 REPO/REMOTE），插件也从 Gitee clone。

### 3. 只装 oh-my-zsh，不要任何插件

```bash
bash deploy_omz.sh -O
# 等价：bash deploy_omz.sh --omz-only
```

### 4. 关掉某个插件

```bash
# 不装 zsh-autocomplete（实时补全有时会闪屏，按需关）
bash deploy_omz.sh -zac false

# 启用 you-should-use（默认关）
bash deploy_omz.sh -zysu true
```

### 5. 跑完直接 exec zsh

```bash
bash deploy_omz.sh --exec-zsh
```

注意：`exec zsh` 会替换当前 shell 进程，在脚本/CI 环境里要谨慎。

### 6. 自定义 ZSH_CUSTOM 路径

```bash
bash deploy_omz.sh --zsh-custom /opt/zsh-shared/custom
```

适合多用户共享 zsh 配置的场景。

---

## 它会改你 zshrc 的哪些地方

脚本会原地修改 `~/.zshrc`，**强烈建议先备份**：

```bash
cp ~/.zshrc ~/.zshrc.bak.$(date +%Y%m%d-%H%M%S)
```

具体改动：

1. **`plugins=(...)` 数组重写**：保留 `git` 和 `z`，把启用的插件追加，禁用项前加 `#`

2. **插入 4 个围栏区段**：
   ```zsh
   # >>> disable_compfix
   ZSH_DISABLE_COMPFIX=true
   # <<< disable_compfix

   # >>> zsh-completions
   fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
   #autoload -U compinit && compinit
   # <<< zsh-completions

   # >>> zac_compinit
   zstyle ':compinit' arguments -i -u
   # <<< zac_compinit

   # >>> zac bindkey config
   bindkey '^I' menu-select
   ...
   # <<< zac bindkey config
   ```

   围栏标记的好处：**重跑脚本时会先删除这些区段再重新插入**，幂等无副作用。

3. **`ZSH_THEME` 改为 `"random"`**，候选限制为 `("ys" "junkfood")`

4. **空行压缩**：连续空行压成一个

5. **Ubuntu 特例**：检测到 Ubuntu 时往 `~/.zshenv` 写 `skip_global_compinit=1`（避免 Ubuntu 的全局 compinit 冲突）

---

## 设计决策

### 为什么主题强制改成 random？

让用户在不熟悉 zsh 主题时也能体验多个风格。`ys` 和 `junkfood` 是经过筛选的、无字体依赖（不需要 Powerline / Nerd Fonts）、信息密度合理的主题。

如果你已经有偏好主题，跑完后手动改回：

```bash
sed -i '' 's/^ZSH_THEME="random"/ZSH_THEME="agnoster"/' ~/.zshrc
```

### 为什么 you-should-use 默认不装？

它会在你输入命令时弹提示（"You should use alias xxx"），有人觉得很有用，有人觉得吵。默认不装，需要时 `-zysu true`。

### 围栏区段是什么？

形如 `# >>> tag` 到 `# <<< tag` 的区段，让脚本可以**幂等重跑**：每次先 `sed -d` 删除整段，再重新插入新内容。这避免了"跑两次 zshrc 就有两份配置"的问题。

### `--exec-zsh` 为什么改成默认关闭？

原脚本结束就 `exec zsh`，会立即替换当前 bash 进程。这在以下场景会出问题：

- CI / 自动化脚本里：后续命令再也跑不到
- 子 shell 里跑：会让父 shell 看不到任何后续 stdout

默认关闭后，脚本只打印 "===== DONE =====" 就退出，由用户手动开新 zsh 终端激活配置。

---

## 常见问题

### Q: 跑完后 zsh 启动报 "compinit insecure directories"

脚本已经在 zshrc 里写了 `zstyle ':compinit' arguments -i -u` 来忽略，正常情况不会报。如果还报：

```bash
chmod -R go-w "$(brew --prefix)/share"
chmod -R go-w ~/.oh-my-zsh/custom
rm -f ~/.zcompdump*
```

### Q: macOS 报 `Bash >= 4 required, current: 3.2.57`

```bash
brew install bash
/opt/homebrew/bin/bash deploy_omz.sh   # 显式调用 brew bash
```

或者把 `/opt/homebrew/bin` 加到 PATH 最前面。

### Q: 旧脚本跑过一次了，能直接跑这版覆盖吗？

可以。脚本对所有改动都是幂等的：
- 已存在的 omz 跳过重装
- 已 clone 的插件跳过 clone
- 围栏区段先删后插

### Q: 想关掉 `random` 主题但保留 candidates 列表

跑完后手动改：

```bash
sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="ys"/' ~/.zshrc
```

### Q: 跑到一半失败了怎么恢复？

脚本是 `set -euo pipefail`，任何步骤失败会立即停。失败前已经做的步骤（omz 安装、插件 clone）都是幂等的，**修复问题后重跑即可**。

---

## 开发与贡献

- 仓库：https://github.com/eisen0419/zsh-deploy
- 上游原版：https://gitee.com/xuchaoxin1375/scripts/blob/main/wp/woocommerce/woo_df/sh/deploy_omz.sh
- 改一行 → `bash -n deploy_omz.sh` 检查语法 → 在 macOS 和 Linux 各跑一次冒烟测试 → PR

### 文件结构

```
zsh-deploy/
├── deploy_omz.sh    # 主脚本（约 490 行）
├── README.md        # 本文件
└── .git/
```

### License

MIT
