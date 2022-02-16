Добавьте в конец Makefile вашего проекта:
```
include awesome.mk

awesome.mk:
	tmpdir=$$(mktemp -d) && \
		git clone --depth 1 repo://awesome-make.git $$tmpdir && \
		cp $$tmpdir/awesome.mk ./

```

