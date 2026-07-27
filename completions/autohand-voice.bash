# Bash completion for the native autohand-voice CLI.
_autohand_voice_completions() {
    local current previous
    current="${COMP_WORDS[COMP_CWORD]}"
    previous="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=($(compgen -W "run transcribe check doctor config help version --help --version" -- "$current"))
        return
    fi

    if [[ "${COMP_WORDS[1]}" == "config" ]]; then
        case "$COMP_CWORD" in
            2)
                COMPREPLY=($(compgen -W "show set reset path" -- "$current"))
                ;;
            3)
                [[ "${COMP_WORDS[2]}" == "set" ]] &&
                    COMPREPLY=($(compgen -W "output ptt_key sounds" -- "$current"))
                ;;
            4)
                case "${COMP_WORDS[3]}" in
                    output) COMPREPLY=($(compgen -W "type clipboard" -- "$current")) ;;
                    ptt_key) COMPREPLY=($(compgen -W "control_option_space" -- "$current")) ;;
                    sounds) COMPREPLY=($(compgen -W "on off" -- "$current")) ;;
                esac
                ;;
        esac
    elif [[ "$previous" == "transcribe" ]]; then
        COMPREPLY=($(compgen -f -- "$current"))
    fi
}

complete -F _autohand_voice_completions autohand-voice
