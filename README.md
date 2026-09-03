# Windows 压缩包

这是一个 macOS 小工具，用来生成复制到 Windows 后解压更干净的 ZIP。

应用图标设计稿：`WindowsZip-icon.svg`，正式 macOS 图标：`WindowsZip.app/Contents/Resources/WindowsZipIcon.icns`。图形用蓝色文件夹、银色拉链和清理闪光表达“干净打包”，没有文字，缩小后也能识别。

它会自动排除这些 macOS Finder 元数据：

- `.DS_Store`
- `__MACOSX/`
- `._*` AppleDouble 文件
- `.localized` 以及常见的 Finder/系统元数据目录

正常的隐藏文件和普通业务后缀不会被全部排除，例如 `.env`、`.mac` 都会保留。

## 最简单的用法

双击已安装的 App：

```text
/Applications/WindowsZip.app
```

选择文件或文件夹后，应用会自动在源文件旁生成 `原名-Windows.zip`。也可以把文件/文件夹拖到：

```text
WindowsZip.command
```

生成的 ZIP 可以直接复制到 Windows 解压。

压缩成功后，应用会自动打开 Finder 并定位刚生成的 ZIP 文件。

现在压缩核心已经内置在 `/Applications/WindowsZip.app` 中，可以直接从 Launchpad 使用。应用会显示在 Dock 中，方便频繁启动和退出。

拖拽使用时，请从 Finder 选中一个文件或文件夹，拖到 Finder 中的 `WindowsZip.app` 或 Dock 图标；不要拖到 Launchpad 页面本身。现在 App 已直接接收 macOS 的文件打开事件，不需要先打开 App 再拖进去。一次拖入一个文件或文件夹即可。

这个应用不是常驻后台程序：每次启动只处理一次，完成后自动退出。取消选择、关闭对话框或应用收到中断信号时，会清理正在运行的压缩子进程，不会留下后台压缩任务。

## 命令行用法

```bash
python3 mac_clean_zip.py "/path/to/要压缩的文件夹"
```

默认在源文件旁生成 `原名-Windows.zip`。指定输出文件：

```bash
python3 mac_clean_zip.py \
  "/path/to/要压缩的文件夹" \
  --output "/path/to/交付-Windows.zip" \
  --overwrite
```

运行报告会写到 `~/Library/Logs/MacWindowsZip/`。

## 第一次打开提示

如果 macOS 提示应用来自未知开发者，在 Finder 中右键 `WindowsZip.app`，选择“打开”；或者双击 `WindowsZip.command`。
