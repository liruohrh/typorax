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
./pkg2appimage-*.AppImage Typora.yml

# ARM64（必须在 arm64 机器上，或用支持它的容器/交叉环境）
ARCH=aarch64 ./pkg2appimage-*.AppImage Typora.yml
```

产物位于 `out/Typora-0.11.18.glibc2.X-<arch>.AppImage`。

## 配方要点

- 通过 `ingredients.script` 按架构（`$ARCH` 或 `uname -m`）从 GitHub Release 下载对应的
  `typora_0.11.18_amd64.deb` / `typora_0.11.18_arm64.deb`，无需 apt 仓库。
- 该 deb 不声明任何依赖，Electron 所需的系统库（GTK3、NSS、ALSA 等）由运行 AppImage
  的主机提供。
- 自定义 `AppRun`：Electron 的 SUID 沙箱在 AppImage（FUSE 挂载，通常 nosuid）里无法使用，
  因此以 `--no-sandbox` 启动。

## 运行

```bash
chmod +x Typora-0.11.18.*.AppImage
./Typora-0.11.18.*.AppImage
```

注意：`--no-sandbox` 会关闭 Chromium 沙箱（个人使用通常可接受；若在意安全，
建议改用官方 Typora 或等上游提供 AppImage）。
