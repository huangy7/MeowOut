# MeowOut

<p align="center">
  <b>一只奔跑的像素小猫，守护你的颈椎健康</b>
  <br>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/huangy7/MeowOut?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square" alt="Swift">
</p>

<p align="center">
  <img src=".github/assets/hero.gif" alt="MeowOut Hero" width="800">
</p>

MeowOut 是一款 macOS 原生菜单栏应用，用一只奔跑的像素小猫提醒你按时休息。它通过系统底层接口精准检测用户活跃度，根据连续工作时长自动进入预警或强制休息阶段，是开发者预防颈椎病和保持健康的贴心伙伴。


## ✨ 核心特性

| 特性 | 说明 |
| :--- | :--- |
| **动感托盘小猫** | 复刻 RunCat 经典动画，根据工作状态实时切换奔跑与静止，支持状态染色。 |
| **硬核防沉迷算法** | **时光回滚**: 精准扣除起座初期的“幽灵时间”。<br>**满血复活**: 自定义休息阈值，只有真正歇够了，工作循环才会重置。 |
| **强制休息遮罩** | 采用绝对坐标追踪，弹出极高层级的无边框全屏“巨型猫咪”遮罩，强制拦截用户操作。 |
| **全方位健康统计** | 独立统计面板，包含每日目标进度条及 **7 天工作历史趋势图**。 |


## 🕰 监测逻辑说明

MeowOut 采用一套精密的活跃度判定逻辑，确保对你工作状态的追踪既准确又人性化：

- **如何定义“在工作”？**
  - **实时采样**：系统每 5 秒检测一次全局输入活动（键鼠操作）。
  - **活跃判定**：只要连续无操作时间（Idle Time）小于约 2 分钟（Rollback Threshold），即认为你处于活跃工作状态。
  - **状态演进**：累计工作时间达到预警阈值（默认 40 分钟）时，小猫会切换台词提醒；达到最大时长（默认 45 分钟）时，强制进入休息模式。

- **如何定义“在休息”？**
  - **强制休息**：进入休息模式后，系统开始 5 分钟的倒计时。
  - **轻度容错**：目前设计允许在休息期间进行低强度的鼠标操作（如翻阅文档），倒计时不受干扰。

- **如何判定“休息够了”？（重置逻辑）**
  - **倒计时结束**：完成 5 分钟休息倒计时后，工作计时自动归零。
  - **自然挂机 (Idle Reset)**：如果完全不操作电脑超过 5 分钟，系统自动判定你已起座休息，重置工作计时。
  - **休眠重置 (Sleep Reset)**：电脑进入合盖/休眠状态时长超过 5 分钟，唤醒后将重新开始计时。
  - **时光回滚 (Rollback)**：如果挂机超过 2 分钟 but 未达重置标准，系统会从累计时长中扣除这段挂机时间，防止因接电话或短暂交谈导致的计时虚高。


## 🚀 安装指南 (Installation)

### 下载安装包 (推荐) ⭐️

1. **[下载最新的 MeowOut.dmg](https://github.com/huangy7/MeowOut/releases/latest)**
2. **移除隔离属性** (未签名的应用需要执行此操作):
   ```bash
   cd ~/Downloads
   xattr -cr MeowOut*.dmg
   ```
3. **打开** 下载好的 DMG 文件
4. **拖拽** `MeowOut.app` 到你的 `应用程序 (Applications)` 文件夹
5. **启动**: 
   ```bash
   open /Applications/MeowOut.app
   ```
6. 在你的状态栏寻找那只**奔跑的小猫 🐱**！

> **⚠️ 为什么需要终端命令？** 本应用目前没有使用 Apple 开发者证书（每年 $99）进行签名。  
> macOS 默认会拦截未签名的下载文件，所以你需要先手动移除文件的隔离标签才能正常运行。

### 极速一键安装 (Quick One-Line Install)

打开终端 (Terminal)，直接粘贴并运行以下一键脚本。它会自动下载最新版本、解除系统拦截并打开安装窗口：

```bash
curl -L https://github.com/huangy7/MeowOut/releases/latest/download/MeowOut.dmg -o ~/Downloads/MeowOut.dmg && xattr -cr ~/Downloads/MeowOut.dmg && open ~/Downloads/MeowOut.dmg
```

随后只需将应用拖入 `Applications` 文件夹即可！

### 开发者：从源码编译

#### 系统要求
- macOS 14.0 或更高版本
- 已安装 Xcode 或 Command Line Tools

#### 编译与运行
```bash
# 克隆项目
git clone https://github.com/huangy7/MeowOut.git
cd MeowOut

# 编译并直接运行
swift run
```

#### 专业打包 (生成 DMG)
```bash
./scripts/build-dmg.sh
```


## 🛠️ 技术栈
- **UI 框架**: SwiftUI (现代声明式 UI)
- **底层架构**: AppKit (NSPanel 物理窗口控制)
- **状态管理**: Swift Observation (@Observable)
- **工程管理**: XcodeGen + 纯 SwiftPM 混合架构
- **本地化**: 标准 .strings 国际化方案


## 📂 项目结构
```text
Sources/MeowOut/
  AppState.swift              # 全局状态管理与持久化
  PetState.swift              # 像素猫逻辑状态与动画引擎
  ActivityMonitor.swift       # 活动检测与回滚算法
  CatOverlayController.swift  # 双窗口同步与全屏遮罩引擎
  SettingsView.swift          # 统计面板与个性化设置 UI
  I18n.swift                  # 国际化运行时加载器
  DialogueManager.swift       # 多性格台词路由
  Assets.xcassets             # 像素猫动画素材库
scripts/build-dmg.sh          # Xcodebuild 自动化发布流水线
```


## ⚖️ 开源协议

本项目采用 [MIT](LICENSE) 协议。

---

<p align="center">
  由 <a href="https://github.com/huangy7">huangy7</a> 开发并维护
</p>
