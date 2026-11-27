unit module ScratchAgents::Utils;

use ScratchAgents::Types;

#| Print a readable trace of events recorded in an ExecutionContext.
sub display-trace($context) is export {
    for $context.events.kv -> $index, $event {
        say "\n[{ $index + 1 }] { $event.author }";
        for $event.content -> $item {
            given $item {
                when Message    { say "  { .role }: { .content }" }
                when ToolCall   { say "  tool call: { .name }({ .arguments })" }
                when ToolResult {
                    my $preview = .content.elems ?? ~.content[0] !! '';
                    say "  tool result: { .name } -> { $preview.substr(0, 500) }";
                }
            }
        }
    }
}

=begin pod

=head1 NAME

ScratchAgents::Utils - Execution trace formatting utilities

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Utils;

display-trace($result.context);
=end code

=head1 DESCRIPTION

Exports C<display-trace($context)>, which prints a numbered, human-readable transcript of every C<Event> (messages, tool calls, and truncated tool results) recorded in an C<ExecutionContext>.

=end pod
