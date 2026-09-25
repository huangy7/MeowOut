<p align="center">
  <img src=".github/assets/app_icon.png" alt="MeowOut Icon" width="128">
</p>

<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/lang-English-blue?style=flat-square" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/lang-简体中文-lightgrey?style=flat-square" alt="简体中文"></a>
</p>

<h1 align="center">MeowOut</h1>

<p align="center">
  <b>A native macOS menu bar toolkit — with a pixel pet that keeps you healthy</b>
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
    <img src="https://img.shields.io/badge/Official_Website-meow.huangy.top-a855f7?style=for-the-badge&labelColor=1d003d" alt="Official Website">
  </a>
  &nbsp;
  <a href="https://meow.huangy.top/#demo">
    <img src="https://img.shields.io/badge/Live_Web_Demo-Try_all_features_in_your_browser-ff7b00?style=for-the-badge&labelColor=1a0a00" alt="Interactive Demo">
  </a>
  &nbsp;
  <a href="https://github.com/huangy7/MeowOut/releases/latest">
    <img src="https://img.shields.io/badge/Download-MeowOut_v1.9.0-0071e3?style=for-the-badge&labelColor=001a3d" alt="Download">
  </a>
</p>

MeowOut packs a clipboard manager, a TOTP authenticator, a dropzone, quick memos, a launcher and a live system monitor into one menu bar app. A pixel pet rides along in the menu bar while you work.

## Contents

- [Features](#features)
  - [Text & Clipboard](#text--clipboard)
  - [Files & Security](#files--security)
  - [System & Hardware](#system--hardware)
  - [Everyday](#everyday)
  - [Health Companion](#health-companion)
- [Installation](#installation)
- [License](#license)

## Features

### Text & Clipboard

- **Clipboard History** — Search, preview and reuse anything you've copied. Plain text, rich text and images are all captured, with instant actions to paste, pin or clear.
- **Quick Memos** — Native Markdown memos with timeline and calendar views, image attachments, and a quick-capture window you can summon without leaving what you're doing.

### Files & Security

- **Dropzone** — A drag-and-drop staging area for files. Drop things in from anywhere, drag them out when you need them, with multi-file staging and preview.
- **2FA Authenticator** — TOTP codes with multiple hash algorithms, with secrets encrypted in the macOS Keychain.

### System & Hardware

- **System Monitor** — Live CPU, memory, network, battery and disk capacity in a translucent panel, with per-process drill-down and a significant-energy ranking.
- **Keep-Awake & Battery Protection** — Prevent sleep with the lid closed, with a customizable battery threshold so a long export doesn't drain you to zero.
- **Cleaning Mode** — Lock keyboard or screen input with a countdown unlock, so wiping things down doesn't fire off shortcuts.

### Everyday

- **Fund Tracker** — Real-time valuation for the funds you follow, in a lightweight floating dashboard with a privacy mode and holding profit calculation.
- **Launcher** — A long-press radial launcher that puts your most frequent actions under the cursor. Configure several rings and switch between them with the scroll wheel.

### Health Companion

- **Pixel Companions** — Clawd the cat, Panda or Pika walk in your menu bar while you work, with live switching and independent animation.
- **Mindfulness** — A five-minute breathing session in a fullscreen immersive view. Completed sessions feed back into your health statistics.

## Installation

### Install via Homebrew (Recommended)

If you have Homebrew installed, install and update through our dedicated tap:

```bash
brew install huangy7/tap/meowout
```

### Download the DMG

1. **[Download the latest MeowOut.dmg](https://github.com/huangy7/MeowOut/releases/latest)**
2. **Remove the quarantine attribute** (required for unsigned apps):
   ```bash
   cd ~/Downloads
   xattr -cr MeowOut*.dmg
   ```
3. **Open** the DMG and drag `MeowOut.app` into your `Applications` folder.

### One-Line Quick Install

```bash
curl -L https://github.com/huangy7/MeowOut/releases/latest/download/MeowOut.dmg -o ~/Downloads/MeowOut.dmg && xattr -cr ~/Downloads/MeowOut.dmg && open ~/Downloads/MeowOut.dmg
```

## License

This project is released under the [MIT](LICENSE) License.

---

<p align="center">
  Developed and maintained by <a href="https://github.com/huangy7">huangy7</a>
</p>
