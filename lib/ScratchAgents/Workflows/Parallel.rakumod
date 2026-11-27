unit module ScratchAgents::Workflows::Parallel;

use ScratchAgents::Agent;
use ScratchAgents::Context;

#| Raised when one or more branches in a ParallelWorkflow do not complete cleanly.
class ParallelWorkflowIncomplete is Exception is export {
    has @.branch-results;  # Array of Pair(agent-name => AgentResult)
    has @.branch-errors;   # Array of Pair(agent-name => Exception)
    has Str $.message;

    submethod TWEAK() {
        my $states = @!branch-results
            .grep({ .value.status ne 'complete' })
            .map({ "{ .key }: { .value.status }" })
            .join(', ');
        $!message = "Parallel workflow did not complete ($states). "
            ~ "Inspect branch_results; automatic parallel resume is not supported.";
    }

    method message(--> Str) { $!message }
}

#| Run agents concurrently and combine results.
class ParallelWorkflow is Agent is export {
    has @.agents is rw;

    multi method new(@agents, Str :$name = 'parallel_workflow') {
        self.bless(:@agents, :$name);
    }

    multi method new(:@agents!, Str :$name = 'parallel_workflow') {
        self.bless(:@agents, :$name);
    }

    submethod TWEAK() {
        self.tools = [];
    }

    #| Execute all agents concurrently with isolated cloned contexts.
    method run(
        $pos-user-input = Nil,
        :$user-input is copy = Nil,
        ExecutionContext :$context = ExecutionContext,
        Bool :$verbose = False,
        *%kwargs,
        --> AgentResult
    ) {
        $user-input //= $pos-user-input;

        my $seed = $context.defined ?? $context !! ExecutionContext.new;
        my $existing-count = $seed.events.elems;

        my @branches = @!agents.map({ $seed.deep-clone }).Array;
        my @errors;

        my @promises = (^@!agents.elems).map(-> $i {
            my $agent  = @!agents[$i];
            my $branch = @branches[$i];
            start {
                my $err = Nil;
                my $res;
                try {
                    $res = $agent.run($user-input, context => $branch, :$verbose);
                    CATCH {
                        default {
                            $err = $_;
                            $res = AgentResult.new(output => Nil, context => $branch, status => 'error');
                        }
                    }
                }
                $err.defined ?? { error => $err, result => $res } !! $res;
            }
        });

        my @raw = await Promise.allof(@promises).then({ @promises.map(*.result).Array });
        my @results;

        for @raw.kv -> $i, $item {
            if $item ~~ Associative && ($item<error>:exists) {
                @errors.push(@!agents[$i].name => $item<error>);
                @results.push($item<result>);
            } else {
                @results.push($item);
            }
        }

        if @results.first({ .status ne 'complete' }) {
            my @branch-pairs = (^@!agents.elems).map({ @!agents[$_].name => @results[$_] });
            die ParallelWorkflowIncomplete.new(
                branch-results => @branch-pairs,
                branch-errors  => @errors,
            );
        }

        my $merged = $seed.deep-clone;
        my Bool $seen-user = False;

        for @results -> $res {
            my @new-events = $res.context.events[$existing-count .. *];
            for @new-events -> $event {
                if $event.author eq 'user' {
                    unless $seen-user {
                        $merged.add-event($event);
                        $seen-user = True;
                    }
                } else {
                    $merged.add-event($event);
                }
            }
        }

        my $combined = (^@!agents.elems).map({
            "[{ @!agents[$_].name }]\n{ @results[$_].output // '' }"
        }).join("\n\n");

        AgentResult.new(output => $combined, context => $merged);
    }
}
