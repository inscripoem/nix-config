# Rime 输入法在 NixOS 上的声明式管理

> 2026-07 · 调研结论 + 实施方案 + 操作手册

## 选型理由

### 为什么放弃了微信输入法 / 搜狗输入法

- **微信输入法**（Weixin Input Method）截至 2026-07 仅有 Windows 2.1.0 / macOS 2.2.0，**没有 Linux 版**。网上误传源自微信通讯软件（WeChat）Linux 4.0——那是聊天软件，不是输入法。
- **搜狗输入法 Linux 版**虽然仍在更新（2026-06 发布 16.6），但底层基于 **fcitx4**，在 Wayland（KDE Plasma 6 / niri / Hyprland）下候选框闪烁、无法正常输入。且与 fcitx5 冲突，需要卸载后者。**在现代桌面环境没有可用性。**

### 为什么选了万象拼音（rime-wanxiang）

裸 Rime（luna_pinyin）有两个核心痛点：
1. **词序不够现代**——静态词典权重，单字母简拼（如 `l` → 第一候选永远「里」而不是「了」）无法通过用户词频学习改变
2. **长句不够自然**——没有 ngram 语言模型，上下文预测弱

对比了三种 Rime 现代方案：

| 方案 | 词库构建 | ngram 语言模型 | 单字母置顶 | 社区活跃度 |
|------|---------|--------------|----------|-----------|
| **雾凇拼音**（rime-ice） | 人工精校 + 腾讯词向量 | 选配（需手动挂 LTS） | 内置 pin_cand_filter.lua | 18k★ |
| **万象拼音**（rime-wanxiang） | AI 语料深度优化 + 调频标注 | **自带 LTS**（开箱即用） | 需手动配置 | 活跃 |
| 白霜拼音（rime-frost） | 独立评测调优 | 可挂载多种 | 需手动配置 | 活跃 |

**选中万象的核心理由**：自带 ngram 语言模型，长句体验更接近商业输入法。用户对「不够现代」的感知根源是裸 Rime 没有语言模型——万象原生解决这一点，且 nixpkgs 已有现成包，声明式接入成本极低。

## 声明式管理机制

NixOS / home-manager 对 Rime 的声明式配置支持到 **~95%** 的覆盖度：

### rimeDataPkgs 注入（系统级）

```nix
i18n.inputMethod.fcitx5.addons = with pkgs; [
  (fcitx5-rime.override {
    rimeDataPkgs = [
      rime-data          # 官方基础方案合集
      rime-wanxiang      # 万象拼音主方案
      rime-zhwiki        # 维基百科词库
      rime-moegirl       # 萌娘百科词库
    ];
  })
  # ...
];
```

`rimeDataPkgs` 在 build 时将各包内容合并到 fcitx5-rime 的 `share/rime-data/` 目录，用户目录（`~/.local/share/fcitx5/rime/`）会覆盖/扩展系统级配置。

### 方案选择 + 自定义 patch（用户级，home-manager）

```nix
# 启用万象
xdg.dataFile."fcitx5/rime/default.custom.yaml".text = ''
  patch:
    __include: wanxiang_suggested_default:/
'';
```

`__include: wanxiang_suggested_default:/` 是万象上游把 `default.yaml` 改名的结果——避免和 `rime-data` 的 `default.yaml` 冲突。

### 无法声明式的部分（~5%）

| 项目 | 原因 | 处理方式 |
|------|------|---------|
| 万象 ngram 语法模型（`.gram`） | 上游用「覆盖式 LTS 标签」发布，同一 URL 指向不同内容，违反 Nix hash 不可变原则，nixpkgs 官方故意不打包 | `home.activation` 自动下载 + 手动 `update-wanxiang-gram` 刷新 |
| 用户词库（`.userdb`） | Rime 运行期 ption生成，不能也不该声明式 | 自动生成，勿手动管理 |
| 方案部署后触发重新加载 | 改了词库/方案文件后需 Rime 感知 | 在 fcitx5 托盘菜单点 Deploy，或执行 `rime_deployer --deploy` |

## 万象 ngram 语法模型（`.gram`）

### 首次部署

仓库已在 `home.activation` 中配置自动下载：**换新机器时无需记忆任何步骤**，`home-manager switch`（或 `nixos-rebuild switch`）时会自动 curl 到 `~/.local/share/fcitx5/rime/wanxiang-lts-zh-hans.gram`。若网络不可用则在 stderr 警告并跳过，后续手动补。

### 手动更新到最新版

```bash
update-wanxiang-gram
```

该命令直接从 GitHub LTS release 拉取最新 `.gram` 文件。

### 更新节奏

上游作者不定期更新（每年 1-3 次），只要服务端跑完了训练（需租用 GPU 服务器），就将新模型推到同一个 `LTS` 标签下覆盖旧版。因此同一 URL 每次都拿到的是「当前最新 LTS」，没有版本号分割。

参考：https://github.com/amzxyz/RIME-LMDG/releases

## v14 build 缓存问题（workaround）

当前 nixpkgs-unstable 锁定的 `rime-wanxiang` 版本为 **14.1.1**（< v15），buildPhase 里有 `rime_deployer --compile` 预编译步骤。这可能导致用户目录的 `*.custom.yaml` patch 不生效。

**症状**：改了 custom.yaml 后万象依然不响应配置变更。

**解决**：
```bash
rm -rf ~/.local/share/fcitx5/rime/build/
# 然后在 fcitx5 托盘菜单点 Deploy
```

这个问题在 nixpkgs 的 rime-wanxiang **v15+** 已移除 buildPhase，届时仓库 nixpkgs 自动跟进即可（`nix flake update`）。

## 参考链接

- [rime-wanxiang / 万象拼音](https://github.com/amzxyz/rime_wanxiang)
- [RIME-LMDG / 万象语法模型](https://github.com/amzxyz/RIME-LMDG)
- [rime-ice / 雾凇拼音](https://github.com/iDvel/rime-ice)（备选方案）
- [felixonmars/fcitx5-pinyin-zhwiki](https://github.com/felixonmars/fcitx5-pinyin-zhwiki)（zhwiki 词库，同时产出 fcitx5 和 rime 格式）
- [outloudvi/mw2fcitx](https://github.com/outloudvi/mw2fcitx)（moegirl 词库生成器）
- [librime #377 — 候选词排序算法](https://github.com/rime/librine/issues/377)（开发者解释「记忆与遗忘」模型）
- [Nixpkgs PR #224042 — rimeDataPkgs 机制](https://github.com/NixOS/nixpkgs/pull/224042)
- [NixOS Wiki: Fcitx5](https://wiki.nixos.org/wiki/Fcitx5)
- [fcitx5 官方 Wiki: Using Fcitx 5 on Wayland](https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland)
