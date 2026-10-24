#!/bin/sh

# GitHub Environment передаёт пароль только во время deploy job.
if [ -z "$ANSIBLE_VAULT_PASSWORD" ]; then
  echo "ANSIBLE_VAULT_PASSWORD is empty" >&2
  exit 1
fi

printf '%s' "$ANSIBLE_VAULT_PASSWORD"
