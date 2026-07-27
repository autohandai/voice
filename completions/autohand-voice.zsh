#compdef autohand-voice

# Zsh completion for autohand-voice
# Install: copy to a directory in your $fpath (e.g., ~/.zsh/completions/)
# and add to ~/.zshrc: fpath=(~/.zsh/completions $fpath); autoload -Uz compinit && compinit

_autohand_voice_writing_styles=(
    'clean:Fixes punctuation, keeps your words'
    'professional:Professional tone and grammar'
    'bullets:Concise bullet points'
    'email:Polished email'
    'slack:Concise chat message'
    'technical:Precise technical wording'
    'tweet:Short social post'
    'raw:Exact transcription, no LLM processing'
)

_autohand_voice_quality_values=(
    'api:Local API backend'
    'fast:1.5B model'
    'balanced:2B model'
    'quality:3B model'
    '0:API backend'
    '1:Fast 1.5B model'
    '2:Balanced 2B model'
    '3:Quality 3B model'
)

_autohand_voice_stt_values=(
    'ane:Apple Neural Engine'
    'qwen3-asr:Qwen3-ASR'
    'parakeet:Parakeet MLX'
    'whisper:Whisper MLX'
    '0:ANE'
    '1:Qwen3-ASR'
    '2:Parakeet'
    '3:Whisper'
)

_autohand_voice_languages=(
    'auto:Automatic detection'
    'en:English'
    'pl:Polish'
    'de:German'
    'fr:French'
    'es:Spanish'
    'it:Italian'
    'pt:Portuguese'
    'nl:Dutch'
    'ja:Japanese'
    'zh:Chinese'
    'ko:Korean'
    'ru:Russian'
)

_autohand_voice_ptt_keys=(
    'ctrl_l:Left Control'
    'ctrl_r:Right Control'
    'cmd_r:Right Command'
    'alt_l:Left Option'
    'alt_r:Right Option'
)

_autohand_voice_command_keys=(
    'none:Disabled'
    'alt_r:Right Option'
    'alt_l:Left Option'
    'cmd_r:Right Command'
    'ctrl_r:Right Control'
)

_autohand_voice_sound_values=(
    'soft_pop:Gentle pop sound'
    'chime:Bell chime'
    'warm:Warm tone'
    'click:Click sound'
    'marimba:Marimba tone'
    'simple:Simple beep'
)

_autohand_voice_config_set_value() {
    local key=$words[4]
    case "$key" in
        writing_style) _describe 'writing style' _autohand_voice_writing_styles ;;
        quality) _describe 'quality preset' _autohand_voice_quality_values ;;
        stt) _describe 'STT engine' _autohand_voice_stt_values ;;
        input_language) _describe 'input language' _autohand_voice_languages ;;
        output_language) _describe 'output language' _autohand_voice_languages ;;
        ptt_key) _describe 'push-to-talk key' _autohand_voice_ptt_keys ;;
        command_key) _describe 'command key' _autohand_voice_command_keys ;;
        llm_cleanup) _values 'toggle' on off ;;
        sound) _describe 'sound preset' _autohand_voice_sound_values ;;
        llm_endpoint) _message 'host:port (e.g., localhost:11434)' ;;
        advanced_mode) _values 'toggle' on off ;;
        device_id) _values 'input device' auto default system none ;;
    esac
}

_autohand_voice_config_keys=(
    'writing_style:Writing style for LLM cleanup'
    'quality:Quality preset (LLM model size)'
    'stt:Speech-to-text engine'
    'input_language:Input language for transcription'
    'output_language:Output language (translation target)'
    'ptt_key:Push-to-talk key'
    'command_key:Command key (lock recording)'
    'llm_cleanup:Enable LLM text cleanup'
    'sound:Sound feedback preset'
    'llm_endpoint:LLM API endpoint (host\:port)'
    'advanced_mode:Enable advanced mode in menu bar'
    'device_id:Audio input device id'
)

_autohand_voice() {
    local -a commands
    commands=(
        'config:View and modify preferences'
        'stats:Show usage statistics'
        'status:Show system info and model status'
        'doctor:Run diagnostic checks'
        'devices:List audio input devices'
        'update:Update to the latest version'
    )

    _arguments -C \
        '(-h --help)'{-h,--help}'[Show help]' \
        '(-V --version)'{-V,--version}'[Show version]' \
        '(-f --foreground)'{-f,--foreground}'[Run in foreground]' \
        '1:command:->command' \
        '*::arg:->args'

    case "$state" in
        command)
            _describe 'autohand-voice command' commands
            ;;
        args)
            case $words[1] in
                config)
                    local -a config_subcmds
                    config_subcmds=(
                        'show:Show all current settings'
                        'set:Set a preference'
                        'reset:Reset all preferences to defaults'
                        'path:Show config file path'
                    )
                    case $CURRENT in
                        2) _describe 'config subcommand' config_subcmds ;;
                        3)
                            if [[ $words[2] == "set" ]]; then
                                _describe 'config key' _autohand_voice_config_keys
                            fi
                            ;;
                        4)
                            if [[ $words[2] == "set" ]]; then
                                _autohand_voice_config_set_value
                            fi
                            ;;
                    esac
                    ;;
            esac
            ;;
    esac
}

_autohand_voice "$@"
