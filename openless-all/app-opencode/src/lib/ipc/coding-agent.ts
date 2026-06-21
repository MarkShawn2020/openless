import type { OpenCodeAgentPermissionMode } from "../types"
export type { OpenCodeAgentPermissionMode }
import { invokeOrMock } from "./shared"

/** opencode CLI 检测结果（回前端，camelCase）。 */
export interface OpenCodeDetection {
    installed: boolean
    version: string | null
    exe: string
}

/** 命令风险等级（供前端审批卡展示颜色/按钮）。 */
export type CommandRisk = "safe" | "medium" | "high"

/** 无头 opencode 运行事件，由后端 `opencode:event` 流式推送（tag 为 `kind`）。 */
export type OpenCodeAgentEvent =
    | { kind: "started"; session_id: string }
    | { kind: "delta"; session_id: string; text: string }
    | { kind: "tool_use"; session_id: string; name: string }
    | {
          kind: "completed"
          session_id: string
          text: string
          cost_usd: number | null
          duration_ms: number | null
      }
    | { kind: "cancelled"; session_id: string }
    | { kind: "error"; session_id: string; message: string }

/** 检测 opencode CLI 是否已安装并可用。 */
export function opencodeAgentDetect(): Promise<OpenCodeDetection> {
    return invokeOrMock(
        "opencode_agent_detect",
        undefined,
        () => ({
            installed: false,
            version: null,
            exe: "opencode",
        }),
    )
}

export interface OpenCodeAgentRunTestArgs {
    prompt: string
    permissionMode?: OpenCodeAgentPermissionMode
    workdir?: string
    model?: string
    maxBudgetUsd?: number
}

/** 跑一轮 opencode agent（测试 / 调试用。生产路径走 coordinator 的语音流水线）。 */
export function opencodeAgentRunTest(args: OpenCodeAgentRunTestArgs): Promise<string> {
    return invokeOrMock("opencode_agent_run", { ...args }, () => "")
}

/** 取消运行中的 opencode agent。 */
export function opencodeAgentCancelTest(): Promise<void> {
    return invokeOrMock("opencode_agent_cancel", undefined, () => undefined)
}

/** 查询某条命令的风险等级（供前端在审批卡里展示）。 */
export function opencodeAgentCommandRisk(command: string): Promise<CommandRisk> {
    return invokeOrMock("opencode_agent_command_risk", { command }, () => "safe")
}
