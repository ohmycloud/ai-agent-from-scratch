unit module ScratchAgents::Eval::Gaia;

use ScratchAgents::Agent;
use ScratchAgents::Llm;
use ScratchAgents::Types;

#| Structured response model for GAIA evaluation.
class GaiaOutput is export {
    has Bool $.is-solvable       is required;
    has Str  $.unsolvable-reason = '';
    has Str  $.final-answer      = '';

    method from-hash(%h --> GaiaOutput) {
        GaiaOutput.new(
            is-solvable       => ?(%h<is_solvable> // %h<is-solvable> // False),
            unsolvable-reason => ~(%h<unsolvable_reason> // %h<unsolvable-reason> // ''),
            final-answer      => ~(%h<final_answer> // %h<final-answer> // ''),
        );
    }

    method json-schema(--> Hash) {
        {
            type       => 'object',
            properties => {
                is_solvable       => { type => 'boolean' },
                unsolvable_reason => { type => 'string' },
                final_answer      => { type => 'string' },
            },
            required => ['is_solvable'],
        }
    }
}

#| System prompt for GAIA evaluation.
constant $GAIA-PROMPT is export = q:to/END/.trim;
You are a general AI assistant. I will ask you a question.
First, determine if you can solve this problem with your current capabilities and set "is_solvable" accordingly.
If you can solve it, set "is_solvable" to true and provide your answer in "final_answer".
If you cannot solve it, set "is_solvable" to false and explain why in "unsolvable_reason".
Your final answer should be a number OR as few words as possible OR a comma-separated list of numbers and/or strings.
If you are asked for a number, don't use a comma to write your number neither use units such as $ or percent sign unless specified otherwise.
If you are asked for a string, don't use articles, neither abbreviations (e.g., for cities), and write the digits in plain text unless specified otherwise.
If you are asked for a comma-separated list, apply the above rules depending on whether the element is a number or a string.
END

my class AsyncSemaphore {
    has Channel $!ch .= new;

    submethod TWEAK(Int :$limit = 10) {
        $!ch.send(True) for ^$limit;
    }

    method acquire() { $!ch.receive }
    method release() { $!ch.send(True) }
}

my %PROVIDER-SEMAPHORES = (
    openai    => AsyncSemaphore.new(limit => 30),
    anthropic => AsyncSemaphore.new(limit => 10),
);

#| Extract provider name from model string.
sub get-provider(Str $model --> Str) is export {
    $model.starts-with('anthropic/') ?? 'anthropic' !! 'openai';
}

#| Check exact match between prediction and ground-truth answer (case-insensitive).
sub is-correct($prediction, Str $answer --> Bool) is export {
    return False unless $prediction.defined;
    (~$prediction).trim.lc eq $answer.trim.lc;
}

#| Solve a single problem and return structured GaiaOutput.
sub solve-problem(Str $model, Str $question, :$client --> GaiaOutput) is export {
    my $provider = get-provider($model);
    my $sem      = %PROVIDER-SEMAPHORES{$provider};
    $sem.acquire();
    LEAVE { $sem.release() }

    my $llm = $client // LlmClient.new(:$model);
    my $prompt = "$GAIA-PROMPT\n\nQuestion: $question";
    my $res = $llm.ask($prompt, response-format => GaiaOutput);
    $res ~~ GaiaOutput ?? $res !! GaiaOutput.from-hash($res);
}

#| Evaluate a single problem-model pair directly via LLM.
sub evaluate-gaia-single(%problem, Str $model, :$client --> Hash) is export {
    try {
        my $output = solve-problem($model, %problem<Question>, :$client);
        return {
            task_id           => %problem<task_id>,
            model             => $model,
            correct           => is-correct($output.final-answer, %problem<Final answer>),
            is_solvable       => $output.is-solvable,
            prediction        => $output.final-answer,
            answer            => %problem<Final answer>,
            unsolvable_reason => $output.unsolvable-reason,
        };
        CATCH {
            default {
                return {
                    task_id     => %problem<task_id>,
                    model       => $model,
                    correct     => False,
                    is_solvable => Nil,
                    prediction  => Nil,
                    answer      => %problem<Final answer>,
                    error       => .message,
                };
            }
        }
    }
}

#| Evaluate one problem using the full Agent loop and optional tools.
sub evaluate-gaia-agent-single(%problem, Str $model, @tools, :$client --> Hash) is export {
    try {
        my $agent = Agent.new(
            model        => ($client // LlmClient.new(:$model)),
            tools        => @tools,
            instructions => $GAIA-PROMPT,
            output-type  => GaiaOutput,
            max-steps    => 15,
        );
        my $result = $agent.run(%problem<Question>);
        my $output = $result.output;

        unless $output.defined {
            return {
                task_id     => %problem<task_id>,
                model       => $model,
                correct     => False,
                is_solvable => Nil,
                prediction  => Nil,
                answer      => %problem<Final answer>,
                error       => 'Agent did not return a final GaiaOutput',
                steps       => $result.context.current-step,
            };
        }

        $output = GaiaOutput.from-hash($output) unless $output ~~ GaiaOutput;

        return {
            task_id           => %problem<task_id>,
            model             => $model,
            correct           => is-correct($output.final-answer, %problem<Final answer>),
            is_solvable       => $output.is-solvable,
            prediction        => $output.final-answer,
            answer            => %problem<Final answer>,
            unsolvable_reason => $output.unsolvable-reason,
            steps             => $result.context.current-step,
        };
        CATCH {
            default {
                return {
                    task_id     => %problem<task_id>,
                    model       => $model,
                    correct     => False,
                    is_solvable => Nil,
                    prediction  => Nil,
                    answer      => %problem<Final answer>,
                    error       => .message,
                };
            }
        }
    }
}

#| Evaluate all models on all problems concurrently.
sub run-experiment(@problems, @models, :@tools --> Hash) is export {
    my @promises;

    for @problems -> %problem {
        for @models -> Str $model {
            if @tools.defined && @tools.elems {
                @promises.push(start { evaluate-gaia-agent-single(%problem, $model, @tools) });
            } else {
                @promises.push(start { evaluate-gaia-single(%problem, $model) });
            }
        }
    }

    await Promise.allof(@promises);

    my %results;
    %results{$_} = [] for @models;
    for @promises -> $p {
        my %res = $p.result;
        %results{%res<model>}.push(%res);
    }
    %results;
}

=begin pod

=head1 NAME

ScratchAgents::Eval::Gaia - GAIA benchmark evaluation runner and scoring utilities

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Eval::Gaia;

say is-correct(' 42 ', '42');
my %results = run-experiment(@problems, ['gpt-5.5'], :@tools);
=end code

=head1 DESCRIPTION

Implements GAIA benchmark evaluation with provider-level concurrency throttling:

=item C<GaiaOutput> — Structured answer schema (C<is-solvable>, C<unsolvable-reason>, C<final-answer>).
=item C<$GAIA-PROMPT> — Standard GAIA system instruction string.
=item C<< get-provider(Str $model --> Str) >> and C<< is-correct($prediction, Str $answer --> Bool) >> — Provider detection and normalized exact-match scoring.
=item C<solve-problem>, C<evaluate-gaia-single>, C<evaluate-gaia-agent-single>, and C<run-experiment> — Single-shot and full-agent concurrent benchmark runners backed by a channel-based semaphore.

=end pod
