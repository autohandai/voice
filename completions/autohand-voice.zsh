#compdef autohand-voice

_autohand_voice() {
    local -a commands
    commands=(
        'run:Open the native menu bar app'
        'transcribe:Transcribe an audio file locally'
        'check:Check platform and permissions'
        'doctor:Show native diagnostics'
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
                config)
                    if (( CURRENT == 3 )); then
                        _values 'action' show set reset path
                    elif [[ "$words[3]" == "set" ]] && (( CURRENT == 4 )); then
                        _values 'preference' output ptt_key sounds
                    elif [[ "$words[3]" == "set" ]] && (( CURRENT == 5 )); then
                        case "$words[4]" in
                            output) _values 'output mode' type clipboard ;;
                            ptt_key) _values 'push-to-talk key' right_option right_control ;;
                            sounds) _values 'sound feedback' on off ;;
                        esac
                    fi
                    ;;
            esac
            ;;
    esac
}

_autohand_voice "$@"
