# typephp-skills

> Agent skill for [TypePHP](https://github.com/swoole/typephp) — the PHP → C++ AOT compiler.
> 面向 TypePHP 的 Agent 技能包：新建、改造、调试、审计项目，以及判断一份现有 PHP 代码能不能迁移到 AOT。

[![license](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![node](https://img.shields.io/badge/node-%3E%3D16-brightgreen.svg)](./package.json)

---

## 这是什么

一套写给 AI Agent 的**判断纪律**，不是 API 手册。

TypePHP 把 PHP 编译成原生二进制。这一句话解释了它几乎所有的失败模式：源码是 PHP，**验收标准是 C++ 编译器的**，运行时是链接进来的 PHP runtime 而不是解释器。三者错位，于是产生了一类在其他 PHP 项目里不存在的失败——能过检查、能编译、能链接，一运行就崩。

`check_code` 走的是 `tpc --dry`，它**只生成 C++**，不编译、不链接、不执行。在 tpc v0.9.5 / Windows x64 / MSVC 14.44 上实测：

| 输入 | `check_code` | 真实构建 | 运行 |
|---|---|---|---|
| `echoo("done")`（拼错函数名） | OK, `diagnostics=0` | 成功 | `call to undefined function` |
| `new Calc()`（全项目无此类） | OK, `diagnostics=0` | 成功 | `class 'Calc' is undefined` |
| 缺少 `]`（真语法错误） | FAILED，带 `file:line` | — | — |
| `$count = 1; $count = "one";` | FAILED，类型不匹配 | — | — |

所以技能的第一条规则是：**绿灯是必要条件，永远不是充分条件**。技能把验证拆成四级阶梯（生成 → 编译 → 链接 → 运行），并要求汇报时点名到达了哪一级。

## 安装

一行命令，直接从 GitHub 拉取并安装。**不需要 npm 账号，也不需要预先 clone。**

```bash
npx github:yangweijie/typephp-skills install
```

默认装到 `~/.workbuddy-ai/skills`（用户级，所有项目可用）。可选参数：

```bash
npx github:yangweijie/typephp-skills install --claude    # ~/.claude/skills
npx github:yangweijie/typephp-skills install --project   # ./.workbuddy-ai/skills
npx github:yangweijie/typephp-skills install --dir ./skills   # 自定义目录
npx github:yangweijie/typephp-skills install --force     # 覆盖旧版本（旧目录先备份）
```

目标目录已存在时默认跳过；加 `--force` 覆盖，旧目录会先备份为 `<name>.bak-<时间戳>`，不会直接删除。

其他命令：

```bash
npx github:yangweijie/typephp-skills list     # 列出包内技能
npx github:yangweijie/typephp-skills path     # 打印包内 skills 目录绝对路径
```

首次执行会拉取仓库（约 1–2 秒），之后走 npm 缓存。装完重启客户端才会加载。

### 手动安装

技能就是 `skills/typephp-project/` 这一个目录，拷到任意兼容 Agent Skills 的客户端技能目录即可：

```bash
git clone git@github.com:yangweijie/typephp-skills.git
cp -R typephp-skills/skills/typephp-project ~/.workbuddy-ai/skills/
```

| 客户端 | 用户级 | 项目级 |
|---|---|---|
| WorkBuddy | `~/.workbuddy-ai/skills/` | `.workbuddy-ai/skills/` |
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |

关键约束：**`SKILL.md` 必须在技能根目录直接可见**，加载器不会递归寻找嵌套的 `SKILL.md`。

> npm 包 `typephp-skills` 已在 `package.json` 中准备好（`npm pack` 校验通过），尚未发布到 registry。发布后 `npx typephp-skills install` 会等价可用。

## 安装之后能做什么

技能由对话意图触发，不需要记命令。典型的开场白：

```
用 TypePHP 起一个命令行小工具：读 CSV，按列分组求和，按数值降序打印。
最后要能编译成 exe 跑起来。
```

```
这段 TypePHP 代码 check_code 一直是 OK，但编译出来的程序一跑就报
class 'OrderRepo' is undefined，帮我修好并确认能跑。
```

```
评估一下 vendor/psr/log 能不能迁到 TypePHP，给我一份失败清单。
```

## 技能内容

| 文件 | 作用 |
|---|---|
| `SKILL.md` | 技能主体：四级验证阶梯、6 步工作流、收尾清单、MCP 工具选择策略 |
| `references/`（17 篇） | 按需加载的深文档：项目布局、惯用法、类型系统、属性、调试、审计、扩展模式、CI、性能、版本对齐 |
| `scripts/` | `preflight.sh/.bat` 环境体检、`audit-dir.sh/.bat` 批量兼容性扫描 |
| `evals/` | 30 个属性与类型注解回归用例 + 3 个端到端场景 |
| `*.stub.php` | import-library 桩文件样例 |

深文档是**按需加载**的：`SKILL.md` 只保留决策所需的最小上下文，其余在对应场景才读。这样技能占用的上下文可控，又不牺牲深度。

## 前置条件

技能本身只依赖文件系统；要让里面的命令真正跑起来，还需要：

| 依赖 | 用途 | 缺失时的表现 |
|---|---|---|
| `tpc`（TypePHP 工具链） | 全部构建与 `check_code` | 什么都编译不了 |
| C++ 工具链（MSVC / g++ / clang++） | 真实编译 | `C/C++ compiler executable not found` |
| typephp-mcp 服务 | 12 个 MCP 工具、结构化诊断 | 技能会降级为直接调 `tpc --dry` |
| PHP 解释器（可选） | 跑 `evals/` 回归 | 只影响验证，不影响构建 |

完整的环境准备、typephp-mcp 的构建与接入方式，见 [`skills/typephp-project/README.md`](./skills/typephp-project/README.md)。

## 更新

```bash
npx github:yangweijie/typephp-skills install --force
```

GitHub 来源总是取默认分支的最新提交。如果拉到的还是旧内容（npm 对 git 依赖有缓存），显式指定分支或清缓存：

```bash
npx github:yangweijie/typephp-skills#main install --force
npm cache clean --force   # 必要时
```

编译器一升级，技能里的实测结论就可能过期。更新后跑一遍回归：

```bash
php skills/typephp-project/evals/attribute-regression/run.php skills/typephp-project/evals/attribute-regression/cases
```

## 许可

[MIT](./LICENSE) © 2026 yangweijie
