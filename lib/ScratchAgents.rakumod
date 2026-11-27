unit module ScratchAgents;

need ScratchAgents::Types;
need ScratchAgents::Context;
need ScratchAgents::Llm;
need ScratchAgents::Agent;

my constant Message          is export := ScratchAgents::Types::Message;
my constant ToolCall         is export := ScratchAgents::Types::ToolCall;
my constant ToolResult       is export := ScratchAgents::Types::ToolResult;
my constant Event            is export := ScratchAgents::Types::Event;
my constant ContentItem      is export := ScratchAgents::Types::ContentItem;
sub         deep-copy(|c)    is export { ScratchAgents::Types::deep-copy(|c) }

my constant ExecutionContext is export := ScratchAgents::Context::ExecutionContext;
my constant AgentResult      is export := ScratchAgents::Context::AgentResult;
my constant PendingToolCall  is export := ScratchAgents::Context::PendingToolCall;
my constant ToolConfirmation is export := ScratchAgents::Context::ToolConfirmation;

my constant LlmClient        is export := ScratchAgents::Llm::LlmClient;
my constant LlmRequest       is export := ScratchAgents::Llm::LlmRequest;
my constant LlmResponse      is export := ScratchAgents::Llm::LlmResponse;
sub         build-messages(|c) is export { ScratchAgents::Llm::build-messages(|c) }

my constant Agent            is export := ScratchAgents::Agent::Agent;

=begin pod

=head1 NAME

ScratchAgents - Build an AI Agent from Scratch in Raku

=head1 SYNOPSIS

=begin code :lang<raku>
use ScratchAgents;
use ScratchAgents::Tools::Base;
use ScratchAgents::Tools::Calculator;

my $agent = Agent.new(
    model        => LlmClient.new(model => 'gpt-5.5'),
    tools        => [tool(&calculator)],
    instructions => 'Use tools whenever helpful.',
);

my $result = $agent.run('What is 128 * 42?');
say $result.output;
=end code

=head1 DESCRIPTION

C<ScratchAgents> is the top-level entry point for the Raku port of I<Build an AI Agent from Scratch>.
Importing this module re-exports the core symbols from:

=item L<ScratchAgents::Types> (C<Message>, C<ToolCall>, C<ToolResult>, C<Event>, C<ContentItem>, C<&deep-copy>)
=item L<ScratchAgents::Context> (C<ExecutionContext>, C<AgentResult>, C<PendingToolCall>, C<ToolConfirmation>)
=item L<ScratchAgents::Llm> (C<LlmClient>, C<LlmRequest>, C<LlmResponse>, C<&build-messages>)
=item L<ScratchAgents::Agent> (C<Agent>)

=end pod
