#!/usr/bin/env bash
# setup-input-method.sh —— 为 Typora AppImage 配置 GTK 输入法模块（fcitx / ibus）
#
# 为什么需要它：
#   Typora 0.11.18 (Electron 13) 启动时会丢弃 AppRun 里 export 的环境变量
#   （/proc/<pid>/environ 实测无 GTK_IM_MODULE 等），所以环境变量方案无效。
#   可靠的方式是在 GTK 配置文件里写明 im module（fcitx 官方推荐的 X11/XWayland
#   方案，GTK3 始终读取该文件）。本脚本自动检测你正在用的输入法框架并写入配置。
#
# 用法：
#   ./setup-input-method.sh             # 自动检测 fcitx5 / ibus
#   ./setup-input-method.sh fcitx       # 手动指定 fcitx
#   ./setup-input-method.sh ibus        # 手动指定 ibus
#   ./setup-input-method.sh --dry-run   # 只显示将要做的修改，不实际写入
#   ./setup-input-method.sh --help

set -u

GTK_DIR="$HOME/.config/gtk-3.0"
GTK_SETTINGS="$GTK_DIR/settings.ini"
DRY_RUN=0

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------- 检测当前输入法框架 ----------
detect_im() {
  if pgrep -x fcitx5 >/dev/null 2>&1; then
    echo "fcitx"
  elif pgrep -x ibus-daemon >/dev/null 2>&1; then
    echo "ibus"
  elif [ "${XDG_CURRENT_DESKTOP:-}" = "GNOME" ]; then
    echo "ibus"   # GNOME 默认使用 ibus
  else
    echo ""
  fi
}

# ---------- 检查系统是否安装了对应 GTK3 im module ----------
check_module() {
  local name="$1"   # fcitx 或 ibus
  local cache mod
  cache=$(find /usr/lib /usr/lib64 -path "*gtk-3.0*" -name immodules.cache 2>/dev/null | head -1)
  if [ -n "$cache" ] && grep -qi "im-$name" "$cache" 2>/dev/null; then
    return 0
  fi
  mod=$(find /usr/lib /usr/lib64 -path "*gtk-3.0*" -name "im-$name.so" 2>/dev/null | head -1)
  [ -n "$mod" ]
}

# ---------- 按发行版提示需要安装的包 ----------
pkg_hint() {
  local im="$1"
  if command -v pacman >/dev/null 2>&1; then
    [ "$im" = "fcitx" ] && echo "sudo pacman -S fcitx5-gtk" || echo "sudo pacman -S ibus"
  elif command -v apt-get >/dev/null 2>&1; then
    [ "$im" = "fcitx" ] && echo "sudo apt install fcitx5-frontend-gtk3" || echo "sudo apt install ibus-gtk3"
  elif command -v dnf >/dev/null 2>&1; then
    [ "$im" = "fcitx" ] && echo "sudo dnf install fcitx5-gtk3" || echo "sudo dnf install ibus-gtk3"
  elif command -v zypper >/dev/null 2>&1; then
    [ "$im" = "fcitx" ] && echo "sudo zypper install fcitx5-gtk3" || echo "sudo zypper install ibus-gtk3"
  else
    echo "请根据你的发行版安装 $im 的 GTK3 输入法模块"
  fi
}

# ---------- 参数解析 ----------
MODE="auto"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage ;;
    fcitx|ibus) MODE="$arg" ;;
    *) echo "未知参数: $arg" >&2; usage ;;
  esac
done

# ---------- 确定输入法 ----------
if [ "$MODE" = "auto" ]; then
  IM=$(detect_im)
  if [ -z "$IM" ]; then
    echo "无法自动检测输入法框架（未找到 fcitx5 / ibus-daemon 进程）。" >&2
    echo "请手动指定：$0 fcitx  或  $0 ibus" >&2
    exit 1
  fi
  echo "自动检测到输入法框架: $IM"
else
  IM="$MODE"
fi

# ---------- 检查 GTK im module ----------
if ! check_module "$IM"; then
  echo "⚠ 系统未找到 GTK3 的 $IM 输入法模块（im-$IM.so）。" >&2
  echo "  请先安装: $(pkg_hint "$IM")" >&2
  echo "  安装后重新运行本脚本。" >&2
  exit 1
fi

# ---------- 读取当前配置 ----------
mkdir -p "$GTK_DIR"
CURRENT=""
if [ -f "$GTK_SETTINGS" ]; then
  CURRENT=$(grep "^gtk-im-module=" "$GTK_SETTINGS" 2>/dev/null | tail -1 | cut -d= -f2)
fi

echo "GTK 配置文件: $GTK_SETTINGS"
echo "目标配置:     gtk-im-module=$IM"
if [ -n "$CURRENT" ]; then
  echo "当前配置:     gtk-im-module=$CURRENT"
fi

# ---------- 决定写入内容 ----------
if [ -n "$CURRENT" ] && [ "$CURRENT" = "$IM" ]; then
  echo "✅ 已配置为 $IM，无需修改。"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  echo ""
  echo "(--dry-run) 将要执行："
  if [ -n "$CURRENT" ]; then
    echo "  sed -i 's|^gtk-im-module=.*|gtk-im-module=$IM|' \"$GTK_SETTINGS\""
  else
    echo "  printf 'gtk-im-module=$IM\\n' >> \"$GTK_SETTINGS\""
  fi
  exit 0
fi

if [ -n "$CURRENT" ]; then
  echo ""
  read -r -p "将把 gtk-im-module 从 $CURRENT 替换为 $IM，继续? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "已取消。"; exit 1 ;;
  esac
  sed -i "s|^gtk-im-module=.*|gtk-im-module=$IM|" "$GTK_SETTINGS"
  echo "✅ 已更新为 gtk-im-module=$IM"
else
  if [ -s "$GTK_SETTINGS" ]; then
    grep -q "^\[Settings\]" "$GTK_SETTINGS" || printf '\n[Settings]\n' >> "$GTK_SETTINGS"
  else
    printf '[Settings]\n' > "$GTK_SETTINGS"
  fi
  # 将 gtk-im-module 插入 [Settings] 段末尾（不污染其他行/其他段）
  if command -v perl >/dev/null 2>&1; then
    perl -0pi -e "s|(^\[Settings\]\n(?:[^\[\n]+\n)*)|\$1gtk-im-module=$IM\n|m" "$GTK_SETTINGS"
  else
    printf 'gtk-im-module=%s\n' "$IM" >> "$GTK_SETTINGS"
  fi
  echo "✅ 已写入 gtk-im-module=$IM"
fi

echo ""
echo "请完全退出并重新启动 Typora AppImage 使配置生效。"
