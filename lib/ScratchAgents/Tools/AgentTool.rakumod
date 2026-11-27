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

=begin pod

=head1 NAME

ScratchAgents::Tools::AgentTool - Adapter wrapping an Agent as a callable tool

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents::Tools::AgentTool;

my $tool = AgentTool.new(agent => $specialist-agent);
my $out  = $tool(ExecutionContext.new, request => 'Draft a summary');
=end code

=head1 DESCRIPTION

C<AgentTool> subclasses C<BaseTool> to expose any C<Agent> (or workflow) as a tool with an OpenAI-format C<tool-definition> (defaulting to a single required C<request> string parameter, or a custom C<input-schema>). Calling the tool delegates to C<$!agent.run($request)> and returns C<$result.output>.

=end pod
