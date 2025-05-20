# AudioSync

**AudioSync** 是一款专为 macOS 打造的apple music ,usb dac采样位深同步+歌词工具，采用swift+swiftUi完成，绝大部分代码由ai提供😂。 这是一个学习项目，不考虑任何功能新增和bug修复，如使用中有问题请ai帮你修复！！

## 核心功能

- 🎵 **多源歌词获取**：集成网易云、QQ 音乐等平台，自动匹配并抓取歌词
  
  <img width="360" alt="image" src="https://github.com/user-attachments/assets/2f744dce-a968-4adf-be4e-e2be040972b7" />
- 🧠 **日文歌曲智能还原**：处理片假名/罗马音等 J-Pop 曲名，还原正确的原文 (需要调用大模型api，参见fetchOriginalName)
  <img width="862" alt="image" src="https://github.com/user-attachments/assets/3951a77f-f043-4625-89de-bb591b19fd4b" />
- ⚡ **采样率&位深同步**：系统日志读取 采样率 & 位深（找不到更好的方式）
- 🔍 **候选歌词选择策略**：自动匹配严格，如匹配度不高，会弹窗手动选择，选择最合适歌词
  <img width="490" alt="image" src="https://github.com/user-attachments/assets/9fd87db2-d633-496f-81c6-40cd8476f843" />


## 使用说明

## 致谢

本项目部分功能与思路参考了以下优秀开源项目：

- [LyricsX](https://github.com/ddddxxx/LyricsX)
- [LyricFever](https://github.com/aviwad/LyricFever)
