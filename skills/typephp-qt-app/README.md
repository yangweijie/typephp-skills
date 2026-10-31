# typephp-qt-app

> 面向 [TypePHP](https://github.com/swoole/typephp)（PHP → C++ AOT 编译器）的**原生桌面 GUI** 技能：用 Qt 画窗口，用编译后的 PHP 写逻辑。

---

**目录**

- [为什么需要它](#为什么需要它)
- [核心模型：两条路由](#核心模型两条路由)
- [包路线的三个概念](#包路线的三个概念)
- [能力范围](#能力范围)
- [安装](#安装)
- [前置条件](#前置条件)
- [快速开始](#快速开始)
- [目录结构](#目录结构)
- [18 条硬规则](#18-条硬规则)
- [无人工验证](#无人工验证)
- [已知边界](#已知边界)
- [许可](#许可)

---

## 为什么需要它

TypePHP 把 PHP 编译成原生机器码，但它**画不出一个窗口**。窗口得由 Qt（C++）画。

于是每个项目都是同一个形状：一层很薄的 C++ 桥把 Qt 暴露给 PHP，所有决策留在 PHP 里。技能要解决的就是这个形状里的所有坑——而且这些坑有个共同特征：**在解释器下不复现，只在编译产物里炸**。

## 核心模型：两条路由

| 路由 | 是什么 | 什么时候用 |
|---|---|---|
| **0. `typephp-qt` 包**（默认） | Composer 包，已经包含桥、声明式 UI 层、测试替身和 CLI。你只写 PHP。 | 几乎总是。表单、表格、看板、工具、管理面板。 |
| **1. 手写桥** | 自己写 `.stub.php` + `.cc`，手动驱动 `tpc`。 | 需要包没暴露的 Qt 控件，或在编译器仓库内部工作。 |

**除非有明确理由，否则走路由 0。** 手写桥意味着你要自己维护 C++，还要跟着 Qt / PHPX 的版本走。

## 包路线的三个概念

1. **状态就是普通 PHP** —— 一个数组（或你自己的对象）装着界面要显示的一切。
2. **`view()` 从状态描述界面** —— 每帧执行一次，返回控件树。你永远不去改控件。
3. **handler 只改状态** —— 下一帧重新描述界面，C++ 侧按 `id` 做 diff，光标、选中、滚动位置都保留。

```php
$app->view(fn() => WidgetTree::vbox([
    WidgetTree::label($state['greeting'], ['id' => 'greeting']),
    WidgetTree::button('打招呼', ['id' => 'greet_btn']),
]));

$app->on('greet_btn', 'click', function () use (&$state) {
    $state['greeting'] = 'Hello!';
});
```

**要给每个你会读写的控件一个 `id`。** 没有 id 的节点会拿到结构化路径 id（`_p0.1.2`），稳定但不可读，`text('name_input')` 这类调用拿不到它。

## 能力范围

| 你要做的事 | 技能给出的东西 | 对应文档 |
|---|---|---|
| 判断该不该手写桥 | 两条路由的取舍与成本 | `SKILL.md` 顶部 |
| 从零建一个窗口应用 | `scaffold.sh` 一键生成可编译项目 | `scripts/scaffold.sh` |
| 搞清哪些控件可用 | 安装内**全部** Qt Widgets 类，按用途分组 | `references/qt-widgets-catalog.md` |
| 内嵌网页 | WebView2 / WKWebView / QTextBrowser 三后端的差异与运行时探测 | `SKILL.md` 包路线 |
| 写 C++ 桥 | 转换辅助、`php::Box`、事件队列、`php_*` 入口 | `references/bridge-pattern.md` |
| 编译报错 / 链接报错 | AOT 陷阱逐条：症状、根因、修法 | `references/aot-pitfalls.md` |
| 三平台构建与部署 | `project.yml`、`windeployqt`、`.app` 打包、DLL 闭包 | `references/build-and-deploy.md` |
| 加一个新 Qt 模块 | 缺哪个模块、要改哪三处 | `references/qt-modules.md` |
| 用 QML 而不是 Widgets | `QQmlApplicationEngine` 桥与 `.qml` 部署 | `references/qml-route.md` |
| 做托盘常驻应用 | 三个平台的托盘差异、两个被反转的假设 | `references/system-tray.md` |

## 安装

```bash
npx github:yangweijie/typephp-skills install
```

这条命令会装上本仓库里的所有技能（`typephp-project` 和 `typephp-qt-app`）。常用参数：

```bash
npx github:yangweijie/typephp-skills install --claude    # ~/.claude/skills
npx github:yangweijie/typephp-skills install --project   # ./.workbuddy-ai/skills
npx github:yangweijie/typephp-skills install --force     # 覆盖旧版本（先备份）
```

手动安装：把 `skills/typephp-qt-app/` 整个目录拷到技能目录即可，`SKILL.md` 必须在技能根目录直接可见。

## 前置条件

| 依赖 | 用途 | 缺失时的表现 |
|---|---|---|
| `composer require yangweijie/typephp-qt` | 包路线的一切 | 没有 `qtphp` 命令 |
| Qt 6（含 Widgets；QML 另需 Qt6Qml/Qt6Quick） | 编译与运行窗口 | 链接失败或启动黑屏 |
| `tpc`（TypePHP 工具链） | 编译 PHP | `qtphp doctor` 报 `tpc: 未找到` |
| C++ 工具链（MSVC / Xcode CLT / g++） | 编译桥 | 编译阶段失败 |

**装完先跑 `qtphp doctor`**，它会把 PHP、tpc、Qt、编译器、PHPUnit 一次性查完。

两个容易踩的环境坑：

- **消费方项目里 `qtphp` 找不到 `tpc`。** 它按包目录推导 `rootDir`，会去找 `vendor/yangweijie/typephp-qt/vendor/bin/tpc.php`，那里没有。要在自己的项目里装驱动并显式指定：`composer require --dev swoole/typephp` 然后 `export TPC="$PWD/vendor/bin/tpc.php"`。
- **Windows 上 `cl.exe` 在 PATH 里还不够**，`INCLUDE` 必须指向 MSVC 头文件目录，否则报 `fatal error C1083: cannot open include file "malloc.h"`——不是缺库，是 `vcvars64.bat` 没 source。

## 快速开始

```bash
composer require yangweijie/typephp-qt
qtphp doctor          # 先确认环境
qtphp new myapp       # 生成一个能直接编译的项目
cd myapp
qtphp build .         # 编译（Windows 上会自动部署运行时 DLL）
qtphp run .           # 运行
qtphp package .       # 打自包含包，并做自检
```

体积敏感的场景加 `--nano`：把 php-nano 和 PHPX 源码直接编进产物，完全不链接 PHP 运行时（技能内记录 Apple Silicon 已验证；其余平台未验证）。

## 目录结构

```
typephp-qt-app/
├── SKILL.md                      # 路由决策、18 条硬规则、Windows 工具链陷阱
├── README.md
├── references/                   # 7 篇按需加载的深文档
│   ├── aot-pitfalls.md           # 只在编译产物里出现的 9 类陷阱
│   ├── bridge-pattern.md         # C++/PHP 桥的完整实现
│   ├── qt-widgets-catalog.md     # 安装内全部 Qt Widgets 类
│   ├── qt-modules.md             # 有哪些模块、缺的怎么加
│   ├── build-and-deploy.md       # 三平台构建、部署、打包
│   ├── qml-route.md              # QML / Quick 路线
│   └── system-tray.md            # 系统托盘
├── assets/templates/             # 三平台 project.yml、runtime.ini、桥/桩/主程序/托盘骨架
├── scripts/
│   ├── scaffold.sh               # 一键生成可编译项目（窗口 / 托盘两种）
│   └── lint-bats.sh              # 检查生成的 .bat 里的 cmd 陷阱
└── evals/
    └── evals.json                # 8 个端到端场景
```

## 18 条硬规则

每一条都会**静默**毁掉一次构建、一次运行或一次点击。分三组：

- **规则 1–6：AOT 特有**，在普通 PHP 解释器下不复现，所以单测全绿证明不了什么。包括闭包参数个数被严格校验、全局作用域只能有声明、`main()` 必须是全局函数、闭包参数必须显式标类型、模态对话框会永久阻塞、反射变量不能复用。
- **规则 7–14：两条路由都适用**。桩函数体必须为空、C++ 符号要有 `php_` 前缀、`QApplication` 必须先于任何控件、事件循环得自己泵、部署要带 Qt 插件而不只是 DLL、边界处统一 UTF-8、每个用到的类都要 include、托盘应用要反转两个假设。
- **规则 15–18：API / 编译器陷阱**，靠跑真应用才挖出来的。其中 15–17 编译通过、运行时静默失效（`tabs()` 的参数形状、首帧 `current` 选择无效、`table` 没有行高控制导致多行单元格被省略成 `…`），18 是编译期报错但指向生成的代码而不是你的源码。

全文与修法见 `SKILL.md`，逐条的症状/根因/修复见 `references/aot-pitfalls.md`。

## 无人工验证

GUI 最难测，所以技能要求每个包应用都留三个无头开关：

```bash
qtphp run . --shot out.png   # 渲染几帧存成 PNG 再退出 —— 视觉检查
qtphp run . --selftest       # 触发所有已注册事件 —— 抓 handler 接线错误
qtphp run . --difftest       # 表格/树 diff 的边界（选中、行 id、patch）
```

`$app->headless(true)` 让 `message()` 返回默认值、文件对话框返回空，**模态框就不会把 CI 卡死**。无 GUI 会话的机器上再设 `QT_QPA_PLATFORM=offscreen`。

`--selftest` 不是锦上添花：它是唯一能抓到「闭包参数个数」那个 AOT 陷阱的检查，PHP 单测跑在宽容的解释器上，复现不了。

## 已知边界

- 技能编写于 2026-10，`yangweijie/typephp-qt` 当前最新为 **v0.9.5（2026-10-15）**。技能内**没有逐条标注版本基线**，升级包之后请以 `qtphp doctor`、包自带的 `README.md` 和 `tests/WidgetTreeTest.php` 为准。
- 实测重心在 **Windows / MSVC**（`windeployqt`、`/Zc:__cplusplus`、`runtime.ini`）；macOS 的 `.app` 打包与 Apple Silicon 的 `--nano` 有实测记录；Linux 覆盖度最低。
- `--nano` 的产物体积数字来自技能内的记录，**只在 Apple Silicon 上验证过**，其他平台未复验。
- 规则 16、17 是**上游缺陷**（已标注 `Upstream defect` / `Upstream gap`），不是使用者的错；修复方式在各自条目里写明。
- `scripts/scaffold.sh` 生成的 `.bat` 里含有作者机器的默认路径（`PHP_HOME`、`vcvars64.bat`），首次使用需要按本机环境改。

## 许可

[MIT](../../LICENSE) © 2026 yangweijie
