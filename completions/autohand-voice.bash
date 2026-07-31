# Bash completion for the native autohand-voice CLI.
_autohand_voice_completions() {
    local current previous
    current="${COMP_WORDS[COMP_CWORD]}"
    previous="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=($(compgen -W "run transcribe check doctor model-check reliability config help version --help --version" -- "$current"))
        return
    fi

    if [[ "${COMP_WORDS[1]}" == "config" ]]; then
        case "$COMP_CWORD" in
            2)
                COMPREPLY=($(compgen -W "show set reset path" -- "$current"))
                ;;
            3)
                [[ "${COMP_WORDS[2]}" == "set" ]] &&
                    COMPREPLY=($(compgen -W "output ptt_key recording_mode function_key_long_press model language sounds live_preview" -- "$current"))
                ;;
            4)
                case "${COMP_WORDS[3]}" in
                    output) COMPREPLY=($(compgen -W "type clipboard" -- "$current")) ;;
                    ptt_key) COMPREPLY=($(compgen -W "control_option_space" -- "$current")) ;;
                    recording_mode) COMPREPLY=($(compgen -W "press_and_hold toggle hands_free" -- "$current")) ;;
                    function_key_long_press) COMPREPLY=($(compgen -W "on off" -- "$current")) ;;
                    model) COMPREPLY=($(compgen -W "v2 v3" -- "$current")) ;;
                    sounds) COMPREPLY=($(compgen -W "on off" -- "$current")) ;;
                    live_preview) COMPREPLY=($(compgen -W "on off" -- "$current")) ;;
                esac
                ;;
        esac
    elif [[ "${COMP_WORDS[1]}" == "reliability" ]]; then
        if [[ "$COMP_CWORD" -eq 2 ]]; then
            COMPREPLY=($(compgen -W "show path reset export --json" -- "$current"))
        elif [[ "${COMP_WORDS[2]}" == "export" && "$COMP_CWORD" -eq 3 ]]; then
            COMPREPLY=($(compgen -f -- "$current"))
        fi
    elif [[ "$previous" == "transcribe" ]]; then
        COMPREPLY=($(compgen -f -- "$current"))
    fi
}

complete -F _autohand_voice_completions autohand-voice
