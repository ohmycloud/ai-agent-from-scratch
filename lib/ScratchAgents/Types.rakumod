unit module ScratchAgents::Types;

use JSON::Fast;
use UUID;

#| A text message in the conversation.
class Message is export {
    has Str $.type    = 'message';
    has Str $.role    is required where * ~~ 'system' | 'user' | 'assistant';
    has Str $.content is required;

    method to-hash(--> Hash) {
        { :$!type, :$!role, :$!content }
    }

    method from-hash(%h --> Message) {
        Message.new(role => ~%h<role>, content => ~(%h<content> // ''))
    }

    method deep-clone(--> Message) {
        Message.new(role => $!role, content => $!content);
    }
}

#| Deeply copy nested data structures (Hash, Array, ContentItem, Event).
sub deep-copy($val) is export {
    return $val unless $val.defined;
    given $val {
        when Hash {
            my %copy;
            for $val.kv -> $k, $v {
                %copy{$k} = deep-copy($v);
            }
            return %copy;
        }
        when Array {
            return $val.map({ deep-copy($_) }).Array;
        }
        when *.^can('deep-clone') {
            return $val.deep-clone;
        }
        default {
            return $val;
        }
    }
}

#| LLM's request to execute a tool.
class ToolCall is export {
    has Str $.type         = 'tool_call';
    has Str $.tool-call-id is required;
    has Str $.name         is required;
    has     %.arguments;

    method to-hash(--> Hash) {
        { :$!type, tool-call-id => $!tool-call-id, :$!name, :%.arguments }
    }

    method from-hash(%h --> ToolCall) {
        ToolCall.new(
            tool-call-id => ~(%h<tool-call-id> // %h<tool_call_id>),
            name         => ~%h<name>,
            arguments    => (%h<arguments> // {}).Hash,
        )
    }

    method deep-clone(--> ToolCall) {
        ToolCall.new(
            tool-call-id => $!tool-call-id,
            name         => $!name,
            arguments    => deep-copy(%!arguments),
        );
    }
}

#| Result from tool execution.
class ToolResult is export {
    has Str $.type         = 'tool_call_result' ~ '' eq '' ?? 'tool_result' !! 'tool_result';
    has Str $.tool-call-id is required;
    has Str $.name         is required;
    has Str $.status       is required where * ~~ 'success' | 'error';
    has     @.content;

    method to-hash(--> Hash) {
        { :$!type, tool-call-id => $!tool-call-id, :$!name, :$!status, :@!content }
    }

    method from-hash(%h --> ToolResult) {
        ToolResult.new(
            tool-call-id => ~(%h<tool-call-id> // %h<tool_call_id>),
            name         => ~%h<name>,
            status       => ~%h<status>,
            content      => (%h<content> // []).Array,
        )
    }

    method deep-clone(--> ToolResult) {
        ToolResult.new(
            tool-call-id => $!tool-call-id,
            name         => $!name,
            status       => $!status,
            content      => deep-copy(@!content),
        );
    }
}

#| Union type for content items.
subset ContentItem is export where Message | ToolCall | ToolResult;

#| A recorded occurrence during agent execution.
class Event is export {
    has Str $.id           = ~UUID.new(:version(4));
    has Str $.execution-id is required;
    has Num $.timestamp    = now.Num;
    has Str $.author       is required;  # "user" or agent name
    has     @.content;                   # Array of ContentItem

    method to-hash(--> Hash) {
        {
            :$!id,
            execution-id => $!execution-id,
            :$!timestamp,
            :$!author,
            content => @!content.map({ .^can('to-hash') ?? .to-hash !! $_ }).Array,
        }
    }

    method from-hash(%h --> Event) {
        my @items;
        for (%h<content> // []).list -> $c {
            if $c ~~ Associative {
                given $c<type> // '' {
                    when 'message'     { @items.push(Message.from-hash($c)) }
                    when 'tool_call'   { @items.push(ToolCall.from-hash($c)) }
                    when 'tool_result' { @items.push(ToolResult.from-hash($c)) }
                    default            { @items.push($c) }
                }
            } else {
                @items.push($c);
            }
        }
        Event.new(
            id           => %h<id> // ~UUID.new(:version(4)),
            execution-id => ~(%h<execution-id> // %h<execution_id> // ''),
            timestamp    => (%h<timestamp> // now).Num,
            author       => ~%h<author>,
            content      => @items,
        );
    }

    method deep-clone(--> Event) {
        Event.new(
            id           => $!id,
            execution-id => $!execution-id,
            timestamp    => $!timestamp,
            author       => $!author,
            content      => @!content.map({ deep-copy($_) }).Array,
        );
    }
}

=begin pod

=head1 NAME

ScratchAgents::Types - Core conversation and event data models

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Types;

my $msg   = Message.new(role => 'user', content => 'Hello');
my $call  = ToolCall.new(tool-call-id => 'tc_1', name => 'calculator', arguments => { operator => '+', first-number => 1, second-number => 2 });
my $res   = ToolResult.new(tool-call-id => 'tc_1', name => 'calculator', status => 'success', content => [3]);
my $event = Event.new(execution-id => 'exec_1', author => 'agent', content => [$msg, $call, $res]);
=end code

=head1 DESCRIPTION

Defines the fundamental serializable value types shared across the framework:

=head2 Classes & Subsets

=item C<Message> — Role (C<system>, C<user>, C<assistant>) and text content, with C<.to-hash>, C<.from-hash>, and C<.deep-clone>.
=item C<ToolCall> — Tool invocation request emitted by an LLM (C<tool-call-id>, C<name>, C<arguments>).
=item C<ToolResult> — Tool execution outcome (C<status>: C<success> or C<error>, plus C<content> array).
=item C<ContentItem> — Subset matching C<Message | ToolCall | ToolResult>.
=item C<Event> — Timestamped, UUID-identified execution log entry authored by C<user> or an agent.

=head2 Subroutines

=item C<deep-copy($val)> — Recursively clones nested Hashes, Arrays, and objects implementing C<.deep-clone>.

=end pod
