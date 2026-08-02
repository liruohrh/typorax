# Typora 0.11.18 (free) + typora_plugin

Typora 0.11.18（最后一个免费版，Electron 13）集成
[typora_plugin](https://github.com/obgnail/typora_plugin)，自动构建发布
Linux amd64/arm64 AppImage + Windows x64 zip + macOS dmg。

## 目录结构

```
freearchives/              原始包（Git LFS 管理）：deb（amd64/arm64）、Windows exe、dmg、zip
build.sh                   统一构建脚本（本地与 CI 相同流程）
.github/workflows/release.yml   GitHub Action：定时 + 手动发布
build/                     构建产物（gitignore）
tmpapps/                   工作目录（gitignore）：工具、plugin 源码、解包缓存
```

## Git LFS

`freearchives/` 下的原始包（约 222MB）用 [Git LFS](https://git-lfs.com) 管理，
clone 前需要注册 LFS（每台机器一次）：

```bash
git lfs install   # 注册 LFS filter（写入 ~/.gitconfig）
git clone git@github.com:liruohrh/typorax.git
```

未注册时 clone 会得到 LFS 指针文件（几十字节）而非真实大文件；已 clone 的可
`git lfs pull` 补齐。GitHub 免费配额：1GB 存储 + 1GB/月带宽。

## 本地构建

```bash
./build.sh                     # 插件用最新代码（git 最新 commit 日期命名）
./build.sh 1.19.0              # 插件用指定版本（下载 typora-plugin@v1.19.0.zip）
./build.sh 1.19.0 -t vplugin-x # 同时指定自定义 release tag
```

产物在 `build/`，命名 `Typora-0.11.18-plugin-{插件版本|commit日期}-{amd64|arm64}.{AppImage|zip}`。

## GitHub Action 自动发布

`.github/workflows/release.yml`：

- **定时**（每天 UTC 0:30）：检测 obgnail/typora_plugin 最新 release，有新版则构建并发布，tag `vplugin{插件版本}`（如 `vplugin1.19.0`）
- **手动**（workflow_dispatch）：可手动指定 `plugin_version` 和自定义 `release_tag`
- 已存在的 tag 自动跳过；产物 `build/` 全部挂到 release

## 关键实现

| 项目 | 说明 |
|---|---|
| 构建 | amd64/arm64 同一套 AppDir 组装逻辑 + appimagetool（自动下载对应架构 type2-runtime） |
| 插件集成 | `window.html` 注入 `<script src="./plugin/index.js">` + 复制 `plugin/` 到 `resources/`（参考 typora-free-with-plugin PKGBUILD） |
| 沙箱 | AppImage 挂载 nosuid，setuid 沙箱失效；AppRun 检测 userns，可用则 `--disable-setuid-sandbox`（保留沙箱），否则 `--no-sandbox` |
| 配置外置 | 插件优先读写 `~/.config/typora_plugin/`；AppRun 首次启动复制默认配置过去（AppImage 内 resources/ 只读，否则报 EROFS） |
| Windows zip | Inno Setup exe 用 innoextract 解包 → 注入插件 → 7-Zip 重新打包 |
| dmg | 仅原样携带（Linux 无法重新打包 dmg，7-Zip 对 dmg 只读） |

## 输入法（fcitx5 / ibus）

Typora 0.11.18 原生 Wayland 不支持 IME（Chromium 98 前的限制），保持 X11/XWayland
渲染。若 fcitx5/ibus 无法输入，按以下两步在主机上配置（实测 Typora 二进制会丢弃
AppRun 里 export 的环境变量，故用 GTK 配置文件而非环境变量）：

1. 安装对应 GTK 前端模块：Arch/CachyOS `sudo pacman -S fcitx5-gtk`（ibus 则 `ibus`）
2. 在 `~/.config/gtk-3.0/settings.ini` 的 `[Settings]` 段写入
   `gtk-im-module=fcitx`（ibus 用户写 `ibus`），然后重启 Typora
