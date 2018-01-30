#!/bin/sh

# Author: win@payfazz.com

# Note:
# every code must compatible with POSIX shell

quote() (
  ret=; nl=$(printf '\nx'); nl=${nl%x}; no_proc=${no_proc:-n}; count=${count:--1}
  for next; do
    char=; current=; state=discard; read=y; backslash_ret=
    while [ "$count" != 0 ]; do
      case $read in
      n)  read=y ;;
      y)  case $next in "") case $state in
            discard)        break ;;
            normal)         ret="$ret'$current' "; count=$((count-1))
                            break ;;
            backslash)      echo 'premature end of string' >&2; return 1 ;;
            single|double)  echo "unmatched $state quote" >&2; return 1 ;;
          esac ;; esac
          char=${next%"${next#?}"}; next=${next#"$char"} ;;
      esac
      case $state in
      discard)    case $char in [!$IFS]) state=normal; read=n ;; esac ;;
      normal)     case $no_proc in
                  n)  case $char in
                      \\)     backslash_ret=$state; state=backslash ;;
                      \')     state=single; ;;
                      \")     state=double; ;;
                      [$IFS]) ret="$ret'$current' "; count=$((count-1))
                              current=; state=discard ;;
                      *)      current="$current$char" ;;
                      esac ;;
                  y)  case $char in
                      \')     current="$current'\\''" ;;
                      [$IFS]) ret="$ret'$current' "; count=$((count-1))
                              current=; state=discard ;;
                      *)      current="$current$char" ;;
                      esac ;;
                  esac ;;
      backslash)  state=$backslash_ret
                  case $char in
                  $nl) : ;;
                  \') current="$current\\'\\''" ;;
                  *)  current="$current\\$char" ;;
                  esac ;;
      single)     case $char in
                  \') state=normal ;;
                  *)  current="$current$char" ;;
                  esac ;;
      double)     case $char in
                  \\) backslash_ret=$state; state=backslash ;;
                  \') current="$current'\\''" ;;
                  \") state=normal ;;
                  *)  current="$current$char" ;;
                  esac ;;
      esac
    done
  done
  printf '%s\n' "${ret% }"
)

exists() {
  case $1 in
  network|volume) [ "$(docker "$1" inspect -f ok "$2" 2>/dev/null)" = ok ] ;;
  *)              [ "$(docker inspect --type "$1" -f ok "$2" 2>/dev/null)" = ok ] ;;
  esac
}

running() {
  [ "$(docker inspect --type container -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]
}

construct_run_cmds() (
  ret="$(quote "${opts:-}") " || { echo 'cannot process "opts"' >&2; return 1; }
  eval "set -- $ret"
  for arg; do
    case $arg in
    --name|--net|--network) printf '"opts" cannot contain "%s"\n' "$arg" >&2; return 1 ;;
    esac
  done
  ret="$ret'--detach' '--name' "
  [ -z "${name:-}" ] && { echo '"name" cannot be empty' >&2; return 1; }
  ret="$ret$(no_proc=y count=1 quote "$name") "
  [ -n "${net:-}" ] && ret="$ret'--network' $(no_proc=y count=1 quote "$net") "
  [ -z "${image:-}" ] && { echo '"image" cannot be empty' >&2; return 1; }
  ret="$ret$(no_proc=y count=1 quote "$image") "
  ret="$ret$(quote "${args:-}")" || { echo 'cannot process "args"' >&2; return 1; }
  ret=${ret# }
  ret=${ret% }
  printf %s "$ret"
)

gc_network() {
  [ "$(docker network inspect -f '{{index .Labels "kurnia_d_win.docker.autoremove"}}{{.Containers|len}}' "$1" 2>/dev/null)" = true0 ] \
  && docker network rm "$1" >/dev/null 2>&1
  return 0
}

exec_fn_opt() (
  if type "$1" 2>/dev/null | grep -q -F function; then
    "$@" || {
      tmp=$?
      printf '"%s" return %d\n' "$1" $tmp >&2
      return $tmp
    }
  fi
  return 0
)

main() (
  [ $# -gt 0 ] && { action=$1; shift; }
  constructed_run_cmds=$(construct_run_cmds) || return $?
  case ${action:-} in
    start)
      if ! running "$name"; then
        if ! exists container "$name"; then
          exec_fn_opt "pre_$action" run || return $?
          [ -n "${net:-}" ] && ! exists network "$net" && {
            docker network create --driver bridge --label kurnia_d_win.docker.autoremove=true "$net" >/dev/null \
            || { printf 'cannot create network "%s"\n' "$net" >&2; return 1; }
          }
          eval "set -- $constructed_run_cmds"
          docker run --label "kurnia_d_win.docker.run_opts=$constructed_run_cmds" "$@" >/dev/null || return $?
          exec_fn_opt "post_$action" run
        else
          exec_fn_opt "pre_$action" start || return $?
          docker start "$name" >/dev/null || return $?
          exec_fn_opt "post_$action" start
        fi
      fi
      return $?
      ;;

    stop|restart)
      if running "$name"; then
        tmp=$(no_proc=y quote "${stop_opts:-}" "$@")
        eval "set -- $tmp"
        tmp_opts=; i=1
        while [ $i -le $# ]; do
          a=$(eval echo \${$i})
          case $a in
          -t|--time)
            i=$((i+1)); a=$(eval echo \${$i})
            tmp_opts="$tmp_opts'--time' $(no_proc=y count=1 quote "$a") "
            ;;
          esac
          i=$((i+1))
        done
        exec_fn_opt "pre_$action" || return $?
        eval "set -- $tmp_opts"
        docker "$action" "$@" "$name" >/dev/null || return $?
        exec_fn_opt "post_$action"
      elif [ "$action" = restart ]; then
        echo 'container is not running' >&2
        return 1
      fi
      return $?
      ;;

    rm)
      if exists container "$name"; then
        tmp=$(no_proc=y quote "${rm_opts:-}" "$@")
        eval "set -- $tmp"
        tmp_opts=; i=1
        while [ $i -le $# ]; do
          a=$(eval echo \${$i})
          case $a in
            -[fvl]|-[fvl][fvl]|-[fvl][fvl][fvl]) tmp_opts="$tmp_opts$a " ;;
            --force|--volumes|--link) tmp_opts="$tmp_opts$a " ;;
          esac
          i=$((i+1))
        done
        saved_run_cmds=$(docker inspect -f '{{index .Config.Labels "kurnia_d_win.docker.run_opts"}}' "$name" 2>/dev/null)
        saved_run_cmds=$(no_proc=y quote "$saved_run_cmds")
        exec_fn_opt "pre_$action" || return $?
        docker rm $tmp_opts "$name" >/dev/null || return $?
        exec_fn_opt "post_$action" || return $?
        eval "set -- $saved_run_cmds"
        init_net=; i=1
        while [ $i -le $# ]; do
          a=$(eval echo \${$i})
          case $a in
          "'--network'")
            i=$((i+1)); a=$(eval echo \${$i})
            init_net=${a%"'"}
            init_net=${init_net#"'"}
            break
            ;;
          esac
          i=$((i+1))
        done
        [ -n "$init_net" ] && gc_network "$init_net" || :
      fi
      return $?
      ;;

    exec|exec_root)
      if running "$name"; then
        [ $# = 0 ] && { echo 'no command to execute' >&2; return 1; }
        tmp_opts='--interactive '
        [ "$action" = exec_root ] && tmp_opts="$tmp_opts--user 0:0 "
        [ -t 0 -a -t 1 -a -t 2 ] && tmp_opts="$tmp_opts--tty "
        exec docker exec $tmp_opts "$name" "$@"
      else
        echo 'container is not running' >&2
      fi
      return 1
      ;;

    kill)
      if running "$name"; then
        tmp=$(no_proc=y quote "${kill_opts:-}" "$@")
        eval "set -- $tmp"
        tmp_opts=; i=1
        while [ $i -le $# ]; do
          a=$(eval echo \${$i})
          case $a in
          -s|--signal)
            i=$((i+1)); a=$(eval echo \${$i})
            tmp_opts="$tmp_opts'--signal' $(no_proc=y count=1 quote "$a") "
            ;;
          esac
          i=$((i+1))
        done
        eval "set -- $tmp_opts"
        docker kill "$@" "$name" >/dev/null
      else
        echo 'container is not running' >&2
        return 1
      fi
      return $?
      ;;

    logs|port)
      if running "$name"; then
        docker "$action" "$name" "$@"
      else
        echo 'container is not running' >&2
        return 1
      fi
      return $?
      ;;

    status)
      if exists container "$name"; then
        if [ "$(docker inspect -f '{{index .Config.Labels "kurnia_d_win.docker.run_opts"}}' "$name" 2>/dev/null)" != "$constructed_run_cmds" ]; then
          printf 'different_opts '
        fi
        if [ "$(docker inspect --type image -f '{{.Id}}' "$image" 2>/dev/null)" != "$(docker inspect --type container -f '{{.Image}}' "$name" 2>/dev/null)" ]; then
          printf 'different_image '
        fi
        if running "$name"; then
          printf 'running\n'
        else
          printf 'not_running\n'
        fi
      else
        printf 'no_container\n'
      fi
      return 0
      ;;

    name) echo "$name"; return 0 ;;
    show_cmds) echo "$constructed_run_cmds"; return 0 ;;

    show_running_cmds)
      if exists container "$name"; then
        docker inspect -f '{{index .Config.Labels "kurnia_d_win.docker.run_opts"}}' "$name" 2>/dev/null;
      else
        echo "container not exists" >&2
        return 1
      fi
      return $?
      ;;

    *)
      cat <<EOF >&2
Available commands:
  start              Start the container
  stop               Stop the container
  restart            Restart the container
  rm                 Remove the container
  exec               Exec program inside the container
  exec_root          Exec program inside the container (as root)
  kill               Force kill the container
  logs               Show the log of the container
  port               Show port forwarding
  status             Show status of the container
  name               Show the name of the container
  show_cmds          Show the arguments to docker run
  show_running_cmds  Show the arguments to docker run in current running container
EOF
      exit 1
      ;;
  esac
)

if grep -qF 6245455020934bb2ad75ce52bbdc54b7 "$0" 2>/dev/null; then
  if ! [ -r "${1:-}" ]; then
    printf 'Usage: %s <file> <command> [args...]\n' "$0" >&2
    exit 1
  fi
  file=$1; shift
  . "$file" || exit 1
  main "$@"
fi
