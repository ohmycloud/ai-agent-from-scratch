unit module ScratchAgents::Transfer;

use ScratchAgents::Context;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Helpers;

#| Create a transfer_to_agent tool from a list of transferable target agents.
sub create-transfer-tool(@target-agents --> FunctionTool) is export {
    my @target-names = @target-agents.map(*.name).Array;
    my @agent-descriptions;

    for @target-agents -> $agent {
        my $desc = $agent.description || $agent.instructions.substr(0, 100).subst("\n", ' ', :g);
        if $desc.chars > 100 {
            $desc = $desc.substr(0, 100) ~ '...';
        }
        @agent-descriptions.push("  - { $agent.name }: $desc");
    }

    my $agent-info = @agent-descriptions.join("\n");
    my $desc = qq:to/END/.trim;
    Transfers work to another agent.

    Use this tool when the current question belongs to another agent's specialty.

    Available agents:
    $agent-info
    END

    my sub transfer-to-agent(ExecutionContext $context, Str :$agent_name, Str :$agent-name --> Str) {
        my $target = $agent_name // $agent-name // '';
        unless $target eq any(@target-names) {
            return "Error: '$target' is not valid. Available: { @target-names.join(', ') }";
        }

        if !$context.transfer-to.defined {
            $context.transfer-to = $target;
            return "Transferring to $target...";
        } else {
            return "Transfer already requested to { $context.transfer-to }";
        }
    }

    my %tool-def = format-tool-definition(
        'transfer_to_agent',
        $desc,
        {
            type       => 'object',
            properties => {
                agent_name => {
                    type        => 'string',
                    description => 'The name of the target agent to transfer to',
                    enum        => @target-names,
                },
            },
            required => ['agent_name'],
        },
    );

    FunctionTool.new(
        func            => &transfer-to-agent,
        name            => 'transfer_to_agent',
        description     => $desc,
        tool-definition => %tool-def,
    );
}
