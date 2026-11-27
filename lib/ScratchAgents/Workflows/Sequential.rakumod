unit module ScratchAgents::Workflows::Sequential;

use ScratchAgents::Agent;
use ScratchAgents::Context;

#| Run agents one after another, passing context from one to the next.
class SequentialWorkflow is Agent is export {
    has @.agents is rw;

    multi method new(@agents, Str :$name = 'sequential_workflow') {
        self.bless(:@agents, :$name);
    }

    multi method new(:@agents!, Str :$name = 'sequential_workflow') {
        self.bless(:@agents, :$name);
    }

    submethod TWEAK() {
        # Workflows do not use Agent's model or tool setup
        self.tools = [];
    }

    #| Execute all agents in sequence.
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

        my $result = AgentResult;
        for @!agents.kv -> $i, $agent {
            $context.final-result = Nil;
            $context.current-step = 0;

            if $i == 0 {
                $result = $agent.run($user-input, :$context, :$verbose);
            } else {
                $result = $agent.run(:$context, :$verbose);
            }
            $context = $result.context;
        }

        $result;
    }
}
