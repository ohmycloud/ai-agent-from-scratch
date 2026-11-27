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

=begin pod

=head1 NAME

ScratchAgents::Workflows::Sequential - Sequential multi-agent pipeline workflow

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Workflows::Sequential;

my $workflow = SequentialWorkflow.new([$researcher, $writer]);
my $result   = $workflow.run('Write a summary of Raku concurrency.');
say $result.output;
=end code

=head1 DESCRIPTION

C<SequentialWorkflow> subclasses C<Agent> and runs an ordered list of agents one after another, resetting C<final-result> and C<current-step> before each stage while threading the shared C<ExecutionContext> forward.

=end pod
