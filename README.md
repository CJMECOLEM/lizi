# 扫码识字

一个简洁的 iOS 扫描应用：连续识别一维条码，以及取景框内的数字和中文文字，暗处自动打开闪光灯。

## 功能

- **条码模式**：整个画面连续识别一维条码（EAN-13/8、UPC-A/E、Code 128/39/93、Codabar、ITF）。
- **文字模式**：只识别取景框内的文字，支持中文和数字，在手机本地完成（Google ML Kit）。
- **计数规则**：同一内容需要离开画面、再次出现，才会再计数一次。连续 2 帧都识别到才算有效，用来过滤误识别。
- **暗光**：画面持续变暗约 1.2 秒后，自动打开闪光灯。你手动关闭后，本次扫描期间不会再自动打开。
- **反馈**：每次计数时震动一下。
- **结果**：点击条目即可复制，也可以分享；"复制全部"会把每项内容放在单独一行。
- **历史**：保存在本地，支持搜索；左滑删除，长按可以复制、分享或删除。
- **导出**：在历史页右上角选择导出 Excel 或 CSV，再通过系统分享面板发送。

## 目录结构

```
lib/
  main.dart                 应用入口和底部导航
  pages/                    扫描、历史、设置三个页面
  scan/                     识别逻辑（去重计数、亮度/闪光灯、取景框坐标、帧转换）
  services/                 历史数据库、设置、导出
  models/scan_record.dart
.github/workflows/build-ios.yml   云端编译 iOS 安装包
```

## 本地开发（Windows）

```powershell
flutter pub get
flutter analyze
flutter test
```

在 Windows 上无法编译 iOS 安装包，这一步交给 GitHub Actions 完成。

## 编译 iOS 安装包

1. 把这个文件夹推送到 GitHub 仓库的 `main` 分支。
2. GitHub Actions 会自动运行 **Build iOS (unsigned IPA)**，也可以在 Actions 页面手动运行。
3. 运行完成后，在运行详情页底部下载 `lizi-unsigned-ipa`，解压得到 `lizi-unsigned.ipa`。

> 私有仓库使用 macOS 运行环境会按 10 倍速度消耗免费额度，每次编译大约 10–20 分钟；公开仓库不受限制。

## 用 Sideloadly 安装到 iPhone

1. 在 Windows 上安装 [Sideloadly](https://sideloadly.io/)，以及**从苹果官网下载**的 iTunes 和 iCloud（不要用 Microsoft Store 版本）。
2. 用数据线连接 iPhone，在手机上点"信任此电脑"。
3. 打开 Sideloadly，把 `lizi-unsigned.ipa` 拖进去，输入你的 Apple ID，然后点 Start。
4. 在 iPhone 上：
   - iOS 16 及以上：打开 **设置 › 隐私与安全性 › 开发者模式**，开启后重启手机。
   - 打开 **设置 › 通用 › VPN 与设备管理**，信任你的 Apple ID 对应的开发者。
5. 打开"扫码识字"，允许访问相机。

使用免费 Apple ID 签名的应用 **7 天后失效**，需要重新用 Sideloadly 安装一次，历史记录会保留。付费开发者账号签名的有效期为 1 年。

## 后续计划

- 第二阶段：对识别不准的文字，点一下即可调用百度云 OCR 做精确识别。
