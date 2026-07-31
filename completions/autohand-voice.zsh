#compdef autohand-voice

_autohand_voice() {
    local -a commands
    commands=(
        'run:Open the native menu bar app'
        'transcribe:Transcribe an audio file locally'
        'check:Check platform and permissions'
        'doctor:Show native diagnostics'
        'model-check:Validate the selected local model'
        'reliability:Inspect or export redacted reliability aggregates'
        'config:View or update preferences'
        'help:Show help'
        'version:Show version'
    )

    _arguments -C \
        '(-h --help)'{-h,--help}'[Show help]' \
        '--version[Show version]' \
        '1:command:->command' \
        '*::argument:->arguments'

    case "$state" in
        command)
            _describe 'command' commands
            ;;
        arguments)
            case "$words[2]" in
                transcribe)
                    _files
                    ;;
                check|doctor)
                    _values 'format' --json
                    ;;
                model-check)
                    _values 'format' --json
                    ;;
                reliability)
                    if (( CURRENT == 3 )); then
                        _values 'action' show path reset export --json
                    elif [[ "$words[3]" == "export" ]] && (( CURRENT == 4 )); then
                        _files
                    elif [[ "$words[3]" == "show" ]] && (( CURRENT == 4 )); then
                        _values 'format' --json
                    fi
                    ;;
                config)
                    if (( CURRENT == 3 )); then
                        _values 'action' show set reset path
                    elif [[ "$words[3]" == "set" ]] && (( CURRENT == 4 )); then
                        _values 'preference' output ptt_key recording_mode function_key_long_press model language sounds live_preview
                    elif [[ "$words[3]" == "set" ]] && (( CURRENT == 5 )); then
                        case "$words[4]" in
                            output) _values 'output mode' type clipboard ;;
                            ptt_key) _values 'push-to-talk key' control_option_space ;;
                            recording_mode) _values 'recording mode' press_and_hold toggle hands_free ;;
                            function_key_long_press) _values 'long-press Fn' on off ;;
                            model) _values 'model' v2 v3 ;;
                            sounds) _values 'sound feedback' on off ;;
                            live_preview) _values 'live provisional preview' on off ;;
                        esac
                    fi
                    ;;
            esac
            ;;
    esac
}

_autohand_voice "$@"
