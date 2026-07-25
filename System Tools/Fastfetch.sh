#!/bin/bash

source "$JSF_RUNTIME_CORE_PATH" || {
    echo "Fatal: failed to source JS-Forge runtime." >&2
    exit 1
}

jsf_init_runtime_core

jsf_require_all \
  --native fastfetch \

fastfetch
