//! 解析 `opencode run --format json` 的逐行 JSON 事件输出。
//!
//! opencode 的 JSON 输出是 JSONL（每行一个 JSON 对象），事件结构为：
//! `{ "type": "<event-type>", "properties": { ... } }`
//!
//! 关注的几类事件（其余忽略）：
//! - `message.part.updated`：消息部分更新（文本增量 / 工具调用 / 步骤完成）。
//!   - `part.type == "text"` + `delta`：逐字文本增量。
//!   - `part.type == "tool"` + `state.status == "running"`：工具调用开始。
//!   - `part.type == "step-finish"`：一步完成，携带 `cost`（美元）。
//! - `session.idle`：会话空闲（整轮完成）。
//! - `session.error`：会话出错。
//! - `message.updated`：消息更新（assistant 消息完成时携带最终文本）。
//!
//! 参考类型定义：packages/sdk/js/src/gen/types.gen.ts

/// 流式解析后的事件（投递给 `run_opencode_agent` 的事件循环）。
#[derive(Debug, Clone, PartialEq)]
pub enum OpenCodeStreamEvent {
    /// 逐字文本增量（assistant 回复的流式片段）。
    Delta { text: String },
    /// 工具调用（Bash / Read / Edit / Write / Glob / Grep / WebSearch ...）。
    ToolUse { name: String },
    /// 一步完成，携带本步成本（美元）。多步会多次触发。
    StepFinish { cost: Option<f64> },
    /// 整轮完成，携带最终文本和累计成本。
    Completed { text: String, cost: Option<f64> },
    /// 运行出错。
    Error { message: String },
}

/// 解析一行 JSON 事件。无关行返回 `None`（防御式：解析失败也返回 `None`，不 panic）。
///
/// 累积状态（final_text / total_cost）由调用方维护，本函数只负责把单行翻译成事件。
/// 唯一例外是 `Completed`：当 `session.idle` 触发时，本函数无法知道累积的 final_text，
/// 所以只返回 `Completed { text: "", cost: None }`，调用方应忽略这里的 text/cost 并用自己
/// 累积的值。实际上 `run_opencode_agent` 的循环里对 `Completed` 分支只取 cost 字段。
pub fn parse_opencode_line(line: &str) -> Option<OpenCodeStreamEvent> {
    let line = line.trim();
    if line.is_empty() {
        return None;
    }
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    let event_type = v.get("type")?.as_str()?;
    match event_type {
        "message.part.updated" => parse_message_part_updated(&v),
        "message.updated" => parse_message_updated(&v),
        "session.idle" => Some(OpenCodeStreamEvent::Completed {
            text: String::new(),
            cost: None,
        }),
        "session.error" => {
            let msg = v
                .get("properties")
                .and_then(|p| p.get("error"))
                .and_then(|e| e.get("data"))
                .and_then(|d| d.get("message"))
                .and_then(|m| m.as_str())
                .unwrap_or("opencode session 出错");
            Some(OpenCodeStreamEvent::Error {
                message: msg.to_string(),
            })
        }
        _ => None,
    }
}

/// 解析 `message.part.updated` 事件。
fn parse_message_part_updated(v: &serde_json::Value) -> Option<OpenCodeStreamEvent> {
    let props = v.get("properties")?;
    let part = props.get("part")?;
    let part_type = part.get("type")?.as_str()?;
    match part_type {
        "text" => {
            // 优先用 delta（流式增量）；没有 delta 时取 part.text（部分完成快照）。
            if let Some(delta) = props.get("delta").and_then(|d| d.as_str()) {
                if !delta.is_empty() {
                    return Some(OpenCodeStreamEvent::Delta {
                        text: delta.to_string(),
                    });
                }
            }
            // 无 delta：忽略（避免把完整文本当增量重复投递）。
            None
        }
        "tool" => {
            // 只在工具进入 running 状态时投递一次 ToolUse。
            let status = part
                .get("state")
                .and_then(|s| s.get("status"))
                .and_then(|s| s.as_str())?;
            if status != "running" {
                return None;
            }
            let name = part.get("tool").and_then(|t| t.as_str())?.to_string();
            Some(OpenCodeStreamEvent::ToolUse { name })
        }
        "step-finish" => {
            let cost = part.get("cost").and_then(|c| c.as_f64());
            Some(OpenCodeStreamEvent::StepFinish { cost })
        }
        _ => None,
    }
}

/// 解析 `message.updated` 事件（assistant 消息完成时触发，携带最终文本）。
fn parse_message_updated(v: &serde_json::Value) -> Option<OpenCodeStreamEvent> {
    let info = v.get("properties")?.get("info")?;
    let role = info.get("role").and_then(|r| r.as_str())?;
    if role != "assistant" {
        return None;
    }
    // assistant 消息完成时，error 字段存在则报错。
    if let Some(err) = info.get("error") {
        let msg = err
            .get("data")
            .and_then(|d| d.get("message"))
            .and_then(|m| m.as_str())
            .unwrap_or("assistant 消息出错");
        return Some(OpenCodeStreamEvent::Error {
            message: msg.to_string(),
        });
    }
    // 不在这里投递 Completed（session.idle 会兜底）；message.updated 只用来探测 error。
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_text_delta() {
        let line = r#"{"type":"message.part.updated","properties":{"part":{"id":"p1","sessionID":"s1","messageID":"m1","type":"text","text":"你好"},"delta":"你好"}}"#;
        assert_eq!(
            parse_opencode_line(line),
            Some(OpenCodeStreamEvent::Delta {
                text: "你好".into()
            })
        );
    }

    #[test]
    fn ignores_text_part_without_delta() {
        // 无 delta 字段 → 不投递（避免把完整文本当增量重复投递）。
        let line = r#"{"type":"message.part.updated","properties":{"part":{"id":"p1","type":"text","text":"完整文本"}}}"#;
        assert_eq!(parse_opencode_line(line), None);
    }

    #[test]
    fn ignores_empty_delta() {
        let line = r#"{"type":"message.part.updated","properties":{"part":{"id":"p1","type":"text","text":""},"delta":""}}"#;
        assert_eq!(parse_opencode_line(line), None);
    }

    #[test]
    fn parses_tool_use_running() {
        let line = r#"{"type":"message.part.updated","properties":{"part":{"id":"p1","type":"tool","tool":"Bash","callID":"c1","state":{"status":"running","input":{}}}}}"#;
        assert_eq!(
            parse_opencode_line(line),
            Some(OpenCodeStreamEvent::ToolUse {
                name: "Bash".into()
            })
        );
    }

    #[test]
    fn ignores_tool_use_completed() {
        // 只在 running 时投递；completed 不重复投递。
        let line = r#"{"type":"message.part.updated","properties":{"part":{"id":"p1","type":"tool","tool":"Bash","state":{"status":"completed","output":"done","title":"ls"}}}}"#;
        assert_eq!(parse_opencode_line(line), None);
    }

    #[test]
    fn parses_step_finish_with_cost() {
        let line = r#"{"type":"message.part.updated","properties":{"part":{"id":"p1","type":"step-finish","reason":"stop","cost":0.0123,"tokens":{"input":100,"output":50,"reasoning":0,"cache":{"read":0,"write":0}}}}}"#;
        assert_eq!(
            parse_opencode_line(line),
            Some(OpenCodeStreamEvent::StepFinish {
                cost: Some(0.0123)
            })
        );
    }

    #[test]
    fn parses_session_idle_as_completed() {
        let line = r#"{"type":"session.idle","properties":{"sessionID":"s1"}}"#;
        match parse_opencode_line(line) {
            Some(OpenCodeStreamEvent::Completed { text, cost }) => {
                assert!(text.is_empty());
                assert!(cost.is_none());
            }
            other => panic!("expected Completed, got {other:?}"),
        }
    }

    #[test]
    fn parses_session_error() {
        let line = r#"{"type":"session.error","properties":{"sessionID":"s1","error":{"name":"APIError","data":{"message":"rate limited","statusCode":429,"isRetryable":true}}}}"#;
        assert_eq!(
            parse_opencode_line(line),
            Some(OpenCodeStreamEvent::Error {
                message: "rate limited".into()
            })
        );
    }

    #[test]
    fn parses_assistant_message_error() {
        let line = r#"{"type":"message.updated","properties":{"info":{"id":"m1","role":"assistant","error":{"name":"ProviderAuthError","data":{"providerID":"anthropic","message":"invalid key"}}}}}"#;
        assert_eq!(
            parse_opencode_line(line),
            Some(OpenCodeStreamEvent::Error {
                message: "invalid key".into()
            })
        );
    }

    #[test]
    fn ignores_non_assistant_message_updated() {
        let line = r#"{"type":"message.updated","properties":{"info":{"id":"m1","role":"user"}}}"#;
        assert_eq!(parse_opencode_line(line), None);
    }

    #[test]
    fn ignores_unknown_event_types() {
        assert_eq!(
            parse_opencode_line(r#"{"type":"session.created","properties":{"info":{"id":"s1"}}}"#),
            None
        );
        assert_eq!(
            parse_opencode_line(r#"{"type":"file.edited","properties":{"file":"foo.rs"}}"#),
            None
        );
        assert_eq!(parse_opencode_line(r#"{"type":"todo.updated","properties":{}}"#), None);
    }

    #[test]
    fn ignores_garbage() {
        assert_eq!(parse_opencode_line("not json"), None);
        assert_eq!(parse_opencode_line(""), None);
        assert_eq!(parse_opencode_line("   "), None);
        assert_eq!(parse_opencode_line(r#"{"no_type": true}"#), None);
    }
}
