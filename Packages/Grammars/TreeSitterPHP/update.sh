#!/bin/sh
# Refreshes the vendored tree-sitter-php sources from an upstream tag.
# Usage: ./update.sh v0.24.2
set -eu
tag="${1:?usage: update.sh <tag>}"
tmp="$(mktemp -d)"
git clone --quiet --depth 1 --branch "$tag" https://github.com/tree-sitter/tree-sitter-php.git "$tmp"
cp "$tmp/php/src/parser.c" "$tmp/php/src/scanner.c" php/src/
cp -R "$tmp/php/src/tree_sitter" php/src/
cp "$tmp/common/scanner.h" common/
cp "$tmp/queries/highlights.scm" "$tmp/queries/injections.scm" Sources/TreeSitterPHP/queries/
cp "$tmp/LICENSE" LICENSE
sed -i '' "s/upstreamVersion = \".*\"/upstreamVersion = \"$tag\"/" Sources/TreeSitterPHP/PHPGrammar.swift
rm -rf "$tmp"
echo "Vendored tree-sitter-php $tag"
