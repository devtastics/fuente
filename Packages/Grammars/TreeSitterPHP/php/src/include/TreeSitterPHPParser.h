#ifndef TREE_SITTER_PHP_PARSER_H
#define TREE_SITTER_PHP_PARSER_H

typedef struct TSLanguage TSLanguage;

#ifdef __cplusplus
extern "C" {
#endif

/// The tree-sitter language for PHP with embedded HTML (the `php` grammar, not `php_only`).
const TSLanguage *tree_sitter_php(void);

#ifdef __cplusplus
}
#endif

#endif
