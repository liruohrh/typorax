#!/usr/bin/env bash
# build.sh —— 构建带 typora_plugin 的 Typora 0.11.18 发行包（Linux amd64/arm64 AppImage + Windows x64 zip + dmg）
#
# 设计：与 GitHub Action 一致——在仓库 checkout 目录内运行，原始包取自
#       freearchives/，产物输出到 build/。amd64/arm64 用同一套 AppDir 组装
#       逻辑 + appimagetool（--runtime-file 指定架构 runtime）。
#
# 用法:
#   ./build.sh                    # 插件用最新代码（tmpapps/typora_plugin，git 最新 commit 日期命名）
#   ./build.sh 1.19.0             # 插件用指定版本（下载 typora-plugin@v1.19.0.zip）
#   ./build.sh 1.19.0 -t vplugin-x  # 同时指定自定义 release tag（默认 vplugin{版本|日期}）
#
# 产物（build/）:
#   Typora-0.11.18-plugin-{插件版本|commit日期}-amd64.AppImage
#   Typora-0.11.18-plugin-{插件版本|commit日期}-arm64.AppImage
#   Typora-0.11.18-plugin-{插件版本|commit日期}-amd64.zip   (Windows x64)
#   Typora-0.11.18.dmg                                     (仅下载/复制，Linux 无法重新打包 dmg)
#
# 配置说明: typora_plugin 优先读写主机 ~/.config/typora_plugin/；AppRun 首次
#           启动时把默认配置复制过去（AppImage 内 resources/ 只读，不复制会报
#           EROFS）。沙箱: userns 可用则 --disable-setuid-sandbox，否则 --no-sandbox。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$ROOT/tmpapps"
TOOLS="$TMP/tools"
BUILD="$ROOT/build"
ARCHIVES="$ROOT/freearchives"
VER_TYPORA="0.11.18"
REPO_URL="git@github.com:liruohrh/typorax.git"
BUILD_TIME="$(date -u +'%Y-%m-%d %H:%M UTC')"

# ---------- 参数解析 ----------
PLUGIN_VER=""
RELEASE_TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag) RELEASE_TAG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) PLUGIN_VER="$1"; shift ;;
  esac
done

mkdir -p "$TMP" "$TOOLS" "$BUILD" "$TMP/plugin_dist"

# ---------- 工具准备（缺失自动下载，本地/CI 通用）----------
dl() { curl -sL -o "$1" "$2"; }

if [ ! -x "$TOOLS/7zz" ]; then
  echo "== 下载 7-Zip =="
  dl "$TOOLS/7z.tar.xz" "https://www.7-zip.org/a/7z2602-linux-x64.tar.xz"
  (cd "$TOOLS" && (tar xf 7z.tar.xz 2>/dev/null || bsdtar -xf 7z.tar.xz) && chmod +x 7zz)
fi
if [ ! -x "$TOOLS/innoextract-1.9-linux/bin/amd64/innoextract" ]; then
  echo "== 下载 innoextract =="
  dl "$TOOLS/innoextract.tar.xz" "https://github.com/dscharrer/innoextract/releases/download/1.9/innoextract-1.9-linux.tar.xz"
  (cd "$TOOLS" && (tar xf innoextract.tar.xz 2>/dev/null || bsdtar -xf innoextract.tar.xz) && chmod +x innoextract-1.9-linux/bin/amd64/innoextract)
fi
if [ ! -x "$TOOLS/appimagetool.AppImage" ]; then
  echo "== 下载 appimagetool =="
  dl "$TOOLS/appimagetool.AppImage" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$TOOLS/appimagetool.AppImage"
fi
# runtime 由 appimagetool 按目标架构自动下载（type2-runtime，支持 zstd）

SZ="$TOOLS/7zz"
INNOEXTRACT="$TOOLS/innoextract-1.9-linux/bin/amd64/innoextract"
APPIMAGETOOL="$TOOLS/appimagetool.AppImage"

# ---------- 原始包（freearchives/）----------
[ -f "$ARCHIVES/typora_${VER_TYPORA}_amd64.deb" ] || { echo "❌ 缺 freearchives/typora_${VER_TYPORA}_amd64.deb"; exit 1; }
[ -f "$ARCHIVES/typora_${VER_TYPORA}_arm64.deb" ] || { echo "❌ 缺 freearchives/typora_${VER_TYPORA}_arm64.deb"; exit 1; }
[ -f "$ARCHIVES/typora-setup-x64-${VER_TYPORA}.exe" ] || { echo "❌ 缺 freearchives/typora-setup-x64-${VER_TYPORA}.exe"; exit 1; }

# ---------- 1. 确定 plugin 源与版本标识 ----------
if [ -n "$PLUGIN_VER" ]; then
  ZIP="$TMP/plugin_dist/typora-plugin@v${PLUGIN_VER}.zip"
  [ -f "$ZIP" ] || { echo "== 下载 typora_plugin v${PLUGIN_VER} =="; dl "$ZIP" "https://github.com/obgnail/typora_plugin/releases/download/${PLUGIN_VER}/typora-plugin@v${PLUGIN_VER}.zip"; }
  D="$TMP/plugin_dist/v${PLUGIN_VER}"
  rm -rf "$D" && mkdir -p "$D"
  (cd "$D" && "$SZ" x -y "$ZIP" >/dev/null)
  PLUGIN_SRC="$D/plugin"
  PLUGIN_TAG="$PLUGIN_VER"
else
  if [ ! -d "$TMP/typora_plugin/.git" ]; then
    echo "== 克隆 typora_plugin 最新代码 =="
    git clone --depth 1 https://github.com/obgnail/typora_plugin.git "$TMP/typora_plugin"
  else
    echo "== 更新 typora_plugin（git pull）=="
    git -C "$TMP/typora_plugin" pull --ff-only 2>/dev/null || echo "  (pull 失败，继续用本地代码)"
  fi
  PLUGIN_SRC="$TMP/typora_plugin/plugin"
  PLUGIN_TAG="$(git -C "$TMP/typora_plugin" log -1 --format=%cd --date=format:%Y%m%d)"
fi
[ -f "$PLUGIN_SRC/index.js" ] || { echo "❌ plugin 源无效: $PLUGIN_SRC"; exit 1; }
echo "✅ plugin 源: $PLUGIN_SRC (标识: $PLUGIN_TAG)"

[ -n "$RELEASE_TAG" ] || RELEASE_TAG="vplugin${PLUGIN_TAG}"
echo "✅ release tag: $RELEASE_TAG"

# ---------- 2. 组装 AppDir（amd64/arm64 同一套逻辑）----------
inject_plugin() {  # $1 = resources/ 目录
  sed -i 's|<script src="./appsrc/window/frame.js" defer="defer"></script>|<script src="./appsrc/window/frame.js" defer="defer"></script><script src="./plugin/index.js" defer="defer"></script>|g' \
    "$1/window.html"
  rm -rf "$1/plugin"
  cp -a "$PLUGIN_SRC" "$1/plugin"
}

write_apprun() {  # $1 = AppDir
  cat > "$1/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "${0}")")"
# 沙箱：setuid 沙箱在 AppImage（FUSE nosuid）下失效；userns 可用则保留
# 沙箱（--disable-setuid-sandbox），否则退回 --no-sandbox。
SANDBOX="--no-sandbox"
if unshare -U true 2>/dev/null; then
  SANDBOX="--disable-setuid-sandbox"
fi
# typora_plugin 配置外置：AppImage 内 resources/ 只读，首次启动把默认配置
# 复制到 ~/.config/typora_plugin/（插件优先读写该路径，不覆盖已有配置）。
PLUGIN_CFG="${HOME}/.config/typora_plugin"
if [ ! -f "${PLUGIN_CFG}/settings.user.toml" ]; then
  mkdir -p "${PLUGIN_CFG}"
  cp -a "${HERE}/usr/share/typora/resources/plugin/global/settings/." "${PLUGIN_CFG}/" 2>/dev/null || true
fi
exec "${HERE}"/usr/share/typora/Typora ${SANDBOX} "$@"
EOF
  chmod +x "$1/AppRun"
}

assemble_appdir() {  # $1=arch(x86_64|aarch64)  $2=deb  $3=AppDir
  local arch="$1" deb="$2" appdir="$3" work="$TMP/work/$1"
  echo "== 组装 AppDir ($arch) =="
  rm -rf "$work" "$appdir"
  mkdir -p "$work" "$appdir/usr"
  (cd "$work" && bsdtar -xf "$deb" && bsdtar -xf data.tar.xz)
  cp -a "$work/usr/." "$appdir/usr/"
  cp "$work/usr/share/applications/typora.desktop" "$appdir/"
  # 自定义名称与构建信息（Name=Typorax；Comment 含 Typora 版本/free/plugin 版本/构建时间/仓库）
  sed -i \
    -e "s|^Name=.*|Name=Typorax|" \
    -e "s|^Comment=.*|Comment=Typora ${VER_TYPORA} free + typora_plugin ${PLUGIN_TAG} · built ${BUILD_TIME} · ${REPO_URL}|" \
    -e "/Change Log/d" \
    "$appdir/typora.desktop"
  cp "$work/usr/share/icons/hicolor/256x256/apps/typora.png" "$appdir/"
  inject_plugin "$appdir/usr/share/typora/resources"
  write_apprun "$appdir"
  rm -rf "$work"
}

# ---------- 3. Linux amd64 AppImage ----------
AMD_APPIMAGE="$BUILD/Typora-${VER_TYPORA}-plugin-${PLUGIN_TAG}-amd64.AppImage"
assemble_appdir x86_64 "$ARCHIVES/typora_${VER_TYPORA}_amd64.deb" "$TMP/Typora-amd64.AppDir"
"$APPIMAGETOOL" "$TMP/Typora-amd64.AppDir" "$AMD_APPIMAGE" >/dev/null 2>&1
echo "✅ $AMD_APPIMAGE"

# ---------- 4. Linux arm64 AppImage ----------
ARM_APPIMAGE="$BUILD/Typora-${VER_TYPORA}-plugin-${PLUGIN_TAG}-arm64.AppImage"
assemble_appdir aarch64 "$ARCHIVES/typora_${VER_TYPORA}_arm64.deb" "$TMP/Typora-arm64.AppDir"
"$APPIMAGETOOL" "$TMP/Typora-arm64.AppDir" "$ARM_APPIMAGE" >/dev/null 2>&1
echo "✅ $ARM_APPIMAGE"

# ---------- 5. Windows x64 zip ----------
echo "== 构建 Windows x64 zip =="
WIN="$TMP/win_extract/app"
if [ ! -f "$WIN/Typora.exe" ]; then
  rm -rf "$TMP/win_extract"
  "$INNOEXTRACT" "$ARCHIVES/typora-setup-x64-${VER_TYPORA}.exe" -d "$TMP/win_extract" >/dev/null 2>&1
fi
inject_plugin "$WIN/resources"
WIN_ZIP="$BUILD/Typora-${VER_TYPORA}-plugin-${PLUGIN_TAG}-amd64.zip"
(cd "$TMP/win_extract" && "$SZ" a -tzip -mx=5 -y "$WIN_ZIP" app/ >/dev/null)
echo "✅ $WIN_ZIP"

# ---------- 6. dmg（仅复制，Linux 无法重新打包）----------
[ -f "$ARCHIVES/Typora-${VER_TYPORA}.dmg" ] && cp "$ARCHIVES/Typora-${VER_TYPORA}.dmg" "$BUILD/"
echo "✅ $BUILD/Typora-${VER_TYPORA}.dmg (未集成 plugin)"

echo ""
echo "========== 构建完成 (tag: $RELEASE_TAG) =========="
ls -lh "$BUILD"
