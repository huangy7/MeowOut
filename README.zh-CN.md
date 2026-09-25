<p align="center">
  <img src=".github/assets/app_icon.png" alt="MeowOut Icon" width="128">
</p>

<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/lang-English-lightgrey?style=flat-square" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/lang-简体中文-blue?style=flat-square" alt="简体中文"></a>
</p>

<h1 align="center">MeowOut</h1>

<p align="center">
  <b>原生 macOS 菜单栏工具箱 —— 附带一只守护健康的像素宠物</b>
  <br>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/huangy7/MeowOut?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square" alt="Swift">
  <a href="https://github.com/huangy7/MeowOut/releases"><img src="https://img.shields.io/github/downloads/huangy7/MeowOut/total?style=flat-square&color=success" alt="Downloads"></a>
  <img src="https://komarev.com/ghpvc/?username=huangy7-MeowOut&label=Views&color=0071e3&style=flat-square" alt="Views">
</p>

<p align="center">
  <img src=".github/assets/hero.gif" alt="MeowOut Hero" width="100%">
</p>

<p align="center">
  <a href="https://meow.huangy.top/">
    <img src="https://img.shields.io/badge/官方网站-meow.huangy.top-a855f7?style=for-the-badge&labelColor=1d003d" alt="官方网站">
  </a>
  &nbsp;
  <a href="https://meow.huangy.top/#demo">
    <img src="https://img.shields.io/badge/在线演示-浏览器里直接试用全部功能-ff7b00?style=for-the-badge&labelColor=1a0a00" alt="在线演示">
  </a>
  &nbsp;
  <a href="https://github.com/huangy7/MeowOut/releases/latest">
    <img src="https://img.shields.io/badge/下载-MeowOut_v1.8.0-0071e3?style=for-the-badge&labelColor=001a3d" alt="下载">
  </a>
</p>

MeowOut 把剪贴板管理、两步验证、文件中转站、快速备忘、快捷启动器和实时系统监控收进同一个菜单栏应用；另有一只像素宠物在菜单栏里陪你工作。

## 目录

- [功能](#功能)
  - [文字与剪贴](#文字与剪贴)
  - [文件与安全](#文件与安全)
  - [系统与硬件](#系统与硬件)
  - [日常](#日常)
  - [健康伴侣](#健康伴侣)
- [安装](#安装)
- [开源协议](#开源协议)

## 功能

### 文字与剪贴

- **剪贴板历史** — 搜索、预览并复用你复制过的任何内容。纯文本、富文本与图片都会记录，可一键粘贴、置顶或清除。
- **快速备忘** — 原生 Markdown 备忘，支持时间线与日历双视图、图片附件，以及不必离开当前工作就能唤起的速记窗口。

### 文件与安全

- **文件中转站** — 拖拽式的文件暂存区。随手拖入、需要时再拖出，支持多文件暂存与预览。
- **两步验证** — 支持多种哈希算法的 TOTP 验证码，密钥加密存放在 macOS 钥匙串中。

### 系统与硬件

- **系统监控** — 半透明面板实时显示 CPU、内存、网络、电池与磁盘容量，可下钻到进程，并列出显著耗能排行。
- **合盖常亮与电池保护** — 合上盖子也不休眠，可设定电量下限，长时间导出不会把电池耗到见底。
- **清洁模式** — 一键锁定键盘或屏幕输入并倒计时解锁，擦屏幕时不会误触快捷键。

### 日常

- **基金看板** — 实时估值跟踪你关注的基金，轻量悬浮面板，支持隐私模式与持仓收益计算。
- **快捷启动器** — 长按唤出环形启动器，把高频操作放到光标下；可配置多个圆环，用滚轮切换。

### 健康伴侣

- **像素宠物** — 猫、熊猫或皮卡在菜单栏里陪你工作，可随时切换，各自独立动画。
- **正念练习** — 五分钟呼吸练习，全屏沉浸式交互，完成后自动计入健康统计。

## 安装

### 使用 Homebrew 安装（推荐）

如果你已经装了 Homebrew，可以通过专属 tap 安装与更新：

```bash
brew install huangy7/tap/meowout
```

### 下载安装包

1. **[下载最新的 MeowOut.dmg](https://github.com/huangy7/MeowOut/releases/latest)**
2. **移除隔离属性**（未签名应用需要）：
   ```bash
   cd ~/Downloads
   xattr -cr MeowOut*.dmg
   ```
3. **打开** DMG，把 `MeowOut.app` 拖进 `Applications` 文件夹。

### 极速一键安装

```bash
curl -L https://github.com/huangy7/MeowOut/releases/latest/download/MeowOut.dmg -o ~/Downloads/MeowOut.dmg && xattr -cr ~/Downloads/MeowOut.dmg && open ~/Downloads/MeowOut.dmg
```

## 开源协议

本项目基于 [MIT](LICENSE) 协议开源。

---

<p align="center">
  由 <a href="https://github.com/huangy7">huangy7</a> 开发与维护
</p>
