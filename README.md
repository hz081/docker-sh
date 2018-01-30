# Docker utility script

This is simple POSIX script for managing docker container, just like `docker-compose`.

Because this is POSIX shell script, the possibility is limitless

This script is written with POSIX shell standard, so it will work with `bash`, `ash`, `dash` or any shell that follow POSIX standard

## How to use it
There are 2 way to use this script
- source `docker.sh` from your script
```sh
#!/bin/sh
. ./docker.sh

name=test_nginx
image=nginx:alpine
opts="
  -p 8080:80
"

main "$@"
```
- use it as interpreter, you need to install it in your `PATH`
```sh
#!/usr/env/bin docker.sh

name=test_nginx
image=nginx:alpine
opts="
  -p 8080:80
"
```

The things you need to set/define:

- `name` (string)
- `image` (string)
- `net` (string, optional)
- `opts` (array, optional)
- `args` (array, optional)
- `stop_opts` (array, optional)
- `rm_opts` (array, optional)
- `kill_opts` (array, optional)
- `pre_start` (function, optional), first parameter set to `run` if container not exists or `start` if container already exists
- `post_start` (function, optional), first parameter set to `run` if container not exists or `start` if container already exists
- `pre_stop` (function, optional)
- `post_stop` (function, optional)
- `pre_restart` (function, optional)
- `post_restart` (function, optional)
- `pre_rm` (function, optional)
- `post_rm` (function, optional)

when you use #2 method, `file` variable will be set

because POSIX shell does't support array, I provide `quote` function utility, to convert string to quoted one so you can use it in `eval` and `set` command
```shell
eval "set -- $(quote "a b 'c d' \"e'f\"")"
for x; do echo ">$x<"; done
```
will print:
```
>a<
>b<
>c d<
>e'f<
```

read `docker.sh` file if you need more information


## Example

content of `postgres/app`:
```sh
#!/usr/bin/env docker.sh

dir=$(cd "$(dirname "$file")"; pwd)
name=$(basename "$dir")-$(printf %s "$dir" | cksum |  awk '{print $1}')
image=postgres:9-alpine
net=net0
opts="
  --restart always
  -v '$dir/data:/var/lib/postgresql/data'
  -p 5432:5432
  --network-alias '$(basename "$dir")'
"
```

content of `pgadmin/app`:
```sh
#!/usr/bin/env docker.sh

dir=$(cd "$(dirname "$file")"; pwd)
vol_opts="-v '$dir/data:/pgadmin'"

name=$(basename "$dir")-$(printf %s "$dir" | cksum |  awk '{print $1}')
image=thajeztah/pgadmin4
net=net0
opts="
  --restart always
  $vol_opts
  -p 5050:5050
  --network-alias '$(basename "$dir")'
"

pre_start() (
  "$dir/../postgres/app" start || { echo 'failed to start postgres'; return 1; }
  if [ "${1:-}" = run ]; then
    # we need to chown the dir
    tmp=$(quote "$vol_opts") || return 1
    eval "set -- $tmp"
    docker run -it --rm \
      "$@" \
      -u 0:0 --entrypoint /bin/sh \
      "$image" -c 'chown pgadmin:pgadmin /pgadmin'
  fi
)
```
NOTE: Here i chown the folder before container start (can't be done with `docker-compose`)

don't forget to change permission so you can execute the script

    chmod 755 postgres/app pgadmin/app

now, you can run them with just on command

    pgadmin/app start
