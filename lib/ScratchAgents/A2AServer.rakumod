unit module ScratchAgents::A2AServer;

#| Base class for A2A agent executors.
class AgentExecutor is export {
    method execute($context, $event-queue) { ... }
}

#| Example A2A executor wrapping an Agent.
class MathAgentExecutor is AgentExecutor is export {
    has $.agent is required;

    #| Execute the agent and push results to the event queue (Channel or Array).
    method execute($context, $event-queue) {
        my $user-input = '';
        if $context.^can('message') || (($context ~~ Associative) && ($context<message>:exists)) {
            my $msg = $context ~~ Associative ?? $context<message> !! $context.message;
            for ($msg<parts> // []).list -> %part {
                if (%part<type> // '') eq 'text' {
                    $user-input = ~%part<text>;
                    last;
                }
            }
        }

        my $result = $!agent.run($user-input);

        if $event-queue.defined && $result.output.defined {
            my %artifact = (
                type  => 'artifact',
                parts => [{ type => 'text', text => ~$result.output },],
            );
            if $event-queue.^can('send') {
                $event-queue.send(%artifact);
            } elsif $event-queue.^can('push') {
                $event-queue.push(%artifact);
            }
        }
    }
}

=begin pod

=head1 NAME

ScratchAgents::A2AServer - A2A server executor adapters

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::A2AServer;

my $executor = MathAgentExecutor.new(agent => $agent);
my @queue;
$executor.execute({ message => { parts => [{ type => 'text', text => '6 * 7' },] } }, @queue);
=end code

=head1 DESCRIPTION

Provides server-side adapters for exposing a C<ScratchAgents::Agent> over the A2A protocol:

=item C<AgentExecutor> — Abstract base class defining C<method execute($context, $event-queue)>.
=item C<MathAgentExecutor> — Concrete executor that extracts text from the incoming A2A message, invokes C<$!agent.run>, and pushes the resulting artifact onto a C<Channel> or C<Array> event queue.

=end pod
