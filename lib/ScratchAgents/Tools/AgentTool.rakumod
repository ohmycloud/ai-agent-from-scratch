unit module ScratchAgents::Tools::AgentTool;

use JSON::Fast;
use ScratchAgents::Context;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Helpers;

#| Adapter that wraps an Agent as a tool.
class AgentTool is BaseTool is export {
    has $.agent        is required;
    has $.input-schema = Nil;

    submethod TWEAK() {
        my %parameters;
        if $!input-schema.defined {
            %parameters = $!input-schema;
        } else {
            %parameters = {
                type       => 'object',
                properties => {
                    request => {
                        type        => 'string',
                        description => 'The task or question to delegate',
                    },
                },
                required => ['request'],
            };
        }

        my $tool-def = format-tool-definition($!agent.name, $!agent.description, %parameters);
        self.name            = $!agent.name;
        self.description     = $!agent.description;
        self.tool-definition = $tool-def;
    }

    method execute(ExecutionContext $context, *%kwargs) {
        my $request = %kwargs<request> // to-json(%kwargs, :!pretty);
        my $result  = $!agent.run($request);
        $result.output;
    }
}
