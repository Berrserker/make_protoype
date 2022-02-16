# Определяем дефолтную среду выполнения(фикс для darwin)
export SHELL := /bin/sh

# Читаемый хелп
.DEFAULT_GOAL := help-default
.PHONY: help-default
help-default: Makefile
	@sed -n 's/[ 	]*:[ 	]*/: /;s/^##/>/;/^>.*:/s/>/\x1b[1;32m\>\x1b[1;33m/;/^\x1b.*>\x1b.*/s/: /: \x1b[1;36m/p' $< *.mk


export GOPRIVATE="private repo name"

# Гошные переменные, если надо переписываем внутри своего мейка.
# https://golang.org/cmd/go/#hdr-Environment_variables
# Зачем нам компилить c по умолчанию?
export CGO_ENABLED=0

# Костыль для спасения от "missing go.sum entry for module" https://github.com/golang/go/issues/44129
# https://golang.org/ref/mod#build-commands
export GOFLAGS=-mod=mod

# Делаем доступными все установленные в модуле утилиты
export PATH := bin:$(PATH)

# Директория со скриптами миграции
MIGRATIONS_DIR := ./migrations

# Пути для кодогенерации конфига по умолчанию
CONFIG_CODEGEN_SOURCE := ./app/config.env.yml
CONFIG_CODEGEN_DEST := ./internal/config/generated.go
CONFIG_ENV_DEST := .env.local

# Дополнительные переменные окружения сборки для команды build-default
BUILD_BINARY_ENV?=

# Путь к скрипту запуска миграций БД
DB_MIGRATE_SCRIPT?=build/test/migrate.sh

# Хост на котором доступна БД postgres
DB_HOST?=localhost

# DSN подключения к БД postgres
DB_MASTER_DSN?=postgres://postgres:postgres@${DB_HOST}:5432/tests?sslmode=disable

# Версии используемых утилит. Можете переопределить в Makefile вашего сервиса после импорта.
GRPCURL_VERSION := v1.7.0
LINTER_VERSION :=v1.41.0
GOOSE_VERSION :=v2.7.0
GODOC_VERSION :=v0.1.0
GOMOCK_VERSION :=v1.5.0
CONFIG_VERSION :=v0.4.2

# Расположение утилит
LOCAL_BIN := $(CURDIR)/bin
GRPCURL_BIN := $(LOCAL_BIN)/grpcurl
LINTER_BIN := $(LOCAL_BIN)/golangci-lint
GOIMPORTS_BIN := $(LOCAL_BIN)/goimports
CONFIG_BIN := $(LOCAL_BIN)/config-gen
GOOSE_BIN := $(LOCAL_BIN)/goose
GODOC_BIN := $(LOCAL_BIN)/godoc
GOMOCK_BIN := $(LOCAL_BIN)/mockgen

## all : format test lint build
.PHONY: all-default
all-default: format test lint build


# .format для переданного списка файлов FORMAT_TARGETS проводит goimports чтобы схлопнуть импорты в один блок,
# затем при помощи sed убирает пустые строки внутри блока import,
# после чего выполняет ещё один проход goimports.
.PHONY: format-default
format-default: FORMAT_TARGETS := $(shell find . -not \( -path ./.git -prune \)  -not \( -path ./.idea -prune \) -not \( -path ./vendor -prune \) -type f -name '*.go')
format-default: .format


# Название модуля для использования в local извлекается автоматически из
.format: IS_DARWIN := $(filter Darwin,$(shell uname -s))
.format: SED_FIX := $(if $(IS_DARWIN), '',)
.format: MODULE_NAME := $(shell test -f go.mod && go list -m)
.format: install-goimports
ifneq ($(wildcard go.mod),)
	@[ ! -z "$(FORMAT_TARGETS)" ] || exit 0 && $(GOIMPORTS_BIN) -format-only -local $(MODULE_NAME) -w $(FORMAT_TARGETS) \
		&& echo $(FORMAT_TARGETS) | xargs sed -i $(SED_FIX) '/import (/,/)/{/^\s*$$/d;}' \
		&& $(GOIMPORTS_BIN) -format-only -local $(MODULE_NAME) -w $(FORMAT_TARGETS)
endif

## setup-default: пробежит все инсталяторы
.PHONY: setup-default
setup-default: install-goimports install-grpcurl install-lint install-goose install-config-gen

## install-goimports: поставит goimports
.PHONY: install-goimports
install-goimports:
	$(call fn_install_goutil,golang.org/x/tools/cmd/goimports,latest,$(GOIMPORTS_BIN))

## install-grpcurl: поставит grpcurl
.PHONY: install-grpcurl
install-grpcurl:
	$(call fn_install_goutil,github.com/fullstorydev/grpcurl/cmd/grpcurl,$(GRPCURL_VERSION),$(GRPCURL_BIN))

## install-lint: поставит линтер
.PHONY: install-lint
install-lint:
	$(call fn_install_goutil,github.com/golangci/golangci-lint/cmd/golangci-lint,$(LINTER_VERSION),$(LINTER_BIN))

## install-goose: поставит гуся
.PHONY: install-goose
install-goose:
	$(call fn_install_goutil,github.com/pressly/goose/cmd/goose,$(GOOSE_VERSION),$(GOOSE_BIN),"-tags='no_mysql no_sqlite3'")


## install-godoc: установит godoc
.PHONY: install-godoc
install-godoc:
	$(call fn_install_goutil,golang.org/x/tools/cmd/godoc,$(GODOC_VERSION),$(GODOC_BIN))
	
.PHONY: install-gomock
install-gomock:
	$(call fn_install_goutil,github.com/golang/mock/mockgen,$(GOMOCK_VERSION),$(GOMOCK_BIN))

# fn_install_goutil устанавливает бинарь из гошного пакета.
# Параметры:
# 1 - uri пакета для сборки бинаря;
# 2 - версия пакета вида vX.Y.Z или latest;
# 3 - полный путь для установки бинаря.
# 4 - опциональные build флаги
# Работает не через go install, чтобы иметь возможность использовать разные версии в разных модулях и не добавлять пакет в зависимости текущего модуля.
# Проверяет наличие бинаря, создаёт временную директорию, инициализирует в ней временный модуль, в котором вызывает установку и сборку бинаря.
define fn_install_goutil
	@[ ! -f $(3)@$(2) ] \
		|| exit 0 \
		&& echo "Install $(1) ..." \
		&& tmp=$$(mktemp -d) \
		&& cd $$tmp \
		&& echo "Module: $(1)" \
		&& echo "Version: $(2)" \
		&& echo "Binary: $(3)" \
		&& echo "Temp: $$tmp" \
		&& go mod init temp && go get -d $(1)@$(2) && go build $(4) -o $(3)@$(2) $(1) \
		&& ln -sf $(3)@$(2) $(3) \
		&& rm -rf $$tmp \
		&& echo "$(3) installed!" \
		&& echo "********************************"
endef

## mod-download : go mod download
.PHONY: mod-download
mod-download:
	go mod download

## lint : линтер - $(LINTER_BIN) run
.PHONY: lint-default
lint-default: install-lint
ifneq ($(wildcard go.mod),)
	$(LINTER_BIN) run
endif

## test : CGO_ENABLED=1 go test -race -count=1 ./...
.PHONY: test-default
test-default:
ifneq ($(wildcard go.mod),)
	CGO_ENABLED=1 go test -race -count=1 ./...
endif

## migrate : goose up migration(deprecated)
.PHONY: migrate-default
migrate-default: install-goose
ifneq ($(wildcard $(MIGRATIONS_DIR)),)
	@[ -z "${MIGRATE_DB_DSN}" ] && echo "MIGRATE_DB_DSN variable is empty!" && exit 1 || \
		$(GOOSE_BIN) -dir $(MIGRATIONS_DIR) postgres "${MIGRATE_DB_DSN}" up
endif

## migration : create migration
.PHONY: migration
migration: install-goose
ifneq ($(wildcard $(MIGRATIONS_DIR)),)
	@read -p "Enter migration name: " migration_name; \
	goose -dir $(MIGRATIONS_DIR) create $$migration_name sql
endif

# Костыль, позволяющий избежать предупреждений о переопределении целей.
%:  %-default
	@  true

## doc : поднимет сервак godoc http://localhost:6060/pkg и откроет в браузере
.PHONY: doc
doc: IS_DARWIN := $(filter Darwin,$(shell uname -s))
doc: URL_OPENER := $(if $(IS_DARWIN), 'open', 'xdg-open')
doc: MODULE_NAME := $(shell test -f go.mod && go list -m)
doc: install-godoc
	sh -c "sleep 3 && $(URL_OPENER) http://localhost:6060/pkg/$(MODULE_NAME)?m=all" &
	$(GODOC_BIN) -http=:6060

## update-awesomemk : Обновление awesome.mk
.PHONY: update-awesomemk
update-awesomemk:
	$(call copy_file,awesome.mk,awesome.mk)

define copy_file
	tmpdir=$$(mktemp -d) && \
	git clone -b ${REPOSITARY_BRANCH} --depth 1 https://git.hte.team/go/awesome-make.git $$tmpdir && \ #TODO: make a makelib repo
	cp $$tmpdir/${1} ${2}
endef
