unit module ScratchAgents::Context;

use UUID;
use ScratchAgents::Types;

#| Central storage for all execution state.
class ExecutionContext is export {
    has Str  $.execution-id    = ~UUID.new(:version(4));
    has      @.events;                         # Array of Event
    has Int  $.current-step    is rw = 0;
    has      %.state           is rw;
    has      $.final-result    is rw = Nil;
    # CH06 session
    has      $.session         is rw = Nil;
    has      $.session-manager is rw = Nil;
    # CH06 long-term memory
    has      $.memory-manager  is rw = Nil;
    # CH08 code execution
    has      $.code-env        is rw = Nil;    # E2B Sandbox handle
    # CH09 agent transfer
    has Str  $.transfer-to     is rw = Str;
    has      %.transfer-tools  is rw;

    method add-event(Event $event) {
        @!events.push($event);
    }

    method increment-step() {
        $!current-step++;
    }

    #| Deep copy context (events and state) for isolated parallel branches.
    method deep-clone(--> ExecutionContext) {
        ExecutionContext.new(
            events          => @!events.map({ deep-copy($_) }).Array,
            state           => deep-copy(%!state),
            session         => $!session,
            session-manager => $!session-manager,
            memory-manager  => $!memory-manager,
        );
    }
}

#| Result of an agent execution.
class AgentResult is export {
    has                  $.output;              # Str or structured
    has ExecutionContext $.context is required;
    has Str              $.status  = 'complete'; # complete | pending_confirmation | error
    has                  @.pending-tool-calls;

    method to-hash(--> Hash) {
        { :$!output, status => $!status }
    }
}

#| A tool call awaiting user confirmation (CH06 human-in-the-loop).
class PendingToolCall is export {
    has ToolCall $.tool-call            is required;
    has Str      $.confirmation-message is required;

    method to-hash(--> Hash) {
        { tool-call => $!tool-call.to-hash, confirmation-message => $!confirmation-message }
    }

    method from-hash(%h --> PendingToolCall) {
        PendingToolCall.new(
            tool-call            => ToolCall.from-hash(%h<tool-call> // %h<tool_call>),
            confirmation-message => ~(%h<confirmation-message> // %h<confirmation_message>),
        )
    }
}

#| User's response to a pending tool call (CH06 human-in-the-loop).
class ToolConfirmation is export {
    has Str  $.tool-call-id        is required;
    has Bool $.approved            is required;
    has      %.modified-arguments;
    has Str  $.reason              = Str;
}
