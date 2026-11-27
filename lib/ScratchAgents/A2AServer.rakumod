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
