# Typora 0.11.18 (free) AppImage

用 [pkg2appimage](https://github.com/AppImageCommunity/pkg2appimage) 把 Typora 免费版
(0.11.18, Electron 13) 的 `.deb` 转成 AppImage。

## 依赖

- [pkg2appimage](https://github.com/AppImageCommunity/pkg2appimage/releases) 的 AppImage
  （它自带 dpkg-deb、appimagetool 等工具，不需要在本机装这些）。

## 构建

```bash
# 下载 pkg2appimage
wget -c $(wget -q https://api.github.com/repos/AppImageCommunity/pkg2appimage/releases -O - \
  | grep "pkg2appimage-.*-x86_64.AppImage" | grep browser_download_url | head -n 1 | cut -d '"' -f 4)
chmod +x ./pkg2appimage-*.AppImage

# x86_64
./pkg2appimage-*.AppImage recipes/Typora.yml

# ARM64（必须在 arm64 机器上，或用支持它的容器/交叉环境）
ARCH=aarch64 ./pkg2appimage-*.AppImage recipes/Typora.yml
```

产物位于 `out/Typora-0.11.18.glibc2.X-<arch>.AppImage`。

## 配方要点

- 通过 `ingredients.script` 按架构（`$ARCH` 或 `uname -m`）从 GitHub Release 下载对应的
  `typora_0.11.18_amd64.deb` / `typora_0.11.18_arm64.deb`，无需 apt 仓库。
- 该 deb 不声明任何依赖，Electron 所需的系统库（GTK3、NSS、ALSA 等）由运行 AppImage
  的主机提供。
- 自定义 `AppRun`：以 `--no-sandbox` 启动（Electron 的 SUID 沙箱在 AppImage 的 FUSE
  挂载下无法工作）。AppRun **不设置任何输入法环境变量、不修改任何用户配置**——
  会话里已有的 `GTK_IM_MODULE`/`XMODIFIERS` 等会自然继承（ibus/fcitx 用户各得
  其所），没有则交给 GTK 默认行为或下方脚本写入的配置文件。

## 运行

```bash
chmod +x Typora-0.11.18.*.AppImage
./Typora-0.11.18.*.AppImage
```

## 输入法（fcitx5 / ibus）配置

Typora 0.11.18 是 Electron 13（Chrome 91），原生 Wayland **不支持 IME**（Chromium 98
才支持），因此 AppImage 保持 X11/XWayland 渲染。输入法集成是**主机层面的配置**，
不会在 AppImage 运行时自动改动，需要你手动执行一次脚本：

```bash
./setup-input-method.sh            # 自动检测 fcitx5 / ibus 并写入配置
./setup-input-method.sh fcitx      # 手动指定 fcitx
./setup-input-method.sh ibus       # 手动指定 ibus
./setup-input-method.sh --dry-run  # 只预览改动，不写入
```

脚本做的事：

1. 检测当前输入法框架（fcitx5 / ibus 进程，GNOME 默认 ibus）。
2. 检查系统是否装了对应的 GTK3 im module（fcitx 需 `fcitx5-gtk`，ibus 需
   `ibus-gtk3`），缺失时给出安装命令。
3. 在 `~/.config/gtk-3.0/settings.ini` 的 `[Settings]` 段写入
   `gtk-im-module=<fcitx|ibus>`（已有其他值时先询问确认，不盲目覆盖）。

为什么必须用配置文件而不是环境变量？实测 **Typora 0.11.18 二进制启动时会丢弃
AppRun 里 export 的环境变量**（`/proc/<pid>/environ` 中查不到 `GTK_IM_MODULE` 等），
所以环境变量方案对 Typora 无效。另外，大多数 Linux 会话默认不会设置
`GTK_IM_MODULE` 等变量，AppRun 里若默认写死 `fcitx` 反而会误伤 ibus 用户，因此
AppRun 不做任何输入法假设。GTK3 在 X11/XWayland 下始终读取
`~/.config/gtk-3.0/settings.ini`（fcitx 官方推荐方案），不受此影响。

注意事项：

- 不要给 AppRun 加 `--ozone-platform=wayland` / `--enable-wayland-ime`：在
  Electron 13 上会导致输入法完全失效（Chromium 98 之前的已知限制）。
- GNOME Wayland 下若候选框不显示，可安装
  [gnome-shell-extension-kimpanel](https://extensions.gnome.org/extension/261/kimpanel/)
  扩展（Wayland 下 fcitx5 的弹出窗口需要合成器支持）。
- KDE Plasma Wayland（本机）一般无需额外配置。

注意：`--no-sandbox` 会关闭 Chromium 沙箱（个人使用通常可接受；若在意安全，
建议改用官方 Typora 或等上游提供 AppImage）。
