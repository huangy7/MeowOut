# 🐾 MeowOut 官网 Vercel 部署与维护手册

本笔记记录了为 macOS 原生菜单栏应用 **MeowOut** 构建官方介绍落地页（Landing Page）并将其部署到 **Vercel** 全球托管平台的全过程。

---

## 📖 背景与目的

* **项目名称**：MeowOut (一只奔跑的像素健康伴侣)
* **需求**：为项目构建一个现代且极具吸引力的展示官网，包含功能特性、安装命令、DMG 下载，并能够让访问者在网页端直接交互体验 App 的原型（以减少转化流失）。
* **技术选型**：使用纯原生 HTML5/CSS3/JavaScript 构建静态单页，利用 Vercel 提供的 Git 联动实现快速发布与全球 CDN 加速。

---

## 🎨 第一部分：网页设计与实现

为了匹配 macOS 现代化原生应用的极客质感，网页采用了以下设计标准：

1. **视觉体系 (Sleek Dark Mode)**：
   * **背景**：采用深色放射渐变（`#06060c` 至 `#1e1145`），营造星空及科技感。
   * **字体**：引入 Google Fonts 中的 `Outfit`（用于粗体标题）和 `Inter`（用于高易读性正文）。
   * **图标**：纯 inline SVG 设计（例如 Navbar 的渐变猫爪 logo），零文件依赖，秒开且支持无损缩放。
2. **核心板块划分**：
   * **Hero 头部**：醒目的标题 + 状态栏 + 动态展示图（`.github/assets/hero.gif`）。
   * **功能特性网格 (Features Grid)**：6 张玻璃微光质感的卡片，包含光标悬停时的跟随发光（Glow tracker）特效。
   * **在线试用区 (Interactive Simulator)**：使用 `iframe` 嵌入现有的 `docs/promo_mockup.html`。针对移动端，通过 JS resize 监听器实现了对 iframe 的等比例 CSS 缩放（`transform: scale()`），防止溢出。
   * **安装指南**：支持一键复制 CLI 安装脚本的命令框，并提供 ARM64 (Apple Silicon) 与 x86_64 (Intel) 双版本下载按钮。

---

## 🚀 第二部分：Vercel 部署步骤

Vercel 提供了最顺畅的静态网页部署流程，过程如下：

### 1. 代码提交与推送
首先将新建的网页文件提交到 GitHub 仓库：
```bash
git add index.html
git commit -m "docs: 新增项目官方介绍落地页与在线试用原型"
git push origin main
```

### 2. 控制台导入项目
1. 登录 [Vercel 官网](https://vercel.com)。
2. 点击 **Add New...** -> **Project**。
3. 连接 GitHub 账号，找到 `MeowOut` 仓库，点击 **Import**。

### 3. 配置参数（保持默认）
由于是纯静态网页，配置非常简单：
* **Framework Preset (框架预设)**: 选择 `Other` (自动识别)。
* **Root Directory (根目录)**: 保持为 `./`（因为 `index.html` 就在仓库根目录下）。
* **Build Command / Output Directory**: 留空（静态网页无需构建打包）。

### 4. 发布上线
点击 **Deploy** 按钮。Vercel 会在 10 秒内拉取代码，生成类似 `meow-out.vercel.app` 的免费二级域名并发布上线。

---

## 🌐 第三部分：进阶：绑定自定义域名 (Custom Domains)

如果需要绑定独立域名（例如 `meowout.indiehackertools.net`）：

1. **在 Vercel 中添加域名**：
   * 进入 Vercel 的项目后台，依次点击 **Settings** -> **Domains**。
   * 输入你的域名，点击 **Add**。
2. **配置 DNS 解析**：
   * 登录你的域名解析服务商后台（如 Cloudflare, 阿里云等）。
   * 添加一条解析记录：
     * **类型**：`CNAME`
     * **主机记录 (Name)**：你的子域名（如 `meowout`）
     * **记录值 (Value)**：`cname.vercel-dns.com`
3. **完成证书配置**：
   * 解析生效后，Vercel 会自动为域名签发并续期免费的 SSL 证书，实现 HTTPS 安全访问。

---

## 🔄 第四部分：后续维护与持续集成 (CI/CD)

Vercel 内置了完美的自动化工作流：
* **生产发布**：每当向 `main` 分支 push 代码，Vercel 会在后台自动执行构建并热更新线上网页，无需手动干预。
* **预览发布**：如果拉取了新的分支或提交了 Pull Request，Vercel 会自动生成一个临时的测试预览地址，方便在合并到主分支前确认网页效果。
