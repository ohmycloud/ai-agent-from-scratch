unit module ScratchAgents::Tools::MemoryTool;

use ScratchAgents::Context;
use ScratchAgents::Tools::Base;
use ScratchAgents::Types;

#| Tool that injects relevant past memories into the LLM request automatically.
class MemoryTool is BaseTool is export {
    method new() {
        self.bless(
            name            => 'recall_memory',
            description     => 'Search for past problem-solving records. Use this to check if similar problems were solved before.',
            tool-definition => Hash,  # Automatic injection only, no tool_definition
        );
    }

    method execute(ExecutionContext $context, Str :$query = '' --> Str) {
        return '' unless $context.memory-manager.defined;
        my @memories = $context.memory-manager.search($query, :top-k(3));
        return '' unless @memories;
        self!format-memories(@memories);
    }

    method !format-memories(@memories --> Str) {
        my @results;
        for @memories.kv -> $i, $mem {
            my $is-correct = $mem ~~ Associative ?? ?($mem<is_correct> // $mem<is-correct>) !! $mem.is-correct;
            my $summary    = $mem ~~ Associative ?? ~($mem<task_summary> // $mem<task-summary> // '') !! $mem.task-summary;
            my $approach   = $mem ~~ Associative ?? ~($mem<approach> // '') !! $mem.approach;
            my $answer     = $mem ~~ Associative ?? ~($mem<final_answer> // $mem<final-answer> // '') !! $mem.final-answer;
            my $err        = $mem ~~ Associative ?? ($mem<error_analysis> // $mem<error-analysis> // '') !! ($mem.error-analysis // '');

            my $status = $is-correct ?? 'Correct' !! 'Incorrect';
            my $text = qq:to/END/.trim;
            [Record { $i + 1 }]
            - Problem: $summary
            - Approach: $approach
            - Answer: $answer
            - Result: $status
            END
            if !$is-correct && $err {
                $text ~= "\n- Error analysis: $err";
            }
            @results.push($text);
        }
        @results.join("\n\n");
    }

    method process-llm-request(ExecutionContext $context, $request) {
        return unless $context.memory-manager.defined;

        my @user-msgs = $request.contents.grep({ $_ ~~ Message && .role eq 'user' });
        return unless @user-msgs;

        my $result = self.execute($context, query => @user-msgs[*-1].content);
        return unless $result;

        $request.append-instructions(
            "The following are records from similar problems solved in the past:\n"
            ~ "<PAST_EXPERIENCES>\n"
            ~ "$result\n"
            ~ "</PAST_EXPERIENCES>\n"
            ~ "Reference successful approaches and avoid approaches that led to failures."
        );
    }
}

=begin pod

=head1 NAME

ScratchAgents::Tools::MemoryTool - Automatic long-term memory injection tool

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Tools::MemoryTool;

my $tool = MemoryTool.new;
$tool.process-llm-request($context, $llm-request);
=end code

=head1 DESCRIPTION

C<MemoryTool> is a C<BaseTool> subclass with no LLM-facing C<tool-definition>. Instead, its C<.process-llm-request> hook queries C<$context.memory-manager> using the latest user message and appends a C<< <PAST_EXPERIENCES> >> block to the C<LlmRequest> instructions. Registered automatically by C<Agent> when C<memory-manager> is configured.

=end pod
