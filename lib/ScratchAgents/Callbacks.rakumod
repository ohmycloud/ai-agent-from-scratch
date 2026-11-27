unit module ScratchAgents::Callbacks;

use ScratchAgents::Context;
use ScratchAgents::Rag;
use ScratchAgents::Types;

constant @DANGEROUS-TOOLS is export = <delete_file send_email execute_sql delete-file send-email execute-sql>;

#| Request user approval before executing dangerous tools.
sub approval-callback(ExecutionContext $context, ToolCall $tool-call) is export {
    return Nil unless $tool-call.name eq any(@DANGEROUS-TOOLS);

    say "\n[!] Dangerous tool execution requested";
    say "Tool: { $tool-call.name }";
    say "Arguments: { $tool-call.arguments }";

    my $response = (prompt("Do you want to execute? (y/n): ") // '').lc.trim;
    if $response eq 'y' {
        say "Approved. Executing...\n";
        return Nil;
    } else {
        say "Denied. Skipping execution.\n";
        return "User denied execution of { $tool-call.name }";
    }
}

#| Extract the original search query from context for a given tool call ID.
sub extract-search-query(ExecutionContext $context, Str $tool-call-id --> Str) {
    for $context.events -> $event {
        for $event.content -> $item {
            if ($item ~~ ToolCall)
                && ($item.name eq 'search_web' | 'search-web')
                && ($item.tool-call-id eq $tool-call-id)
            {
                return ~($item.arguments<query> // '');
            }
        }
    }
    '';
}

#| After-tool callback that compresses large web search results via RAG chunking & search.
sub search-compressor(
    ExecutionContext $context,
    ToolResult       $tool-result,
    :&embedder = &get-embeddings,
) is export {
    return Nil unless $tool-result.name eq 'search_web' | 'search-web';
    return Nil unless $tool-result.content.elems;

    my $original = ~$tool-result.content[0];
    return Nil if $original.chars < 2000;

    my $query = extract-search-query($context, $tool-result.tool-call-id);
    return Nil unless $query;

    my @chunks     = fixed-length-chunking($original, :chunk-size(500), :overlap(50));
    my @embeddings = &embedder(@chunks);
    my @results    = vector-search($query, @chunks, @embeddings, :top-k(3), :&embedder);

    my $compressed = @results.map({ .<chunk> }).join("\n\n");

    ToolResult.new(
        tool-call-id => $tool-result.tool-call-id,
        name         => $tool-result.name,
        status       => 'success',
        content      => [$compressed],
    );
}

=begin pod

=head1 NAME

ScratchAgents::Callbacks - Built-in tool approval and result compression callbacks

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents;
use ScratchAgents::Callbacks;

my $agent = Agent.new(
    model                 => $llm,
    tools                 => @tools,
    before-tool-callbacks => [&approval-callback],
    after-tool-callbacks  => [&search-compressor],
);
=end code

=head1 DESCRIPTION

Exports reusable callback functions for C<Agent>:

=item C<@DANGEROUS-TOOLS> — List of tool names requiring interactive confirmation (e.g., C<delete_file>, C<send_email>, C<execute_sql>).
=item C<approval-callback(ExecutionContext $context, ToolCall $tool-call)> — Prompts the user on stdin before executing dangerous tools.
=item C<search-compressor(ExecutionContext $context, ToolResult $tool-result, :&embedder)> — Uses C<ScratchAgents::Rag> chunking and vector search to compress large C<search_web> outputs (> 2000 chars) down to the top-3 most relevant chunks.

=end pod
