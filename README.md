# 🎤 语音（yuyin）

**点一下按钮说话，文字自动出现在你正在用的任何程序里。**
免费、可离线、不用写任何代码。专为 Linux（Linux Mint Xfce / X11）制作，适合手不稳、头晕、视力不好、不方便打字的人。

> English summary: a one-click voice-to-text desktop app for Linux (X11). Click, speak, and the text is pasted into whatever window you were using. It runs offline with Whisper, and can optionally use Groq / Gemini cloud speech recognition with automatic fallback to local.

---

## 🔗 快速链接

| 我想…… | 点这里 |
|---|---|
| 马上安装 | [⬇️ 一键安装](#-一键安装) |
| 学会怎么用 | [📖 使用方法](#-使用方法) |
| 申请免费 Groq 密钥 | [console.groq.com/keys](https://console.groq.com/keys) |
| 申请免费 Gemini 密钥 | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |
| 遇到问题 | [🛠 常见问题](#-常见问题) |
| 卸载 | [🗑 卸载](#-卸载) |
| 了解原理 | [⚙️ 工作原理](#️-工作原理) |

---

## ✨ 功能

- **一个按钮**：点一下开始说话，再点一下出字，自动复制，还能自动粘贴到刚才用的窗口。
- **三种识别方式**
  - **本地**：完全离线，免费不限量，声音不上传。
  - **云端**：速度快，支持 Groq 和 Gemini 两家，需要自己的免费密钥。
  - **自动**：先试首选云端，失败换另一家，都失败才用本地，不会中断。
- **边说边识别**：本地模式每说完一句就先识别一句，说完后等待更短；说话时还有灰色实时预览。
- **三档精度**：快 / 标准 / 高，旧电脑可以选快，想更准选高。
- **一键清除重说**：按「🗑 清除」，窗口清空，刚才粘贴出去的字也会被退格删掉。
- **常用词**：把常说的词填进去，减少同音字错误。
- **深色圆角小窗口**，半透明，置顶，不挡事。
- **右键菜单**：输入框支持右键 剪切 / 复制 / 粘贴 / 全选。
- **所有文件都在一个文件夹**：`~/语音`，包括虚拟环境，卸载只需一条命令。

## 📸 截图

> <img width="1280" height="800" alt="截图_2026-11-18_11-13-11" src="https://github.com/user-attachments/assets/4651c27a-31c1-4a8c-987b-74cab72e5e46" />


---

## ⬇️ 一键安装

**系统要求**：Linux Mint Xfce（或其他使用 **X11** 的桌面），能上网（第一次要下载组件和模型）。

**方法一：下载后安装**

1. 在本页点击 `yuyin-install.sh`，再点右上角的下载按钮。
2. 在文件所在的文件夹右键，选「在此处打开终端」。
3. 运行：

```bash
bash yuyin-install.sh
```

**方法二：用命令一步下载**

> 把下面的 `你的用户名` 和 `仓库名` 换成这个仓库的真实名字。

```bash
wget https://raw.githubusercontent.com/你的用户名/仓库名/main/yuyin-install.sh
bash yuyin-install.sh
```

安装过程会：

- 要求输入一次开机密码（用来安装 `python3-tk`、`xclip`、`xdotool` 等系统组件）；
- 在主文件夹创建 `~/语音`，把程序和虚拟环境 `venv` 都放进去；
- 在桌面和开始菜单生成「语音」图标。

第一次安装需要几分钟，识别模型会在第一次使用时下载：`快` 约 140 MB、`标准` 约 460 MB、`高` 约 1.5 GB（大小为估计值）。

装好后，**双击桌面上的「语音」图标**就能用。

**更新**：下载最新的 `yuyin-install.sh`，再运行一遍 `bash yuyin-install.sh`，会覆盖更新，你的设置和密钥会保留。

---

## 📖 使用方法

1. 点击窗口里的绿色大按钮，开始说话。
2. 说完，再点一次（按钮会变红）。
3. 文字出现在窗口里，**已自动复制**；如果打开了「识别完自动粘贴」，还会直接打进你刚才用的窗口。
4. 说错了？点右边的「🗑 清除」，然后重说。

### ⚙ 设置里的选项

| 选项 | 说明 |
|---|---|
| 识别方式 | 本地 / 自动 / 云端 |
| 先试哪个云端服务 | Groq 或 Gemini，失败会自动换另一家 |
| 密钥 | 两家的密钥可以同时填，打开「显示密钥」可核对 |
| 本地识别精度 | 快（base）/ 标准（small）/ 高（medium），越高越准也越慢 |
| 实时预览 | 说话时是否显示灰色预览字幕 |
| 常用词 | 用逗号隔开，例如 `去除, 背景, 黑框` |

设置会自动保存在 `~/语音/settings.json`。

### ☁️ 怎么申请云端密钥（可选，免费）

| 服务 | 申请地址 | 说明 |
|---|---|---|
| Groq | [console.groq.com/keys](https://console.groq.com/keys) | 使用 Whisper 语音识别模型，速度快 |
| Gemini | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | 用谷歌账号登录即可创建 |

> ⚠️ 免费额度和规则由各家服务商决定，**可能随时变化**，请以官网为准。
> 云端模式会把你的**声音上传**给服务商。涉及病历、银行、证件等隐私内容，请使用**本地模式**。
> 模型名称如果被服务商停用，程序会自动查询并换成当前可用的模型。

---

## 🛠 常见问题

**双击图标后还是旧界面？**
说明装的是旧版安装包。下载最新的 `yuyin-install.sh`，重新运行 `bash yuyin-install.sh`，再把还开着的窗口关掉重新打开。

**自动粘贴时弹出「无法启动操作」？**
当前窗口是文件管理器（如 Thunar）时，Ctrl+V 的意思是「粘贴文件」，所以报错。在这种窗口里请把「识别完自动粘贴」关掉，文字照样会复制，手动粘贴即可。

**在终端里粘贴不出来？**
终端要用 `Ctrl+Shift+V`，自动粘贴在终端里可能无效。

**识别很慢？**
本地识别靠电脑的 CPU，旧电脑会比较慢。可以：设置里改用「快」或「标准」精度；关掉灰色实时预览；改用「自动」或「云端」模式。

**同音字识别错了（例如「去除」变成「驱除」）？**
在设置的「常用词」里填上这些词；精度选「高」会更准；一次说完整的句子比说单个词更准。

**云端识别失败？**
窗口上会显示是哪一家失败、原因是什么（如额度用完、没网、密钥不对、所在地区不支持）。「自动」模式下失败会自动换另一家，再失败才用本地。

**启动时报「Illegal instruction（非法指令）」？**
你的 CPU 可能太旧，不支持预编译组件所需的指令。可以改用 [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 等在本机编译的方案（本项目暂未内置）。

**Wayland 能用吗？**
自动粘贴依赖 `xdotool`，只能在 **X11** 下工作。Wayland 下识别和复制仍然可用，但自动粘贴和「清除」删字可能无效。

---

## 🗑 卸载

在安装包所在的文件夹运行：

```bash
bash yuyin-install.sh uninstall
```

会删除 `~/语音` 文件夹（程序、虚拟环境、设置）以及桌面和开始菜单的图标，不留残余。也可以手动删除 `~/语音` 文件夹。

---

## ⚙️ 工作原理

1. 麦克风录音（`sounddevice`）。
2. **本地模式**：用开源的 [Whisper](https://github.com/openai/whisper) 模型，通过 [faster-whisper](https://github.com/SYSTRAN/faster-whisper) 在你自己的电脑上识别。说话时，每个停顿（约 0.7 秒）就先识别一句，没说完的部分用小模型显示灰色预览。
3. **云端模式**：把录音发给 Groq 或 Gemini 的接口识别。
4. 识别后用 `xclip` 复制，再用 `xdotool` 切回原窗口并模拟 `Ctrl+V` 粘贴。
5. 界面使用 [CustomTkinter](https://github.com/TomSchimansky/CustomTkinter)。

---

## 📁 文件结构

```
yuyin-install.sh   ← 唯一需要的文件，内含程序、图标和安装/卸载逻辑
README.md          ← 本说明
```

安装后：

```
~/语音/
├── yuyin.py        程序
├── yuyin.svg       图标
├── settings.json   设置（含密钥，仅自己可读，未加密）
└── venv/           独立的 Python 环境
```

## ⚠️ 说明与限制

- 已在 Linux Mint Xfce（X11）上测试。其他发行版或桌面环境未必完全相同。
- 这是辅助输入工具，**不是医疗器械**；识别结果可能出错，重要内容（药品剂量、金额、证件号码等）请再人工确认。
- 密钥保存在 `~/语音/settings.json`，权限为仅本人可读，但**没有加密**，请勿在公用电脑上保存。

## 🙏 致谢

- [OpenAI Whisper](https://github.com/openai/whisper)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- [CustomTkinter](https://github.com/TomSchimansky/CustomTkinter)
- [xdotool](https://github.com/jordansissel/xdotool)、[xclip](https://github.com/astrand/xclip)

## 📄 许可证

> 请在发布前补充，例如 MIT。在仓库页面点 **Add file → Create new file**，文件名输入 `LICENSE`，右侧会出现许可证模板可以直接选用。
