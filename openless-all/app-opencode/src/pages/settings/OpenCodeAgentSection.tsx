// 高级 → OpenCode 配置：启用开关、后端（Claude / OpenCode）、模型 / 权限模式 / 工作目录。
// 「按住说话键」在 通用 → 快捷键 里配置（见 ShortcutsSection），这里不再重复。
// 配置经 UserPreferences 持久化；启用后 coordinator 才注册热键。

import { useTranslation } from 'react-i18next'
import { detectOS } from '../../components/WindowChrome'
import type { OpenCodeAgentPermissionMode, OpenCodeAgentProviderId } from '../../lib/types'
import { useHotkeySettings } from '../../state/HotkeySettingsContext'
import { Card } from '../_atoms'
import { SectionDesc, SectionTitle, SettingRow, Toggle, inputStyle } from './shared'

const PERMISSION_MODES: OpenCodeAgentPermissionMode[] = [
  'acceptEdits',
  'plan',
  'default',
  'bypassPermissions',
]

export function OpenCodeAgentSection() {
  const { t } = useTranslation()
  const { prefs, updatePrefs: savePrefs } = useHotkeySettings()
  const os = detectOS()

  if (os === 'win') return null

  if (!prefs) {
    return (
      <Card>
        <div style={{ fontSize: 12, color: 'var(--ol-ink-4)' }}>{t('common.loading')}</div>
      </Card>
    )
  }

  const enabled = prefs.opencodeAgentEnabled

  return (
    <Card>
      <SectionTitle>{t('settings.opencodeAgent.title')}</SectionTitle>
      <SectionDesc>{t('settings.opencodeAgent.desc')}</SectionDesc>

      <SettingRow label={t('settings.opencodeAgent.enable')} desc={t('settings.opencodeAgent.hotkeyHint')}>
        <Toggle
          on={enabled}
          onToggle={next => void savePrefs({ ...prefs, opencodeAgentEnabled: next })}
        />
      </SettingRow>

      {enabled && (
        <>
          {/* 「按住说话键」配置已挪到 通用 → 快捷键，避免和这里重复。本区只留后端/模型等高级项。 */}
          <SettingRow label={t('settings.opencodeAgent.provider')}>
            <select
              value={prefs.opencodeAgentProvider}
              onChange={e =>
                void savePrefs({
                  ...prefs,
                  opencodeAgentProvider: e.target.value as OpenCodeAgentProviderId,
                })
              }
              style={{ ...inputStyle, maxWidth: 240, cursor: 'pointer' }}
            >
              <option value="claude-code-cli">Claude Code</option>
              <option value="opencode-cli">{t('settings.opencodeAgent.providerOpenCodeSoon')}</option>
            </select>
          </SettingRow>

          <SettingRow label={t('settings.codingConsole.permissionMode')}>
            <select
              value={prefs.opencodeAgentPermissionMode}
              onChange={e =>
                void savePrefs({
                  ...prefs,
                  opencodeAgentPermissionMode: e.target.value as OpenCodeAgentPermissionMode,
                })
              }
              style={{ ...inputStyle, maxWidth: 240, cursor: 'pointer' }}
            >
              {PERMISSION_MODES.map(m => (
                <option key={m} value={m}>
                  {t(`settings.codingConsole.mode.${m}`)}
                </option>
              ))}
            </select>
          </SettingRow>

          <SettingRow label={t('settings.opencodeAgent.model')} desc={t('settings.opencodeAgent.modelHint')}>
            <select
              value={prefs.opencodeAgentModel ?? ''}
              onChange={e => {
                const v = e.target.value
                void savePrefs({ ...prefs, opencodeAgentModel: v === '' ? null : v })
              }}
              style={{ ...inputStyle, maxWidth: 240, cursor: 'pointer' }}
            >
              <option value="">{t('settings.opencodeAgent.modelDefault')}</option>
              <option value="haiku">Haiku</option>
              <option value="sonnet">Sonnet</option>
              <option value="opus">Opus</option>
            </select>
          </SettingRow>

          <SettingRow label={t('settings.codingConsole.workdir')} desc={t('settings.codingConsole.workdirDesc')}>
            <input
              type="text"
              value={prefs.opencodeAgentWorkdir ?? ''}
              placeholder={t('settings.codingConsole.workdirPlaceholder')}
              spellCheck={false}
              onChange={e => {
                const v = e.target.value.trim()
                void savePrefs({ ...prefs, opencodeAgentWorkdir: v === '' ? null : v })
              }}
              style={inputStyle}
            />
          </SettingRow>
        </>
      )}
    </Card>
  )
}
