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
