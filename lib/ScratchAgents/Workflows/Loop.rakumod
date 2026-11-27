unit module ScratchAgents::Workflows::Loop;

use ScratchAgents::Agent;
use ScratchAgents::Context;

#| Run agents repeatedly in a loop until stop condition or max-iterations is reached.
class LoopWorkflow is Agent is export {
    has      @.agents         is rw;
    has      &.stop-condition is rw = Nil;
    has Int  $.max-iterations is rw = 10;

    multi method new(@agents, :&stop-condition = Nil, Int :$max-iterations = 10, Str :$name = 'loop_workflow') {
        self.bless(:@agents, :&stop-condition, :$max-iterations, :$name);
    }

    multi method new(:@agents!, :&stop-condition = Nil, Int :$max-iterations = 10, Str :$name = 'loop_workflow') {
        self.bless(:@agents, :&stop-condition, :$max-iterations, :$name);
    }

    submethod TWEAK() {
        self.tools = [];
    }

    #| Execute agents in a loop.
    method run(
        $pos-user-input = Nil,
        :$user-input is copy = Nil,
        ExecutionContext :$context is copy = ExecutionContext,
        Bool :$verbose = False,
        *%kwargs,
        --> AgentResult
    ) {
        $user-input //= $pos-user-input;
        $context //= ExecutionContext.new;

        my $result         = AgentResult;
        my Bool $is-first  = True;

        for 1 .. $!max-iterations -> $iteration {
            for @!agents -> $agent {
                $context.final-result = Nil;
                $context.current-step = 0;

                if $is-first {
                    $result   = $agent.run($user-input, :$context, :$verbose);
                    $is-first = False;
                } else {
                    $result = $agent.run(:$context, :$verbose);
                }
                $context = $result.context;
            }

            if $result.defined && &!stop-condition.defined && (&!stop-condition)($result, $iteration) {
                last;
            }
        }

        $result;
    }
}
