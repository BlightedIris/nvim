require("minuet").setup({
    provider = 'openai_fim_compatible',
    n_completions = 1, -- one completion is plenty for a local model; more just burns GPU time
    -- minuet's own recommended starting point for local Ollama models; raise
    -- once time-to-first-suggestion is confirmed acceptable at this size
    context_window = 512,
    -- Measured latency is dominated by ~2.1-2.5s of fixed per-request
    -- overhead, not context size or token count (confirmed: 8 vs 56
    -- generated tokens took the same time). This does NOT fix that latency,
    -- but it does shrink the model's resident VRAM footprint (4.8GB vs
    -- 8.2GB at the default 32K context), which matters when both FIM and
    -- chat models are loaded together.
    -- defaults (throttle 1000ms / debounce 400ms) are tuned to avoid cost and
    -- rate limits on paid cloud APIs; local Ollama has neither concern
    throttle = 200,
    debounce = 200,
    provider_options = {
        openai_fim_compatible = {
            -- Windows has no TERM env var; Ollama ignores the value and only
            -- requires a non-empty placeholder (per minuet's own README note)
            api_key = 'APPDATA',
            name = 'Ollama',
            end_point = 'http://localhost:11434/v1/completions',
            -- Custom Modelfile alias (`ollama create qwen2.5-coder-fim`) that
            -- pins num_ctx=2048 on top of qwen2.5-coder:7b. Ollama's Windows
            -- app hardcodes its own OLLAMA_CONTEXT_LENGTH internally and
            -- ignores env vars set by whatever launches it, so a per-model
            -- Modelfile parameter is the only reliable way to shrink context.
            model = 'qwen2.5-coder-fim',
            optional = {
                max_tokens = 56,
                top_p = 0.9,
            },
        },
    },
})
