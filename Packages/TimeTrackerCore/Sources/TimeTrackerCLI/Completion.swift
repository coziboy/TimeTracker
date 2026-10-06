/// A shell completion script, printed by `timetracker completion <shell>`.
///
/// Task names are not baked in: the scripts ask `timetracker __complete-tasks`
/// each time, so completion always offers the current list. Any `--file`
/// typed earlier on the line is passed along so it completes from that file.
public func completionScript(for shell: Shell) -> String {
  switch shell {
  case .zsh: zshScript
  case .bash: bashScript
  }
}

private let zshScript = #"""
  # timetracker zsh completion. Load with: eval "$(timetracker completion zsh)"
  _timetracker() {
    local -a commands file
    commands=(
      'list:Every task with its time'
      'status:Total time and how many timers run'
      'add:Add a task'
      'start:Start a task'"'"'s timer'
      'stop:Stop a task'"'"'s timer'
      'toggle:Start or stop a task'
      'reset:Zero a task, or --all'
      'rename:Rename a task'
      'set:Set a task'"'"'s time'
      'delete:Delete a task'
      'completion:Print a shell completion script'
      'help:Show usage'
    )

    # Find the command word, stepping over options such as --file <path>.
    local i=2 cmd
    while (( i < CURRENT )); do
      case $words[i] in
        --file) file=(--file "$words[i+1]"); (( i += 2 )); continue ;;
        -*) (( i++ )); continue ;;
      esac
      cmd=$words[i]
      break
    done

    [[ $words[CURRENT-1] == --file ]] && { _files; return; }
    if [[ -z $cmd ]]; then
      if [[ $PREFIX == -* ]]; then
        compadd -- --file --help
      else
        _describe -t commands 'timetracker command' commands
      fi
      return
    fi

    case $cmd in
      list|ls|status) compadd -- --json ;;
      add) compadd -- --start ;;
      completion) (( CURRENT == i + 1 )) && compadd zsh bash ;;
      start|stop|toggle|reset|rename|set|delete|rm)
        # Only the word right after the command is a task; rename's and set's
        # later words are a new title and a duration.
        (( CURRENT == i + 1 )) || return
        local -a tasks
        tasks=(${(f)"$(command timetracker $file __complete-tasks 2>/dev/null)"})
        compadd -M 'm:{a-zA-Z}={A-Za-z}' -a tasks
        [[ $cmd == reset ]] && compadd -- --all
        ;;
    esac
  }

  if ! (( $+functions[compdef] )); then
    autoload -Uz compinit && compinit
  fi
  compdef _timetracker timetracker
  """#

private let bashScript = #"""
  # timetracker bash completion. Load with: eval "$(timetracker completion bash)"
  _timetracker() {
    local cur="${COMP_WORDS[COMP_CWORD]}" cmd="" i=1
    local -a file=()

    # Find the command word, stepping over options such as --file <path>.
    while (( i < COMP_CWORD )); do
      case "${COMP_WORDS[i]}" in
        --file) file=(--file "${COMP_WORDS[i+1]}"); (( i += 2 )); continue ;;
        -*) (( i++ )); continue ;;
      esac
      cmd="${COMP_WORDS[i]}"
      break
    done

    if [[ "${COMP_WORDS[COMP_CWORD-1]}" == --file ]]; then
      COMPREPLY=($(compgen -f -- "$cur"))
      return
    fi
    if [[ -z "$cmd" ]]; then
      COMPREPLY=($(compgen -W "list status add start stop toggle reset rename set delete completion help --file --help" -- "$cur"))
      return
    fi

    COMPREPLY=()
    case "$cmd" in
      list|ls|status) COMPREPLY=($(compgen -W "--json" -- "$cur")) ;;
      add) COMPREPLY=($(compgen -W "--start" -- "$cur")) ;;
      completion) COMPREPLY=($(compgen -W "zsh bash" -- "$cur")) ;;
      start|stop|toggle|reset|rename|set|delete|rm)
        (( COMP_CWORD == i + 1 )) || return
        local title
        while IFS= read -r title; do
          # Escape spaces so a multi-word title stays one word.
          [[ "$title" == "$cur"* ]] && COMPREPLY+=("$(printf '%q' "$title")")
        done < <(command timetracker "${file[@]}" __complete-tasks 2>/dev/null)
        [[ "$cmd" == reset && --all == "$cur"* ]] && COMPREPLY+=(--all)
        ;;
    esac
  }
  complete -F _timetracker timetracker
  """#
