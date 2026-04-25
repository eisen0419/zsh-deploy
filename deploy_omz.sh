#!/usr/bin/env bash
# deploy_omz.sh — Robust zsh + oh-my-zsh + plugins deployer
# Rewrite of:
#   https://gitee.com/xuchaoxin1375/scripts/blob/main/wp/woocommerce/woo_df/sh/deploy_omz.sh
#
# 改进 vs 原脚本：
#   - macOS sed 真正适配（封装 _sed_inplace；原脚本 alias sed=gsed 在非交互 bash 不展开）
#   - 严格模式 set -euo pipefail
#   - bash 4+ 守卫（${var,,} 在 macOS 默认 bash 3.2 会语法错误）
#   - 镜像源参数化 --mirror github|gitee；去掉 hardcode 个人镜像
#   - 6 个插件 git clone 收敛为数组 + 单一函数
#   - exec zsh 改为 --exec-zsh 可选，默认不替换当前进程
#   - 顶层 return 0 改为 exit 0（脚本是 bash 直接执行，不是 source）
#
# 一键部署：
#   bash <(curl -fsSL https://raw.githubusercontent.com/eisen0419/zsh-deploy/main/deploy_omz.sh)

set -euo pipefail

VERSION=20260424

# ----------------------------------------------------------------------------
# 默认配置
# ----------------------------------------------------------------------------
INSTALL_OMZ="default"                       # default|github|gitee|false
MIRROR="github"                             # github|gitee
OMZ_ONLY=false
EXEC_ZSH=false
INSTALL_ZSH_COMPLETIONS=true
INSTALL_ZSH_AUTOCOMPLETE=omz                # omz|std|false
INSTALL_ZSH_AUTOSUGGESTIONS=true
INSTALL_ZSH_YOU_SHOULD_USE=false
INSTALL_ZSH_SYNTAX_HIGHLIGHTING=true
INSTALL_ZSH_HISTORY_SUBSTRING_SEARCH=true
ZSHRC_PATH="${HOME}/.zshrc"

# ----------------------------------------------------------------------------
# 帮助
# ----------------------------------------------------------------------------
usage() {
    cat <<EOF
deploy_omz.sh v${VERSION}

Robust zsh + oh-my-zsh + plugins deployer.

Usage: bash deploy_omz.sh [options]

Options:
  -o,    --install-omz [default|github|gitee|false]
         Install oh-my-zsh from given source (default: default)
  -m,    --mirror [github|gitee]
         Plugin git source (default: github)
  -O,    --omz-only
         Install oh-my-zsh only, skip plugins
  -zc,   --install-zsh-completions [true|false]
  -zac,  --install-zsh-autocomplete [omz|std|false]
  -zasp, --install-zsh-autosuggestions [true|false]
  -zysu, --install-zsh-you-should-use [true|false]
  -zshp, --install-zsh-syntax-highlighting [true|false]
  -zhssp,--install-zsh-history-substring-search [true|false]
         --zsh-custom <dir>      Override ZSH_CUSTOM
         --exec-zsh              exec zsh at end (default: no)
  -h,    --help

Examples:
  bash deploy_omz.sh
  bash deploy_omz.sh -O
  bash deploy_omz.sh --mirror gitee --install-omz gitee
  bash deploy_omz.sh -zysu false
EOF
}

# ----------------------------------------------------------------------------
# 工具函数
# ----------------------------------------------------------------------------
log() { printf '[deploy_omz] %s\n' "$*"; }
err() { printf '[deploy_omz][error] %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 跨平台 sed -i：优先 gsed，其次 GNU sed，最后 BSD sed
_sed_inplace() {
    if command -v gsed >/dev/null 2>&1; then
        gsed -i "$@"
    elif sed --version >/dev/null 2>&1; then
        sed -i "$@"
    else
        local script="$1"; shift
        sed -i '' "$script" "$@"
    fi
}

# 同上但启用扩展正则 -E
_sed_inplace_ext() {
    if command -v gsed >/dev/null 2>&1; then
        gsed -i -E "$@"
    elif sed --version >/dev/null 2>&1; then
        sed -i -E "$@"
    else
        local script="$1"; shift
        sed -i '' -E "$script" "$@"
    fi
}

# ----------------------------------------------------------------------------
# 前置检查
# ----------------------------------------------------------------------------
check_bash_version() {
    if (( BASH_VERSINFO[0] < 4 )); then
        err "Bash >= 4 required, current: $BASH_VERSION"
        err "On macOS:  brew install bash && exec /opt/homebrew/bin/bash $0 \"\$@\""
        exit 2
    fi
}

check_requirements() {
    local missing=0
    for cmd in git curl zsh; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            err "'$cmd' not found"
            missing=1
        fi
    done
    (( missing == 0 )) || exit 2

    if [[ "$OSTYPE" == darwin* ]] && ! command -v gsed >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            log "macOS detected without gsed; installing gnu-sed via brew"
            brew install gnu-sed || die "Failed to install gnu-sed"
        else
            die "macOS without gsed and brew. Install gnu-sed manually."
        fi
    fi
}

# ----------------------------------------------------------------------------
# 参数解析
# ----------------------------------------------------------------------------
parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -o|--install-omz)                              INSTALL_OMZ="$2"; shift 2 ;;
            -m|--mirror)                                   MIRROR="$2"; shift 2 ;;
            -O|--omz-only)                                 OMZ_ONLY=true; shift ;;
            -zc|--install-zsh-completions)                 INSTALL_ZSH_COMPLETIONS="$2"; shift 2 ;;
            -zac|--install-zsh-autocomplete)               INSTALL_ZSH_AUTOCOMPLETE="$2"; shift 2 ;;
            -zasp|--install-zsh-autosuggestions)           INSTALL_ZSH_AUTOSUGGESTIONS="$2"; shift 2 ;;
            -zysu|--install-zsh-you-should-use)            INSTALL_ZSH_YOU_SHOULD_USE="$2"; shift 2 ;;
            -zshp|--install-zsh-syntax-highlighting)       INSTALL_ZSH_SYNTAX_HIGHLIGHTING="$2"; shift 2 ;;
            -zhssp|--install-zsh-history-substring-search) INSTALL_ZSH_HISTORY_SUBSTRING_SEARCH="$2"; shift 2 ;;
            --zsh-custom)                                  ZSH_CUSTOM="$2"; shift 2 ;;
            --exec-zsh)                                    EXEC_ZSH=true; shift ;;
            -h|--help)                                     usage; exit 0 ;;
            *) err "Unknown option: $1"; usage >&2; exit 1 ;;
        esac
    done

    INSTALL_OMZ=$(lower "$INSTALL_OMZ")
    MIRROR=$(lower "$MIRROR")
    INSTALL_ZSH_AUTOCOMPLETE=$(lower "$INSTALL_ZSH_AUTOCOMPLETE")

    case "$INSTALL_OMZ" in default|github|gitee|false) ;; *) die "Invalid --install-omz: $INSTALL_OMZ" ;; esac
    case "$MIRROR" in github|gitee) ;; *) die "Invalid --mirror: $MIRROR" ;; esac
    case "$INSTALL_ZSH_AUTOCOMPLETE" in omz|std|false) ;; *) die "Invalid --install-zsh-autocomplete: $INSTALL_ZSH_AUTOCOMPLETE" ;; esac
}

# ----------------------------------------------------------------------------
# oh-my-zsh 安装
# ----------------------------------------------------------------------------
install_omz() {
    if [[ "$INSTALL_OMZ" == "false" ]]; then
        log "Skip oh-my-zsh installation"
        return 0
    fi
    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
        log "oh-my-zsh already installed (remove ${HOME}/.oh-my-zsh to reinstall)"
        return 0
    fi
    log "Installing oh-my-zsh from: $INSTALL_OMZ"
    case "$INSTALL_OMZ" in
        default)
            sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended
            ;;
        github)
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
            ;;
        gitee)
            local tmp; tmp=$(mktemp)
            curl -fsSL https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh -o "$tmp"
            # 注释 install.sh 中原有的 REPO/REMOTE 行，并追加 gitee 镜像配置
            _sed_inplace_ext '/^(remote|repo)/I s/^#*/#/' "$tmp"
            _sed_inplace_ext '/^#*remote/I a\
REPO=${REPO:-mirrors/oh-my-zsh}\
REMOTE=${REMOTE:-https://gitee.com/${REPO}.git}' "$tmp"
            sh "$tmp" "" --unattended
            rm -f "$tmp"
            ;;
    esac
}

# ----------------------------------------------------------------------------
# 插件源 URL
# ----------------------------------------------------------------------------
plugin_url() {
    local name="$1"
    if [[ "$MIRROR" == "github" ]]; then
        case "$name" in
            zsh-completions)              echo "https://github.com/zsh-users/zsh-completions.git" ;;
            zsh-autocomplete)             echo "https://github.com/marlonrichert/zsh-autocomplete.git" ;;
            zsh-autosuggestions)          echo "https://github.com/zsh-users/zsh-autosuggestions.git" ;;
            you-should-use)               echo "https://github.com/MichaelAquilina/zsh-you-should-use.git" ;;
            zsh-syntax-highlighting)      echo "https://github.com/zsh-users/zsh-syntax-highlighting.git" ;;
            zsh-history-substring-search) echo "https://github.com/zsh-users/zsh-history-substring-search.git" ;;
        esac
    else
        case "$name" in
            zsh-completions)              echo "https://gitee.com/mirrors/zsh-completions.git" ;;
            zsh-autocomplete)             echo "https://gitee.com/mirrors/zsh-autocomplete.git" ;;
            zsh-autosuggestions)          echo "https://gitee.com/zsh-users/zsh-autosuggestions.git" ;;
            you-should-use)               echo "https://gitee.com/mirrors/zsh-you-should-use.git" ;;
            zsh-syntax-highlighting)      echo "https://gitee.com/zsh-users/zsh-syntax-highlighting.git" ;;
            zsh-history-substring-search) echo "https://gitee.com/mirrors/zsh-history-substring-search.git" ;;
        esac
    fi
}

# ----------------------------------------------------------------------------
# 插件 clone
# ----------------------------------------------------------------------------
clone_plugins() {
    local zsh_custom="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
    local plugins_dir="${zsh_custom}/plugins"
    mkdir -p "$plugins_dir"

    declare -A wanted=(
        [zsh-completions]="$INSTALL_ZSH_COMPLETIONS"
        [zsh-autocomplete]="$([[ $INSTALL_ZSH_AUTOCOMPLETE != false ]] && echo true || echo false)"
        [zsh-autosuggestions]="$INSTALL_ZSH_AUTOSUGGESTIONS"
        [you-should-use]="$INSTALL_ZSH_YOU_SHOULD_USE"
        [zsh-syntax-highlighting]="$INSTALL_ZSH_SYNTAX_HIGHLIGHTING"
        [zsh-history-substring-search]="$INSTALL_ZSH_HISTORY_SUBSTRING_SEARCH"
    )

    local name enabled target url
    for name in "${!wanted[@]}"; do
        enabled="${wanted[$name]}"
        target="${plugins_dir}/${name}"
        if [[ "$enabled" != "true" ]]; then
            log "Skip $name"
            continue
        fi
        if [[ -d "$target" ]]; then
            log "$name already cloned"
            continue
        fi
        url=$(plugin_url "$name")
        log "Cloning $name from $url"
        git clone --depth 1 "$url" "$target" || err "Failed to clone $name"
    done
}

# ----------------------------------------------------------------------------
# .zshrc 修改
# ----------------------------------------------------------------------------
ensure_zshrc() {
    [[ -f "$ZSHRC_PATH" ]] || touch "$ZSHRC_PATH"
}

build_plugins_block() {
    # 输出 plugins 列表，每行一个名字，禁用项前缀 #
    {
        echo "git"
        echo "z"
        [[ "$INSTALL_ZSH_SYNTAX_HIGHLIGHTING" == true ]]      && echo "zsh-syntax-highlighting"      || echo "#zsh-syntax-highlighting"
        [[ "$INSTALL_ZSH_AUTOSUGGESTIONS" == true ]]          && echo "zsh-autosuggestions"          || echo "#zsh-autosuggestions"
        [[ "$INSTALL_ZSH_HISTORY_SUBSTRING_SEARCH" == true ]] && echo "zsh-history-substring-search" || echo "#zsh-history-substring-search"
        [[ "$INSTALL_ZSH_YOU_SHOULD_USE" == true ]]           && echo "you-should-use"               || echo "#you-should-use"
        [[ "$INSTALL_ZSH_AUTOCOMPLETE" == omz ]]              && echo "zsh-autocomplete"             || echo "#zsh-autocomplete"
    }
}

update_plugins_array() {
    # 用 awk 替换 plugins=(...) 区段，处理单行和多行两种
    # block 写文件 + awk getline 读，避开 BSD awk 不支持多行 -v 变量
    local block_file; block_file=$(mktemp)
    build_plugins_block > "$block_file"
    local tmp; tmp=$(mktemp)
    awk -v block_file="$block_file" '
        BEGIN {
            in_block = 0
            while ((getline line < block_file) > 0) block[++n] = line
            close(block_file)
        }
        /^plugins=\(/ {
            print "plugins=("
            for (i = 1; i <= n; i++) print block[i]
            print ")"
            if ($0 !~ /\)/) in_block = 1
            next
        }
        in_block {
            if (/\)/) in_block = 0
            next
        }
        { print }
    ' "$ZSHRC_PATH" > "$tmp"

    # 没找到 plugins=(...) 就追加
    if ! grep -q '^plugins=(' "$ZSHRC_PATH"; then
        {
            cat "$ZSHRC_PATH"
            echo
            echo "plugins=("
            cat "$block_file"
            echo ")"
        } > "$tmp"
    fi

    rm -f "$block_file"
    mv "$tmp" "$ZSHRC_PATH"
}

# 删除围栏区段（# >>> tag 到 # <<< tag）
remove_fenced_section() {
    local tag="$1"
    _sed_inplace "/# >>> ${tag}/,/# <<< ${tag}/d" "$ZSHRC_PATH"
}

# 在文件头部插入围栏区段
prepend_fenced_section() {
    local tag="$1"; shift
    local body="$1"
    local tmp; tmp=$(mktemp)
    {
        echo "# >>> ${tag}"
        printf '%s\n' "$body"
        echo "# <<< ${tag}"
        cat "$ZSHRC_PATH"
    } > "$tmp"
    mv "$tmp" "$ZSHRC_PATH"
}

# 在文件尾部追加围栏区段
append_fenced_section() {
    local tag="$1"; shift
    local body="$1"
    {
        echo "# >>> ${tag}"
        printf '%s\n' "$body"
        echo "# <<< ${tag}"
    } >> "$ZSHRC_PATH"
}

update_zsh_completions_config() {
    remove_fenced_section "zsh-completions"
    [[ "$INSTALL_ZSH_COMPLETIONS" == "true" ]] || return 0

    local switch=""
    [[ "$INSTALL_ZSH_AUTOCOMPLETE" != "false" ]] && switch="#"

    local body
    body=$(cat <<EOF
fpath+=\${ZSH_CUSTOM:-\${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
${switch}autoload -U compinit && compinit
EOF
)
    # 插到 plugins=( 之前
    if grep -q '^plugins=(' "$ZSHRC_PATH"; then
        local body_file; body_file=$(mktemp)
        printf '%s\n' "$body" > "$body_file"
        local tmp; tmp=$(mktemp)
        awk -v body_file="$body_file" '
            BEGIN {
                while ((getline line < body_file) > 0) body[++n] = line
                close(body_file)
            }
            /^plugins=\(/ && !inserted {
                print "# >>> zsh-completions"
                for (i = 1; i <= n; i++) print body[i]
                print "# <<< zsh-completions"
                print ""
                inserted = 1
            }
            { print }
        ' "$ZSHRC_PATH" > "$tmp"
        rm -f "$body_file"
        mv "$tmp" "$ZSHRC_PATH"
    else
        append_fenced_section "zsh-completions" "$body"
    fi
    rm -f "${HOME}/.zcompdump"
}

update_zsh_autocomplete_config() {
    remove_fenced_section "zsh-autocomplete"
    remove_fenced_section "zac_compinit"
    remove_fenced_section "zac bindkey config"
    remove_fenced_section "disable_compfix"

    case "$INSTALL_ZSH_AUTOCOMPLETE" in
        false)
            return 0
            ;;
        std)
            prepend_fenced_section "zsh-autocomplete" \
'source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh'
            ;;
    esac

    # std 和 omz 都需要这些配置
    prepend_fenced_section "disable_compfix" 'ZSH_DISABLE_COMPFIX=true'

    append_fenced_section "zac_compinit" \
"# 避免 zsh compinit insecure-directory 警告（通常是 linuxbrew 用户权限问题）
zstyle ':compinit' arguments -i -u"

    local bindkey_body
    bindkey_body=$(cat <<'EOF'
# Tab / Shift-Tab 在补全菜单中切换，而不是退出菜单
bindkey              '^I' menu-select
[[ -n "${terminfo[kcbt]}" ]] && bindkey "${terminfo[kcbt]}" menu-select
# 即使在菜单中，Enter 也始终提交命令
bindkey -M menuselect '^M' .accept-line
EOF
)
    append_fenced_section "zac bindkey config" "$bindkey_body"

    # ubuntu 需要 skip_global_compinit
    if [[ -f /etc/os-release ]] && grep -qi 'NAME="Ubuntu' /etc/os-release; then
        local zshenv="${HOME}/.zshenv"
        touch "$zshenv"
        if ! grep -q '^skip_global_compinit=1' "$zshenv"; then
            echo 'skip_global_compinit=1' >> "$zshenv"
        fi
    fi
}

set_random_theme() {
    if grep -qE '^ZSH_THEME=' "$ZSHRC_PATH"; then
        _sed_inplace_ext 's/^ZSH_THEME=.*/ZSH_THEME="random"/' "$ZSHRC_PATH"
    else
        echo 'ZSH_THEME="random"' >> "$ZSHRC_PATH"
    fi
    if grep -qE '^#?\s*ZSH_THEME_RANDOM' "$ZSHRC_PATH"; then
        _sed_inplace_ext 's/^#?\s*(ZSH_THEME_RANDOM[^=]*=).*/\1\("ys" "junkfood"\)/' "$ZSHRC_PATH"
    else
        echo 'ZSH_THEME_RANDOM_CANDIDATES=("ys" "junkfood")' >> "$ZSHRC_PATH"
    fi
}

compress_blank_lines() {
    # 连续空行压缩成一个
    _sed_inplace '/^$/N;/^\n$/D' "$ZSHRC_PATH"
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
main() {
    check_bash_version
    parse_args "$@"
    check_requirements

    install_omz

    if [[ "$OMZ_ONLY" == true ]]; then
        log "omz-only mode; done"
        [[ "$EXEC_ZSH" == true && "$INSTALL_OMZ" != "false" ]] && exec zsh
        exit 0
    fi

    clone_plugins
    ensure_zshrc
    update_plugins_array
    update_zsh_completions_config
    update_zsh_autocomplete_config
    set_random_theme
    compress_blank_lines

    log "Plugin lines in zshrc:"
    grep -E 'zsh-syntax-highlighting|zsh-autosuggestions|zsh-history-substring-search|zsh-autocomplete|zsh-completions' "$ZSHRC_PATH" || true
    log "Theme lines:"
    grep -E '^[^#]*(THEME|RANDOM)' "$ZSHRC_PATH" | cat -n || true

    log "===== DONE ====="
    [[ "$EXEC_ZSH" == true ]] && exec zsh
    exit 0
}

main "$@"
