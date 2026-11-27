unit module ScratchAgents::Memory::ContextOptimizer;

use JSON::Fast;
use Tokenizers;
use ScratchAgents::Context;
use ScratchAgents::Llm;
use ScratchAgents::Types;

#| Count tokens in a text using a Tokenizers instance, custom encoder, or UTF-8 heuristic.
sub estimate-tokens(Str $text, :$tokenizer = Nil, :&encoder = Nil --> Int) {
    return 0 unless $text.chars;
    if $tokenizer.defined {
        return $tokenizer.count($text, :!add-special-tokens);
    }
    if &encoder.defined {
        my $res = &encoder($text);
        return $res ~~ Int ?? $res !! $res.elems;
    }
    # Fallback BPE-style heuristic (~4 UTF-8 bytes per token)
    max(1, ($text.encode('utf-8').elems / 4).ceiling);
}

#| Create a before_llm_callback that triggers optimization when token count exceeds threshold.
sub create-optimizer-callback(&apply-optimization, Int :$threshold = 50000, :$tokenizer = Nil, :&encoder = Nil) is export {
    sub (ExecutionContext $context, LlmRequest $request) {
        my $tokens = count-tokens($request, :$tokenizer, :&encoder);
        return Nil if $tokens < $threshold;

        my $res = &apply-optimization($context, $request);
        await $res if $res ~~ Promise;
        Nil;
    }
}

#| Calculate total token count of an LlmRequest.
sub count-tokens(LlmRequest $request, :$tokenizer = Nil, :&encoder = Nil --> Int) is export {
    my @messages = build-messages($request);
    my Int $total = 0;

    for @messages -> %msg {
        $total += 4;  # per-message overhead

        if %msg<content>.defined {
            $total += estimate-tokens(~%msg<content>, :$tokenizer, :&encoder);
        }

        if %msg<tool_calls>.defined {
            for %msg<tool_calls>.list -> %tc {
                my %func = %tc<function> // {};
                $total += estimate-tokens(~%func<name>, :$tokenizer, :&encoder) if %func<name>;
                $total += estimate-tokens(~%func<arguments>, :$tokenizer, :&encoder) if %func<arguments>;
            }
        }
    }

    if $request.tools.elems {
        for $request.tools -> $tool {
            if $tool.tool-definition.defined {
                $total += estimate-tokens(to-json($tool.tool-definition, :!pretty), :$tokenizer, :&encoder);
            }
        }
    }

    $total;
}

#| Sliding window strategy that preserves through the first user message and keeps only the most recent N items.
sub apply-sliding-window(
    ExecutionContext $context,
    LlmRequest       $request,
    Int              :$window-size = 20,
) is export {
    my @contents = $request.contents;

    my $user-idx = @contents.first({ $_ ~~ Message && .role eq 'user' }, :k);
    return unless $user-idx.defined;

    my @preserved = @contents[0 .. $user-idx];
    my @remaining = @contents[$user-idx + 1 .. *];
    if @remaining.elems > $window-size {
        @remaining = @remaining[* - $window-size .. *];
    }

    $request.contents = [|@preserved, |@remaining];
}

constant %TOOLCALL-COMPACTION-RULES is export = (
    create_file => '[Content saved to file]',
    create-file => '[Content saved to file]',
);

constant %TOOLRESULT-COMPACTION-RULES is export = (
    read_file     => 'File content from {file_path}. Re-read if needed.',
    read-file     => 'File content from {file_path}. Re-read if needed.',
    search_web    => 'Search results processed. Query: {query}. Re-search if needed.',
    search-web    => 'Search results processed. Query: {query}. Re-search if needed.',
    tavily_search => 'Search results processed. Query: {query}. Re-search if needed.',
);

#| Compress bulky tool call arguments and tool results into reference placeholders.
sub apply-compaction(ExecutionContext $context, LlmRequest $request) is export {
    my %tool-call-args;
    my @compacted;

    for $request.contents -> $item {
        given $item {
            when ToolCall {
                %tool-call-args{.tool-call-id} = .arguments;
                if %TOOLCALL-COMPACTION-RULES{.name}:exists {
                    my %compressed-args;
                    for .arguments.kv -> $k, $v {
                        %compressed-args{$k} = $k eq 'content'
                            ?? %TOOLCALL-COMPACTION-RULES{.name}
                            !! $v;
                    }
                    @compacted.push(ToolCall.new(
                        tool-call-id => .tool-call-id,
                        name         => .name,
                        arguments    => %compressed-args,
                    ));
                } else {
                    @compacted.push($item);
                }
            }
            when ToolResult {
                if %TOOLRESULT-COMPACTION-RULES{.name}:exists {
                    my %args = %tool-call-args{.tool-call-id} // {};
                    my $tmpl = %TOOLRESULT-COMPACTION-RULES{.name};
                    my $fp   = ~(%args<file_path> // %args<file-path> // %args<path> // 'unknown');
                    my $q    = ~(%args<query> // 'unknown');
                    my $msg  = $tmpl.subst('{file_path}', $fp).subst('{query}', $q);
                    @compacted.push(ToolResult.new(
                        tool-call-id => .tool-call-id,
                        name         => .name,
                        status       => .status,
                        content      => [$msg],
                    ));
                } else {
                    @compacted.push($item);
                }
            }
            default {
                @compacted.push($item);
            }
        }
    }

    $request.contents = @compacted;
}

my constant $SUMMARIZATION-PROMPT = q:to/END/;
You are summarizing an AI agent's work progress.

Given the following execution history, extract:
1. Key findings: Important information discovered
2. Tools used: List of tools that were called
3. Current status: What has been accomplished and what remains

Be concise. Focus on information that will help the agent continue its work.

Execution History:
{history}

Provide a structured summary.
END

#| Convert ContentItem list into readable text for summarization.
sub format-history-for-summary(@items --> Str) is export {
    my @lines;
    for @items -> $item {
        given $item {
            when Message    { @lines.push("[{ .role }]: { .content.substr(0, 500) }...") }
            when ToolCall   { @lines.push("[Tool Call]: { .name }({ .arguments })") }
            when ToolResult {
                my $preview = .content.elems ?? (~.content[0]).substr(0, 200) !! '';
                @lines.push("[Tool Result]: { .name } -> $preview...");
            }
        }
    }
    @lines.join("\n");
}

#| Generate history summary using an LLM client.
sub generate-summary(LlmClient $llm-client, Str $history --> Str) is export {
    my $request = LlmRequest.new(
        instructions => [$SUMMARIZATION-PROMPT.subst('{history}', $history)],
        contents     => [Message.new(role => 'user', content => 'Please summarize.')],
    );

    my $response = $llm-client.generate($request);
    for $response.content -> $item {
        return $item.content if $item ~~ Message;
    }
    '';
}

#| Replace older messages with an LLM-generated summary stored in instructions.
sub apply-summarization(
    ExecutionContext $context,
    LlmRequest       $request,
    LlmClient        $llm-client,
    Int              :$keep-recent = 5,
) is export {
    my @contents = $request.contents;

    my $user-idx = @contents.first({ $_ ~~ Message && .role eq 'user' }, :k);
    return unless $user-idx.defined;

    my $last-summary-idx = $context.state<last_summary_idx> // $user-idx;
    my $summary-start    = $last-summary-idx + 1;
    my $summary-end      = @contents.elems - $keep-recent;

    return if $summary-end <= $summary-start;

    my @preserved-start = @contents[0 .. $last-summary-idx];
    my @preserved-end   = @contents[$summary-end .. *];
    my @to-summarize    = @contents[$summary-start ..^ $summary-end];

    my $history-text = format-history-for-summary(@to-summarize);
    my $summary      = generate-summary($llm-client, $history-text);

    $request.append-instructions("[Previous work summary]\n$summary");
    $request.contents = [|@preserved-start, |@preserved-end];
    $context.state<last_summary_idx> = @preserved-start.elems - 1;
}

#| Hierarchical context optimization strategy usable as a before-LLM callback.
class ContextOptimizer is export {
    has LlmClient $.llm-client           is required;
    has Int       $.token-threshold      = 50000;
    has Bool      $.enable-compaction    = True;
    has Bool      $.enable-summarization = True;
    has Int       $.keep-recent          = 5;
    has           $.tokenizer            = Nil;
    has           &.encoder              = Nil;

    method CALL-ME(ExecutionContext $context, LlmRequest $request) {
        return Nil if count-tokens($request, :$!tokenizer, :&!encoder) < $!token-threshold;

        if $!enable-compaction {
            apply-compaction($context, $request);
            return Nil if count-tokens($request, :$!tokenizer, :&!encoder) < $!token-threshold;
        }

        if $!enable-summarization {
            apply-summarization($context, $request, $!llm-client, :$!keep-recent);
        }

        Nil;
    }
}
