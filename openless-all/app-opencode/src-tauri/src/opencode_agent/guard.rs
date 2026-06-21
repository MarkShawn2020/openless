//! 护栏：高风险命令分类 + 生成传给 `opencode --settings` 的权限 JSON。
//!
//! 「放行 + 护栏」策略（与原 coding_agent 对齐，但工具说明符语法换成 opencode 的）：
//! - `permissions.defaultMode = acceptEdits`（放行可恢复/轻动作）。
//! - `permissions.deny` 声明式拦截高风险工具调用（跨平台、稳）。
//! - 运行级 git 快照由运行器在启动前做（见 `mod.rs::create_git_snapshot`）。
//!
//! [`classify_command`] / [`is_high_risk_command`] 供「OpenCode 控制台」等场景对**单条命令**
//! 做本地预检/展示用，与 CLI 侧的 deny 规则互为补充。

/// 命令风险等级（前端审批卡按等级展示颜色/按钮）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CommandRisk {
    /// 安全：可恢复的日常命令（ls / git status / cat ...）。
    Safe,
    /// 中等：有副作用但可恢复（文件编辑、git commit、npm install ...）。
    Medium,
    /// 高风险：不可恢复或系统级（rm -rf / sudo / git push --force / mkfs ...）。
    High,
}

impl CommandRisk {
    pub fn is_high(self) -> bool {
        matches!(self, Self::High)
    }
}

/// 高风险子串（已小写）→ 原因。命中任一即判为高风险。
pub const HIGH_RISK_PATTERNS: &[(&str, &str)] = &[
    ("rm -rf", "递归强制删除"),
    ("rm -fr", "递归强制删除"),
    ("sudo ", "提权执行"),
    ("git push --force", "强制推送会覆盖远端历史"),
    ("git push -f", "强制推送会覆盖远端历史"),
    ("git reset --hard", "硬重置会丢弃未提交改动"),
    ("git clean -fd", "强制清理未跟踪文件"),
    ("git clean -f -d", "强制清理未跟踪文件"),
    ("mkfs", "格式化文件系统"),
    ("dd if=", "裸盘写入"),
    (":(){", "fork 炸弹"),
    ("shutdown", "关机"),
    ("reboot", "重启"),
    ("> /dev/sd", "直接写入块设备"),
    ("| sh", "管道执行远程脚本"),
    ("|sh", "管道执行远程脚本"),
    ("| bash", "管道执行远程脚本"),
    ("|bash", "管道执行远程脚本"),
    ("chmod -r 777 /", "危险的全局权限修改"),
    ("chown -r", "递归改所有权"),
];

/// 中等风险子串（已小写）。命中即判为 Medium（除非先命中高风险）。
const MEDIUM_RISK_PATTERNS: &[&str] = &[
    "git commit",
    "git push",
    "git merge",
    "git rebase",
    "git branch -d",
    "git branch -D",
    "npm install",
    "npm publish",
    "yarn install",
    "pnpm install",
    "pip install",
    "cargo install",
    "brew install",
    "apt install",
    "apt-get install",
    "rm ",
    "rmdir",
    "mv ",
    "mkdir",
    "touch",
    "chmod ",
    "chown ",
    "kill ",
    "pkill",
    "curl ",
    "wget ",
    "tar ",
    "unzip",
    "zip ",
    "docker ",
    "kubectl ",
    "helm ",
    "psql",
    "mysql",
    "sqlite",
];

/// 若命令命中高风险模式，返回原因；否则 `None`。
pub fn is_high_risk_command(command: &str) -> Option<&'static str> {
    let lowered = command.to_lowercase();
    HIGH_RISK_PATTERNS
        .iter()
        .find(|(pat, _)| lowered.contains(pat))
        .map(|(_, reason)| *reason)
}

/// 把单条命令分类成风险等级。前端审批卡用这个决定颜色和默认按钮。
///
/// 判定顺序：先高风险（命中即 High），再中等（命中即 Medium），否则 Safe。
pub fn classify_command(command: &str) -> CommandRisk {
    let lowered = command.to_lowercase();
    if HIGH_RISK_PATTERNS.iter().any(|(pat, _)| lowered.contains(pat)) {
        return CommandRisk::High;
    }
    if MEDIUM_RISK_PATTERNS.iter().any(|pat| lowered.contains(pat)) {
        return CommandRisk::Medium;
    }
    CommandRisk::Safe
}

/// 同一风险的等价命令子串分组：approve 其中之一即整组放行（从 deny 移除 + 加入 allow）。
///
/// 审批 UI 只回传命中的单个 `HIGH_RISK_PATTERNS` 子串（如 "git push --force"），但同一风险
/// 往往有多个等价写法（"git push -f"）。若只放行被点的那一个，等价写法仍在 deny（deny 优先
/// 级高于 allow）→ 命令仍被拦，用户误以为已批准。返回整组让调用方按组放行。
/// 命中返回整组；未命中返回空（调用方回落到 pattern 自身）。
pub fn risk_equivalent_patterns(pattern: &str) -> Vec<&'static str> {
    const GROUPS: &[&[&str]] = &[
        &["git push --force", "git push -f"],
        &["rm -rf", "rm -fr"],
        &["git clean -fd", "git clean -f -d"],
        // 其余按需补充；默认返回自身
    ];
    for g in GROUPS {
        if g.contains(&pattern) {
            return g.to_vec();
        }
    }
    Vec::new()
}

/// CLI `--settings` 默认的 `permissions.deny` 规则（opencode 工具说明符语法）。
///
/// opencode 的工具说明符语法与 Claude Code 一致：`Bash(<prefix>:*)` / `Edit(<path>)` /
/// `Write(<path>)`，所以这里直接沿用原 coding_agent 的 deny 清单。
///
/// 注意：管道执行远程脚本（`| sh`）、fork 炸弹（`:(){`）、`> /dev/sd` 等无法用命令前缀
/// 说明符（`Bash(<prefix>:*)`）表达——它们出现在命令中段或依赖 shell 语法——仍由
/// `defaultMode = acceptEdits` + 运行级 [`is_high_risk_command`] 探测兜底。
pub fn default_deny_rules() -> Vec<String> {
    vec![
        "Bash(rm -rf:*)".into(),
        "Bash(rm -fr:*)".into(),
        "Bash(sudo:*)".into(),
        "Bash(git push --force:*)".into(),
        "Bash(git push -f:*)".into(),
        "Bash(git reset --hard:*)".into(),
        "Bash(git clean -fd:*)".into(),
        "Bash(git clean -f -d:*)".into(),
        "Bash(mkfs:*)".into(),
        "Bash(dd:*)".into(),
        "Bash(shutdown:*)".into(),
        "Bash(reboot:*)".into(),
        // 权限/所有权/持久化/系统级命令（补齐 HIGH_RISK_PATTERNS 覆盖面 + macOS 持久化面）。
        "Bash(chmod:*)".into(),
        "Bash(chown:*)".into(),
        "Bash(crontab:*)".into(),
        "Bash(osascript:*)".into(),
        "Bash(launchctl:*)".into(),
        "Bash(kextload:*)".into(),
        "Bash(nvram:*)".into(),
        "Edit(.env)".into(),
        "Edit(.git/**)".into(),
        // macOS 持久化面：开机自启 plist + 登录 shell 配置（写入即可持久驻留/提权）。
        // 用 `~/` 家目录前缀（与 Claude Code settings 官方写法一致，如 `Read(~/.zshrc)`）：
        // 文件路径规则里 bare `**/.zshrc` 是相对 agent **工作目录**匹配，命中不到工作目录
        // 之外的真正 `~/.zshrc` → 护栏失效。LaunchDaemons 是系统路径（写入需 root，已被
        // `Bash(sudo:*)` 拦），这里只覆盖用户态 LaunchAgents + 登录 shell 配置。
        "Edit(~/Library/LaunchAgents/**)".into(),
        "Write(~/Library/LaunchAgents/**)".into(),
        "Edit(~/.zshrc)".into(),
        "Write(~/.zshrc)".into(),
        "Edit(~/.zprofile)".into(),
        "Write(~/.zprofile)".into(),
        "Edit(~/.bash_profile)".into(),
        "Write(~/.bash_profile)".into(),
        "Edit(~/.bashrc)".into(),
        "Write(~/.bashrc)".into(),
    ]
}

/// 生成护栏 settings JSON。`mode` 为 `--mode` 同名取值；`extra_deny` 追加在默认 deny 之后。
pub fn build_guard_settings_json(mode: &str, extra_deny: &[String]) -> serde_json::Value {
    let mut deny = default_deny_rules();
    deny.extend(extra_deny.iter().cloned());
    serde_json::json!({
        "permissions": {
            "defaultMode": mode,
            "deny": deny,
        }
    })
}

/// 生成 opencode 格式的权限配置 JSON（写入临时文件后通过 `OPENCODE_CONFIG` 环境变量传给 opencode）。
///
/// opencode 的权限格式与 Claude Code 不同：
/// - `permission`（单数）以工具名为 key，值为 `"allow"` / `"ask"` / `"deny"`。
/// - 支持对象语法做细粒度模式匹配（`"bash": { "*": "ask", "git *": "allow", "rm *": "deny" }`）。
/// - `edit` 覆盖 edit / write / patch 三种文件修改。
///
/// `mode` 对应 OpenCodeAgentPermissionMode 的 CLI arg（plan / default / acceptEdits / bypassPermissions）；
/// `extra_allow_patterns` 为审批通过后放行的高风险命令子串（如 "git push --force"），
/// 会从 bash deny 规则中剔除并加入 allow。
pub fn build_opencode_permission_json(
    mode: &str,
    extra_allow_patterns: &[String],
) -> serde_json::Value {
    // bash deny 规则：把 HIGH_RISK_PATTERNS 里的 bash 类模式转成 opencode 的命令模式语法。
    // opencode 的 bash 模式匹配的是「解析后的命令」（如 `git status --porcelain`），
    // 所以 `rm -rf *` 能匹配 `rm -rf /tmp/x`。
    let mut bash_deny: Vec<String> = vec![
        "rm -rf *".into(),
        "rm -fr *".into(),
        "sudo *".into(),
        "git push --force *".into(),
        "git push -f *".into(),
        "git reset --hard *".into(),
        "git clean -fd *".into(),
        "git clean -f -d *".into(),
        "mkfs *".into(),
        "dd *".into(),
        "shutdown *".into(),
        "reboot *".into(),
        "chmod *".into(),
        "chown *".into(),
        "crontab *".into(),
        "osascript *".into(),
        "launchctl *".into(),
        "kextload *".into(),
        "nvram *".into(),
    ];

    // 审批放行的模式：从 deny 剔除等价组。
    let approved: Vec<String> = extra_allow_patterns
        .iter()
        .flat_map(|p| {
            let group = risk_equivalent_patterns(p);
            if group.is_empty() {
                vec![p.clone()]
            } else {
                group.into_iter().map(|s| s.to_string()).collect()
            }
        })
        .collect();
    for p in &approved {
        // 把 "git push --force" 转成 "git push --force *" 来匹配 deny 规则。
        let pat = format!("{p} *");
        bash_deny.retain(|d| d != &pat);
    }

    // 构建 bash 权限对象：catch-all 按 mode 决定，deny 规则在后（last match wins）。
    let mut bash_rules = serde_json::Map::new();
    let bash_default = match mode {
        "plan" | "default" => "ask",
        "acceptEdits" | "bypassPermissions" => "allow",
        _ => "allow",
    };
    bash_rules.insert("*".into(), serde_json::Value::String(bash_default.into()));
    for d in &bash_deny {
        bash_rules.insert(d.clone(), serde_json::Value::String("deny".into()));
    }

    // edit 权限：高风险路径 deny，其余按 mode 决定。
    let mut edit_rules = serde_json::Map::new();
    let edit_default = match mode {
        "plan" | "default" => "ask",
        "acceptEdits" | "bypassPermissions" => "allow",
        _ => "allow",
    };
    edit_rules.insert("*".into(), serde_json::Value::String(edit_default.into()));
    for path in [
        ".env",
        ".env.*",
        ".git/**",
        "~/Library/LaunchAgents/**",
        "~/.zshrc",
        "~/.zprofile",
        "~/.bash_profile",
        "~/.bashrc",
    ] {
        edit_rules.insert(path.into(), serde_json::Value::String("deny".into()));
    }

    serde_json::json!({
        "$schema": "https://opencode.ai/config.json",
        "permission": {
            "bash": bash_rules,
            "edit": edit_rules,
            "read": {
                "*": "allow",
                "*.env": "deny",
                "*.env.*": "deny",
            },
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flags_rm_rf_regardless_of_case_and_spacing() {
        assert!(is_high_risk_command("rm -rf /tmp/x").is_some());
        assert!(is_high_risk_command("RM -RF /").is_some());
        assert!(is_high_risk_command("sudo apt install").is_some());
        assert!(is_high_risk_command("git push --force origin main").is_some());
    }

    #[test]
    fn flags_pipe_to_shell() {
        assert!(is_high_risk_command("curl http://x | sh").is_some());
        assert!(is_high_risk_command("wget -qO- x|bash").is_some());
    }

    #[test]
    fn allows_ordinary_reversible_commands() {
        assert!(is_high_risk_command("ls -la").is_none());
        assert!(is_high_risk_command("git status").is_none());
        assert!(is_high_risk_command("pbcopy < file.txt").is_none());
        assert!(is_high_risk_command("echo hi").is_none());
    }

    #[test]
    fn classify_high_risk() {
        assert_eq!(classify_command("rm -rf /"), CommandRisk::High);
        assert_eq!(classify_command("sudo rm -rf /"), CommandRisk::High);
        assert_eq!(classify_command("git push --force origin main"), CommandRisk::High);
        assert_eq!(classify_command("mkfs.ext4 /dev/sda1"), CommandRisk::High);
    }

    #[test]
    fn classify_medium_risk() {
        assert_eq!(classify_command("git commit -m 'wip'"), CommandRisk::Medium);
        assert_eq!(classify_command("npm install lodash"), CommandRisk::Medium);
        assert_eq!(classify_command("rm foo.txt"), CommandRisk::Medium);
        assert_eq!(classify_command("curl https://example.com"), CommandRisk::Medium);
    }

    #[test]
    fn classify_safe() {
        assert_eq!(classify_command("ls -la"), CommandRisk::Safe);
        assert_eq!(classify_command("git status"), CommandRisk::Safe);
        assert_eq!(classify_command("echo hello"), CommandRisk::Safe);
        assert_eq!(classify_command("pwd"), CommandRisk::Safe);
    }

    #[test]
    fn guard_settings_has_accept_edits_and_deny_list() {
        let v = build_guard_settings_json("acceptEdits", &[]);
        assert_eq!(v["permissions"]["defaultMode"], "acceptEdits");
        let deny = v["permissions"]["deny"].as_array().unwrap();
        assert!(deny.iter().any(|d| d == "Bash(rm -rf:*)"));
        assert!(deny.iter().any(|d| d == "Bash(sudo:*)"));
    }

    #[test]
    fn guard_settings_appends_extra_deny() {
        let extra = vec!["Bash(npm publish:*)".to_string()];
        let v = build_guard_settings_json("acceptEdits", &extra);
        let deny = v["permissions"]["deny"].as_array().unwrap();
        assert!(deny.iter().any(|d| d == "Bash(npm publish:*)"));
    }

    #[test]
    fn default_deny_covers_perms_and_macos_persistence() {
        let deny = default_deny_rules();
        // 新增的权限/系统级命令。
        for rule in [
            "Bash(chmod:*)",
            "Bash(chown:*)",
            "Bash(crontab:*)",
            "Bash(osascript:*)",
            "Bash(launchctl:*)",
            "Bash(kextload:*)",
            "Bash(nvram:*)",
        ] {
            assert!(deny.iter().any(|d| d == rule), "缺少 deny: {rule}");
        }
        // macOS 持久化面（`~/` 家目录前缀，全 Edit/Write 变体）。
        for rule in [
            "Edit(~/Library/LaunchAgents/**)",
            "Write(~/Library/LaunchAgents/**)",
            "Edit(~/.zshrc)",
            "Write(~/.zshrc)",
            "Edit(~/.zprofile)",
            "Write(~/.zprofile)",
            "Edit(~/.bash_profile)",
            "Write(~/.bash_profile)",
            "Edit(~/.bashrc)",
            "Write(~/.bashrc)",
        ] {
            assert!(deny.iter().any(|d| d == rule), "缺少 deny: {rule}");
        }
    }

    #[test]
    fn risk_equivalent_force_push_releases_whole_group() {
        // approve "--force" 应同时放行 "-f" 等价写法。
        let group = risk_equivalent_patterns("git push --force");
        assert!(group.contains(&"git push --force"));
        assert!(group.contains(&"git push -f"));
        // 反向也成立：approve "-f" 同样放行 "--force"。
        let group2 = risk_equivalent_patterns("git push -f");
        assert!(group2.contains(&"git push --force"));
    }

    #[test]
    fn risk_equivalent_rm_group_and_unknown_returns_empty() {
        let rm = risk_equivalent_patterns("rm -rf");
        assert!(rm.contains(&"rm -rf"));
        assert!(rm.contains(&"rm -fr"));
        // approve "git clean -fd" 应同时放行 "git clean -f -d" 等价写法。
        let clean = risk_equivalent_patterns("git clean -fd");
        assert!(clean.contains(&"git clean -fd"));
        assert!(clean.contains(&"git clean -f -d"));
        // 不在任何分组里 → 返回空，调用方回落到 pattern 自身。
        assert!(risk_equivalent_patterns("sudo ").is_empty());
    }

    #[test]
    fn opencode_permission_json_has_bash_deny_rules() {
        let v = build_opencode_permission_json("acceptEdits", &[]);
        let bash = &v["permission"]["bash"];
        assert_eq!(bash["*"], "allow");
        assert_eq!(bash["rm -rf *"], "deny");
        assert_eq!(bash["sudo *"], "deny");
        assert_eq!(bash["git push --force *"], "deny");
    }

    #[test]
    fn opencode_permission_json_plan_mode_uses_ask() {
        let v = build_opencode_permission_json("plan", &[]);
        assert_eq!(v["permission"]["bash"]["*"], "ask");
        assert_eq!(v["permission"]["edit"]["*"], "ask");
    }

    #[test]
    fn opencode_permission_json_edit_denies_env_and_persistence() {
        let v = build_opencode_permission_json("acceptEdits", &[]);
        let edit = &v["permission"]["edit"];
        assert_eq!(edit["*"], "allow");
        assert_eq!(edit[".env"], "deny");
        assert_eq!(edit["~/Library/LaunchAgents/**"], "deny");
        assert_eq!(edit["~/.zshrc"], "deny");
    }

    #[test]
    fn opencode_permission_json_extra_allow_removes_deny() {
        // 审批放行 "git push --force" → 等价组（--force + -f）都从 deny 剔除。
        let v = build_opencode_permission_json("acceptEdits", &["git push --force".into()]);
        let bash = &v["permission"]["bash"];
        assert_eq!(bash["*"], "allow");
        // 两个等价写法都应被剔除。
        assert!(bash.get("git push --force *").is_none() || bash["git push --force *"] != "deny");
        assert!(bash.get("git push -f *").is_none() || bash["git push -f *"] != "deny");
        // 其它 deny 规则不受影响。
        assert_eq!(bash["rm -rf *"], "deny");
    }

    #[test]
    fn opencode_permission_json_read_denies_env() {
        let v = build_opencode_permission_json("acceptEdits", &[]);
        let read = &v["permission"]["read"];
        assert_eq!(read["*"], "allow");
        assert_eq!(read["*.env"], "deny");
        assert_eq!(read["*.env.*"], "deny");
    }
}
