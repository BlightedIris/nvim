//go:build tools

// Pins gopls (lsp.lua's `gopls` LSP) via go.sum in this isolated module, kept
// out of the repo root so it never becomes a dependency of anything built here.
// Install with: go install golang.org/x/tools/gopls (run from this directory,
// or `cd tools/go && go install golang.org/x/tools/gopls`).
package tools

import (
	_ "golang.org/x/tools/gopls"
)
